import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const MiAppVelocista());
}

class MiAppVelocista extends StatelessWidget {
  const MiAppVelocista({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Telemetría y Cálculo Avanzado',
      theme: ThemeData.dark(),
      home: const MenuPrincipal(),
    );
  }
}

// ==========================================
// PANTALLA 1: MENÚ PRINCIPAL
// ==========================================
class MenuPrincipal extends StatelessWidget {
  const MenuPrincipal({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menú de Telemetría'), backgroundColor: Colors.blueGrey[900]),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.analytics, size: 80, color: Colors.blue),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: const Icon(Icons.bluetooth),
              label: const Text('Modo ESP32 (Bluetooth)'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), backgroundColor: Colors.blue[800]),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaMedicion(modo: 'ESP32'))),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.smartphone),
              label: const Text('Modo Sensor Interno (Teléfono)'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), backgroundColor: Colors.green[800]),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaMedicion(modo: 'TELEFONO'))),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// PANTALLA 2: TOMA DE DATOS Y ANÁLISIS MULTICARRERA
// ==========================================
class PantallaMedicion extends StatefulWidget {
  final String modo; 
  const PantallaMedicion({super.key, required this.modo});

  @override
  State<PantallaMedicion> createState() => _PantallaMedicionState();
}

class _PantallaMedicionState extends State<PantallaMedicion> {
  List<math.Point<double>> datosCarreraActual = []; 
  List<math.Point<double>>? datosCarrera1;
  List<math.Point<double>>? datosCarrera2;
  int carrerasCompletadas = 0;
  bool mostrarModuloResultadosGlobales = false;

  bool estaMidiendo = false;
  bool medicionActualTerminada = false;
  
  // Suscripciones de hardware
  StreamSubscription<UserAccelerometerEvent>? suscripcionTelefonia;
  StreamSubscription<List<int>>? suscripcionESP32;
  BluetoothDevice? dispositivoESP32;

  double velocidadAcumulada = 0.0;
  DateTime? tiempoUltimaLectura;
  double tiempoInicialAbsoluto = 0.0;

  // Variables Diferenciales
  double? tiempoSeleccionado;
  double? velocidadCalculada;
  double? tasaCambioInstantanea; 
  String pulsoActualString = "Sin pulso";

  // Variables del Modelado Polinómico Adaptable
  List<math.Point<double>> carreraPromedio = [];
  List<math.Point<double>> maximosLocales = [];
  List<math.Point<double>> minimosLocales = [];
  String ecuacionPromedio = "";
  String conclusionRendimiento = "";

  Future<void> iniciarMedicion() async {
    if (carrerasCompletadas >= 2) {
      mostrarAviso("Ya has completado las 2 tomas de datos.");
      return;
    }

    setState(() {
      estaMidiendo = true;
      medicionActualTerminada = false;
      mostrarModuloResultadosGlobales = false;
      datosCarreraActual.clear(); 
      tiempoSeleccionado = null; 
      velocidadAcumulada = 0.0;
      pulsoActualString = widget.modo == 'TELEFONO' ? "No hay toma de pulso" : "Esperando BLE...";
    });

    try {
      if (widget.modo == 'ESP32') {
        await _activarEscuchaESP32();
      } else if (widget.modo == 'TELEFONO') {
        _activarEscuchaAcelerometro();
      }
    } catch (error) {
      detenerMedicion(errorHardware: true);
      mostrarAviso(error.toString().replaceAll("Exception: ", ""));
    }
  }

  void detenerMedicion({bool errorHardware = false}) {
    if (suscripcionTelefonia != null) suscripcionTelefonia!.cancel(); 
    if (suscripcionESP32 != null) suscripcionESP32!.cancel();
    if (dispositivoESP32 != null) dispositivoESP32!.disconnect();
    
    setState(() {
      estaMidiendo = false;
      if (!errorHardware && datosCarreraActual.length >= 2) {
        medicionActualTerminada = true; 
        carrerasCompletadas++;
        
        if (carrerasCompletadas == 1) {
          datosCarrera1 = List.from(datosCarreraActual);
        } else if (carrerasCompletadas == 2) {
          datosCarrera2 = List.from(datosCarreraActual);
          _ejecutarModeladoPolinomialDinamico();
        }
      }
    });
  }

  // ==========================================
  // HARDWARE: LECTURA DEL TELÉFONO CON DESACELERACIÓN
  // ==========================================
  void _activarEscuchaAcelerometro() {
    tiempoUltimaLectura = DateTime.now();
    tiempoInicialAbsoluto = DateTime.now().millisecondsSinceEpoch / 1000.0;

    suscripcionTelefonia = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      if (!estaMidiendo) return;
      DateTime ahora = DateTime.now();
      double dt = ahora.difference(tiempoUltimaLectura!).inMilliseconds / 1000.0;
      tiempoUltimaLectura = ahora;

      if (dt <= 0) return;

      // Usamos el eje Y principal del teléfono (avance hacia adelante/atrás)
      // Si el teléfono va en vertical en el cuerpo, Y o Z registran el empuje.
      double aceleracionEje = event.y; 

      // Filtro de ruido dinámico
      if (aceleracionEje.abs() < 0.2) {
        aceleracionEje = 0.0;
        // Aplicamos fricción natural del aire/suelo para que la velocidad decaer si no se acelera
        velocidadAcumulada *= math.exp(-0.4 * dt); 
      } else {
        // Sumamos (si acelera) o restamos (si desacelera/frena de golpe)
        velocidadAcumulada += aceleracionEje * dt;
      }

      // Evitamos velocidades negativas por descalibración física
      if (velocidadAcumulada < 0) velocidadAcumulada = 0.0;

      double tGrafica = (ahora.millisecondsSinceEpoch / 1000.0) - tiempoInicialAbsoluto;

      setState(() {
        datosCarreraActual.add(math.Point(tGrafica, velocidadAcumulada));
      });
    });
  }

  // ==========================================
  // HARDWARE: BLUETOOTH ESP32 CON DESACELERACIÓN
  // ==========================================
  Future<void> _activarEscuchaESP32() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName == "ESP32_ATLETA") {
          FlutterBluePlus.stopScan();
          dispositivoESP32 = r.device;
          await (dispositivoESP32 as dynamic).connect();
          
          List<BluetoothService> servicios = await dispositivoESP32!.discoverServices();
          for (BluetoothService s in servicios) {
            for (BluetoothCharacteristic c in s.characteristics) {
              if (c.properties.notify) {
                await c.setNotifyValue(true);
                
                tiempoUltimaLectura = DateTime.now();
                tiempoInicialAbsoluto = DateTime.now().millisecondsSinceEpoch / 1000.0;

                suscripcionESP32 = c.lastValueStream.listen((value) {
                  if (!estaMidiendo || value.isEmpty) return;
                  
                  String datosDecodificados = utf8.decode(value);
                  List<String> partes = datosDecodificados.split(',');
                  
                  if (partes.length >= 2) {
                    double aceleracionBLE = double.tryParse(partes[0]) ?? 0.0;
                    String pulsoBLE = partes[1].trim();

                    DateTime ahora = DateTime.now();
                    double dt = ahora.difference(tiempoUltimaLectura!).inMilliseconds / 1000.0;
                    tiempoUltimaLectura = ahora;

                    if (dt <= 0) return;

                    // Si mandas aceleración con signo (+/-) desde el ESP32 se resta sola.
                    // Si mandas solo magnitudes absolutas, procesamos la desaceleración por umbral:
                    if (aceleracionBLE.abs() < 0.2) {
                      velocidadAcumulada *= math.exp(-0.5 * dt); // Decaimiento exponencial controlado
                    } else {
                      velocidadAcumulada += aceleracionBLE * dt;
                    }

                    if (velocidadAcumulada < 0) velocidadAcumulada = 0.0;
                    double tGrafica = (ahora.millisecondsSinceEpoch / 1000.0) - tiempoInicialAbsoluto;

                    setState(() {
                      datosCarreraActual.add(math.Point(tGrafica, velocidadAcumulada));
                      pulsoActualString = "$pulsoBLE BPM";
                    });
                  }
                });
              }
            }
          }
        }
      }
    });
  }

  // ==========================================
  // MATEMÁTICA AVANZADA: REGRESIÓN DE GRADO VARIABLE
  // ==========================================
  void _ejecutarModeladoPolinomialDinamico() {
    if (datosCarrera1 == null || datosCarrera2 == null || datosCarrera1!.isEmpty || datosCarrera2!.isEmpty) return;
    carreraPromedio.clear(); maximosLocales.clear(); minimosLocales.clear();

    double limiteTiempo = math.min(datosCarrera1!.last.x, datosCarrera2!.last.x);
    double t = 0.0;
    while (t <= limiteTiempo) {
      double vProm = (_obtenerVelInterpolada(datosCarrera1!, t) + _obtenerVelInterpolada(datosCarrera2!, t)) / 2.0;
      carreraPromedio.add(math.Point(t, vProm));
      t += 0.20; 
    }

    if (carreraPromedio.length < 5) return;

    // Extracción de Picos (Máximos) y Valles (Mínimos por Desaceleración)
    for (int i = 1; i < carreraPromedio.length - 1; i++) {
      double vAnt = carreraPromedio[i - 1].y; 
      double vAct = carreraPromedio[i].y; 
      double vSig = carreraPromedio[i + 1].y;
      
      if (vAct > vAnt && vAct > vSig) {
        maximosLocales.add(carreraPromedio[i]);
      } else if (vAct < vAnt && vAct < vSig) {
        minimosLocales.add(carreraPromedio[i]);
      }
    }

    int totalExtremos = maximosLocales.length + minimosLocales.length;
    int gradoOptimal = (totalExtremos + 2).clamp(2, 6);

    int matrizSize = gradoOptimal + 1;
    List<List<double>> matrizX = List.generate(matrizSize, (_) => List.filled(matrizSize, 0.0));
    List<double> vectorY = List.filled(matrizSize, 0.0);

    for (var p in carreraPromedio) {
      for (int fila = 0; fila < matrizSize; fila++) {
        for (int col = 0; col < matrizSize; col++) {
          matrizX[fila][col] += math.pow(p.x, fila + col);
        }
        vectorY[fila] += p.y * math.pow(p.x, fila);
      }
    }

    List<double> coeficientes = _resolverGaussJordan(matrizX, vectorY);

    String buildEcuacion = "v(t) = ";
    Map<int, String> superindices = {2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶'};
    
    for (int i = gradoOptimal; i >= 0; i--) {
      double c = coeficientes[i];
      if (i == gradoOptimal) {
        buildEcuacion += "${c.toStringAsFixed(3)}t${superindices[i] ?? ''}";
      } else if (i > 1) {
        buildEcuacion += " ${c >= 0 ? '+' : ''}${c.toStringAsFixed(3)}t${superindices[i] ?? ''}";
      } else if (i == 1) {
        buildEcuacion += " ${c >= 0 ? '+' : ''}${c.toStringAsFixed(3)}t";
      } else {
        buildEcuacion += " ${c >= 0 ? '+' : ''}${c.toStringAsFixed(3)}";
      }
    }

    setState(() {
      ecuacionPromedio = buildEcuacion;
      
      if (gradoOptimal >= 4) {
        conclusionRendimiento = "Modelado Polinómico Adaptado (Grado $gradoOptimal). Se detectaron curvas asimétricas y pérdidas cinemáticas reales con $totalExtremos puntos críticos. El atleta presenta variaciones claras entre aceleración y desaceleración (Picos de zancada y fatiga).";
      } else if (gradoOptimal == 3) {
        conclusionRendimiento = "Ajuste Cúbico (Grado 3). Curva de aceleración inicial seguida de una fatiga/desaceleración progresiva estable al final del tramo.";
      } else {
        conclusionRendimiento = "Ajuste Parabólico Tradicional (Grado 2). Trayectoria balística simple de incremento uniforme.";
      }
    });
  }

  List<double> _resolverGaussJordan(List<List<double>> A, List<double> B) {
    int n = B.length;
    for (int i = 0; i < n; i++) {
      double pivot = A[i][i];
      if (pivot == 0) pivot = 1e-9; 
      for (int j = i; j < n; j++) A[i][j] /= pivot;
      B[i] /= pivot;

      for (int k = 0; k < n; k++) {
        if (k != i) {
          double factor = A[k][i];
          for (int j = i; j < n; j++) A[k][j] -= factor * A[i][j];
          B[k] -= factor * B[i];
        }
      }
    }
    return B;
  }

  double _obtenerVelInterpolada(List<math.Point<double>> serie, double t) {
    if (serie.isEmpty) return 0.0;
    if (t <= serie.first.x) return serie.first.y;
    if (t >= serie.last.x) return serie.last.y;
    for (int i = 0; i < serie.length - 1; i++) {
      if (t >= serie[i].x && t <= serie[i + 1].x) {
        return serie[i].y + ((t - serie[i].x) / (serie[i + 1].x - serie[i].x)) * (serie[i + 1].y - serie[i].y);
      }
    }
    return serie.last.y;
  }

  void calcularDiferencialPorClick(double xClic, double maxAncho) {
    if (datosCarreraActual.length < 2) return; 
    double tMin = datosCarreraActual.first.x;
    double tMax = datosCarreraActual.last.x;
    double tTarget = (tMin + (xClic / maxAncho) * (tMax - tMin)).clamp(tMin, tMax);

    int i = 0;
    while (i < datosCarreraActual.length - 1 && datosCarreraActual[i + 1].x < tTarget) i++;
    
    double dt = datosCarreraActual[i+1].x - datosCarreraActual[i].x;
    double dv = datosCarreraActual[i+1].y - datosCarreraActual[i].y;
    double derivada = (dt > 0) ? (dv / dt) : 0.0; 

    setState(() {
      tiempoSeleccionado = tTarget;
      velocidadCalculada = datosCarreraActual[i].y + derivada * (tTarget - datosCarreraActual[i].x);
      tasaCambioInstantanea = derivada;
    });
  }

  void reiniciarTodoElProceso() {
    setState(() {
      datosCarreraActual.clear(); datosCarrera1 = null; datosCarrera2 = null;
      carrerasCompletadas = 0; mostrarModuloResultadosGlobales = false;
      medicionActualTerminada = false; tiempoSeleccionado = null;
      ecuacionPromedio = ""; conclusionRendimiento = "";
    });
  }

  void mostrarAviso(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red[800]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Telemetría: ${widget.modo}'), backgroundColor: widget.modo == 'ESP32' ? Colors.blue[900] : Colors.green[900], actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: reiniciarTodoElProceso)]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Container(height: 12, decoration: BoxDecoration(color: carrerasCompletadas >= 1 ? Colors.green : Colors.grey[800], borderRadius: BorderRadius.circular(4)))),
                const SizedBox(width: 6),
                Expanded(child: Container(height: 12, decoration: BoxDecoration(color: carrerasCompletadas >= 2 ? Colors.green : Colors.grey[800], borderRadius: BorderRadius.circular(4)))),
              ],
            ),
            const SizedBox(height: 25),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: (estaMidiendo || carrerasCompletadas >= 2) ? null : iniciarMedicion, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), child: Text(carrerasCompletadas == 0 ? 'INICIAR TOMA 1' : 'INICIAR TOMA 2')),
                ElevatedButton(onPressed: estaMidiendo ? () => detenerMedicion() : null, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), child: const Text('TERMINAR')),
              ],
            ),
            const SizedBox(height: 20),

            if (estaMidiendo) const Center(child: Text('Recibiendo flujo cinemático real...', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),

            if (carrerasCompletadas == 2 && !estaMidiendo) ...[
              ElevatedButton.icon(icon: const Icon(Icons.functions), style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[700], padding: const EdgeInsets.all(15)), onPressed: () => setState(() => mostrarModuloResultadosGlobales = true), label: const Text('VER ANALÍTICA DE PRECISIÓN POLINÓMICA')),
            ],

            const Divider(height: 40),

            if (mostrarModuloResultadosGlobales) ...[
              Card(
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.purpleAccent, width: 1.5)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(child: Text('MODELO MULTI-PROMEDIO ADAPTABLE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent, fontSize: 16))),
                      const SizedBox(height: 12),
                      SizedBox(height: 220, width: double.infinity, child: CustomPaint(painter: GraficaPromedioPainter(datosPromedio: carreraPromedio, maximos: maximosLocales, minimos: minimosLocales))),
                      const SizedBox(height: 20),
                      SelectableText(ecuacionPromedio, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.amber)),
                      const SizedBox(height: 15),
                      Text(conclusionRendimiento, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.white70)),
                      const SizedBox(height: 15),
                      Text('Máximos (Picos): ${maximosLocales.isEmpty ? "0" : maximosLocales.map((m) => "(${m.x.toStringAsFixed(1)}s, ${m.y.toStringAsFixed(1)}m/s)").join(" | ")}', style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
                      const SizedBox(height: 4),
                      Text('Mínimos (Valles/Frenado): ${minimosLocales.isEmpty ? "0" : minimosLocales.map((m) => "(${m.x.toStringAsFixed(1)}s, ${m.y.toStringAsFixed(1)}m/s)").join(" | ")}', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                    ],
                  ),
                ),
              ),
            ],

            if (medicionActualTerminada && !mostrarModuloResultadosGlobales) ...[
              const Center(child: Text("Haz click en la gráfica para analizar diferenciales:", style: TextStyle(fontSize: 11, color: Colors.white60))),
              const SizedBox(height: 8),
              GestureDetector(
                onTapDown: (details) => calcularDiferencialPorClick(details.localPosition.dx, context.size!.width - 40),
                child: Container(height: 220, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: CustomPaint(painter: GraficaPainter(datos: datosCarreraActual, tiempoMarcado: tiempoSeleccionado))),
              ),
              if (tiempoSeleccionado != null) ...[
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                          _buildDato(Icons.timer, 'Instante (t)', '${tiempoSeleccionado!.toStringAsFixed(2)}s', Colors.white),
                          _buildDato(Icons.speed, 'v(t)', '${velocidadCalculada!.toStringAsFixed(2)} m/s', Colors.cyanAccent),
                        ]),
                        const SizedBox(height: 12),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                          _buildDato(Icons.trending_up, 'Aceleración (dv/dt)', '${tasaCambioInstantanea!.toStringAsFixed(2)} m/s²', tasaCambioInstantanea! >= 0 ? Colors.greenAccent : Colors.redAccent),
                          _buildDato(Icons.favorite, 'Frecuencia', pulsoActualString, widget.modo == 'TELEFONO' ? Colors.redAccent : Colors.pinkAccent),
                        ]),
                      ],
                    ),
                  ),
                )
              ]
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDato(IconData i, String t, String v, Color c) => Column(children: [Icon(i, color: c, size: 20), const SizedBox(height: 4), Text(t, style: const TextStyle(fontSize: 11, color: Colors.white54)), Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c))]);
}

// ==========================================
// PINTORES GRÁFICOS (CUSTOM PAINTERS)
// ==========================================
class GraficaPainter extends CustomPainter {
  final List<math.Point<double>> datos; final double? tiempoMarcado;
  GraficaPainter({required this.datos, required this.tiempoMarcado});
  
  @override 
  void paint(Canvas canvas, Size size) {
    if (datos.isEmpty) return;
    double xMin = datos.first.x, xMax = datos.last.x;
    double yMin = datos.map((p)=>p.y).reduce(math.min)-0.2;
    double yMax = datos.map((p)=>p.y).reduce(math.max)+0.5;
    
    if (xMax <= xMin) xMax = xMin + 1; if (yMax <= yMin) yMax = yMin + 1;
    Offset mapP(math.Point<double> p) => Offset(((p.x-xMin)/(xMax-xMin))*size.width, size.height - ((p.y-yMin)/(yMax-yMin))*size.height);
    
    final path = Path()..moveTo(mapP(datos.first).dx, mapP(datos.first).dy);
    for (var p in datos) { path.lineTo(mapP(p).dx, mapP(p).dy); }
    
    canvas.drawPath(path, Paint()..color = Colors.cyan..strokeWidth = 3..style = PaintingStyle.stroke);
    
    if (tiempoMarcado != null) {
      double xPos = ((tiempoMarcado!-xMin)/(xMax-xMin))*size.width;
      canvas.drawLine(Offset(xPos, 0), Offset(xPos, size.height), Paint()..color=Colors.amber..strokeWidth=1.5);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GraficaPromedioPainter extends CustomPainter {
  final List<math.Point<double>> datosPromedio, maximos, minimos;
  GraficaPromedioPainter({required this.datosPromedio, required this.maximos, required this.minimos});
  
  @override 
  void paint(Canvas canvas, Size size) {
    if (datosPromedio.isEmpty) return;
    double xMin = datosPromedio.first.x, xMax = datosPromedio.last.x;
    double yMin = datosPromedio.map((p)=>p.y).reduce(math.min)-0.3;
    double yMax = datosPromedio.map((p)=>p.y).reduce(math.max)+0.5;
    
    if (xMax <= xMin) xMax = xMin + 1; if (yMax <= yMin) yMax = yMin + 1;
    Offset mapP(math.Point<double> p) => Offset(((p.x-xMin)/(xMax-xMin))*size.width, size.height - ((p.y-yMin)/(yMax-yMin))*size.height);
    
    final path = Path()..moveTo(mapP(datosPromedio.first).dx, mapP(datosPromedio.first).dy);
    for (var p in datosPromedio) { path.lineTo(mapP(p).dx, mapP(p).dy); }
    
    canvas.drawPath(path, Paint()..color = Colors.purpleAccent..strokeWidth = 3.5..style = PaintingStyle.stroke);
    
    for (var m in maximos) { 
      canvas.drawCircle(mapP(m), 5, Paint()..color=Colors.greenAccent..style=PaintingStyle.fill); 
    }
    for (var m in minimos) { 
      canvas.drawCircle(mapP(m), 5, Paint()..color=Colors.redAccent..style=PaintingStyle.fill); 
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}