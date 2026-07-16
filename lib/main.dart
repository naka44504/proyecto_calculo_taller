import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Librería oficial para interactuar de forma segura con el entorno JavaScript de la Web
import 'dart:js' as js;

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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0E15),
        cardColor: const Color(0xFF161824),
      ),
      home: const MenuPrincipal(),
    );
  }
}

// =========================================================================
// PANTALLA 1: MENÚ PRINCIPAL
// =========================================================================
class MenuPrincipal extends StatelessWidget {
  const MenuPrincipal({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1123), Color(0xFF07080F)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.2), 
                          blurRadius: 40, 
                          spreadRadius: 10
                        )
                      ],
                    ),
                    child: const Icon(Icons.bolt_rounded, size: 100, color: Colors.cyanAccent),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'CRISTO FIT',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white),
                  ),
                  const Text(
                    'Sistema de Telemetría Dinámica Cinemática',
                    style: TextStyle(fontSize: 13, color: Colors.white38, letterSpacing: 1),
                  ),
                  const SizedBox(height: 60),
                  
                  _buildMenuCard(
                    context: context,
                    titulo: 'Modo ESP32 (Bluetooth)',
                    subtitulo: 'Sincronización externa con sensor MAX30102',
                    icono: Icons.bluetooth_connected,
                    colorInicio: const Color(0xFF1A2980),
                    colorFin: const Color(0xFF26D0CE),
                    alPresionar: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaMedicion(modo: 'ESP32'))),
                  ),
                  const SizedBox(height: 25),
                  
                  _buildMenuCard(
                    context: context,
                    titulo: 'Modo Sensor Interno',
                    subtitulo: 'Captura por Acelerómetro con Bypass Web',
                    icono: Icons.smartphone_rounded,
                    colorInicio: const Color(0xFF11998e),
                    colorFin: const Color(0xFF38ef7d),
                    alPresionar: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaMedicion(modo: 'TELEFONO'))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color colorInicio,
    required Color colorFin,
    required VoidCallback alPresionar,
  }) {
    return InkWell(
      onTap: alPresionar,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colorInicio, colorFin]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colorInicio.withOpacity(0.3),
              blurRadius: 15, 
              offset: const Offset(0, 8)
            )
          ],
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          child: Row(
            children: [
              Icon(icono, size: 40, color: Colors.white),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(subtitulo, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// PANTALLA 2: MEDIDOR Y MATRICES
// =========================================================================
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
  
  StreamSubscription<UserAccelerometerEvent>? suscripcionTelefonia;
  StreamSubscription<List<int>>? suscripcionESP32;
  BluetoothDevice? dispositivoESP32;

  double velocidadAcumulada = 0.0;
  DateTime? tiempoUltimaLectura;
  double tiempoInicialAbsoluto = 0.0;

  double? tiempoSeleccionado;
  double? velocidadCalculada;
  double? tasaCambioInstantanea; 
  String pulsoActualString = "Sin pulso";

  List<math.Point<double>> carreraPromedio = [];
  List<math.Point<double>> maximosLocales = [];
  List<math.Point<double>> minimosLocales = [];
  String ecuacionPromedio = "";
  String conclusionRendimiento = "";

  Future<void> iniciarMedicion() async {
    if (carrerasCompletadas >= 2) {
      mostrarAviso("Se alcanzaron las 2 tomas máximas del protocolo.");
      return;
    }

    if (widget.modo == 'TELEFONO' && kIsWeb) {
      try {
        // Validación del objeto global context en Dart/JS Interop para navegadores
        if (js.context.hasProperty('solicitarPermisoSensores')) {
          final dynamic resultadoJS = await js.context.callMethod('solicitarPermisoSensores');
          final bool permisoConcedido = resultadoJS ?? false;
          
          if (!permisoConcedido) {
            mostrarAviso("❌ Error: No se puede medir sin acceso a los sensores.");
            return;
          }
        }
        
        if (js.context.hasProperty('iniciarCapturaWeb')) {
          js.context.callMethod('iniciarCapturaWeb');
        }
      } catch (e) {
        debugPrint("Error inicializando JS: $e");
      }
    }

    setState(() {
      estaMidiendo = true;
      medicionActualTerminada = false;
      mostrarModuloResultadosGlobales = false;
      datosCarreraActual.clear(); 
      tiempoSeleccionado = null; 
      velocidadAcumulada = 0.0;
      pulsoActualString = widget.modo == 'TELEFONO' ? "Inactivo en Teléfono" : "Conectando BLE...";
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
    if (!kIsWeb) {
      suscripcionTelefonia?.cancel();
      suscripcionESP32?.cancel();
      dispositivoESP32?.disconnect();
    } else {
      try {
        if (js.context.hasProperty('detenerCapturaWeb')) {
          js.context.callMethod('detenerCapturaWeb');
        }
        
        if (js.context.hasProperty('datosSensoresWeb')) {
          final dynamic listaJS = js.context.callMethod('datosSensoresWeb');
          
          if (listaJS != null) {
            datosCarreraActual.clear();
            for (var item in listaJS) {
              double posX = (item['x'] as num).toDouble();
              double posY = (item['y'] as num).toDouble();
              datosCarreraActual.add(math.Point(posX, posY));
            }
          }
        }
      } catch (e) {
        debugPrint("Error extrayendo datos de JS: $e");
      }
    }
    
    setState(() {
      estaMidiendo = false;
      
      if (!errorHardware) {
        if (datosCarreraActual.length < 2) {
          mostrarAviso("⚠️ No se registraron datos reales del acelerómetro. Mueve el teléfono.");
          return;
        }

        medicionActualTerminada = true; 
        carrerasCompletadas++;
        
        if (carrerasCompletadas == 1) {
          datosCarrera1 = List.from(datosCarreraActual);
          mostrarAviso("✅ Carrera 1 guardada con datos reales.");
        } else if (carrerasCompletadas == 2) {
          datosCarrera2 = List.from(datosCarreraActual);
          mostrarAviso("✅ Carrera 2 guardada. Modelando polinomio...");
          _ejecutarModeladoPolinomialDinamico();
        }
      }
    });
  }

  void _activarEscuchaAcelerometro() {
    double tiempoReloj = 0.0;
    tiempoUltimaLectura = DateTime.now();

    if (kIsWeb) {
      // --- CAPTURA EN TIEMPO REAL PARA EL ENLACE WEB ---
      suscripcionTelefonia = userAccelerometerEventStream().listen(
        (UserAccelerometerEvent evento) {
          if (!estaMidiendo) return;
          
          final ahora = DateTime.now();
          final dt = ahora.difference(tiempoUltimaLectura!).inMilliseconds / 1000.0;
          tiempoUltimaLectura = ahora;
          tiempoReloj += dt;
          
          // Magnitud de la aceleración real 3D
          double aceleracionNeta = evento.x.abs() + evento.y.abs() + evento.z.abs();
          
          // Filtro pasa-altos dinámico
          if (aceleracionNeta > 0.35) {
            velocidadAcumulada += aceleracionNeta * dt;
          } else {
            // Decaimiento exponencial para simular reposo progresivo
            velocidadAcumulada *= math.exp(-0.8 * dt);
          }

          setState(() {
            datosCarreraActual.add(math.Point(tiempoReloj, velocidadAcumulada));
          });
        },
        onError: (error) {
          debugPrint("Error directo en sensor web: $error");
        },
        cancelOnError: true,
      );
    } else {
      // --- CAPTURA EN TIEMPO REAL NATIVA (USB) ---
      suscripcionTelefonia = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
        if (!estaMidiendo) return;
        
        final ahora = DateTime.now();
        final dt = ahora.difference(tiempoUltimaLectura!).inMilliseconds / 1000.0;
        tiempoUltimaLectura = ahora;
        tiempoReloj += dt;
        
        double acc = event.y; 
        if (acc.abs() < 0.2) acc = 0.0; // Filtro de ruido nativo
        velocidadAcumulada += acc * dt;
        
        if (velocidadAcumulada < 0) {
          velocidadAcumulada = 0.0;
        }
        
        setState(() {
          datosCarreraActual.add(math.Point(tiempoReloj, velocidadAcumulada));
        });
      });
    }
  }

  Future<void> _activarEscuchaESP32() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName == "ESP32_ATLETA") {
          FlutterBluePlus.stopScan();
          dispositivoESP32 = r.device;
          await dispositivoESP32!.connect();
          
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
                    if (aceleracionBLE.abs() < 0.2) {
                      velocidadAcumulada *= math.exp(-0.5 * dt);
                    } else {
                      velocidadAcumulada += aceleracionBLE * dt;
                    }

                    if (velocidadAcumulada < 0) {
                      velocidadAcumulada = 0.0;
                    }
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

    // =========================================================================
    // MOTOR DE CONCLUSIONES CINEMÁTICAS CLÍNICAS (MÁXIMA PRECISIÓN)
    // =========================================================================
    double velocidadMaxima = carreraPromedio.map((p) => p.y).reduce(math.max);
    double velocidadFinal = carreraPromedio.last.y;
    double factorDesaceleracion = (velocidadMaxima > 0) ? (1.0 - (velocidadFinal / velocidadMaxima)) : 0.0;
    
    // Cálculo de la variabilidad del ritmo (desviación estándar de los picos de velocidad)
    double variabilidadRitmo = 0.0;
    if (maximosLocales.isNotEmpty) {
      double promMaximos = maximosLocales.map((m) => m.y).reduce((a, b) => a + b) / maximosLocales.length;
      double sumaVarianza = maximosLocales.map((m) => math.pow(m.y - promMaximos, 2)).reduce((a, b) => a + b);
      variabilidadRitmo = math.sqrt(sumaVarianza / maximosLocales.length);
    }

    String diagnosticoRitmo = "";
    String mejora = "";

    if (totalExtremos >= 5) {
      diagnosticoRitmo = "Ritmo inestable y sumamente fraccionado (Señal asimétrica compleja). Se registraron $totalExtremos fluctuaciones en la zancada.";
      mejora = "Debes trabajar en la rigidez del core y la alineación pélvica para evitar la pérdida de energía lateral. Realiza drills de frecuencia de zancada con metrónomo.";
    } else if (totalExtremos >= 3) {
      diagnosticoRitmo = "Ritmo con oscilaciones cíclicas moderadas. Se observa una transición reactiva pero con ligeros baches en el apoyo.";
      mejora = "Ejecuta entrenamientos de fuerza reactiva (pliometría) para disminuir el tiempo de contacto con el suelo y estabilizar la fase de amortiguación.";
    } else {
      diagnosticoRitmo = "Transición fluida, uniforme y balística de velocidad. Ritmo de carrera altamente lineal y limpio.";
      mejora = "Tu eficiencia mecánica es excelente. Para incrementar la velocidad punta, enfócate en la potencia de empuje en la fase de despegue.";
    }

    // Análisis del factor de fatiga y pérdida tardía
    String analisisFatiga = "";
    if (factorDesaceleracion > 0.25) {
      analisisFatiga = " Caída crítica de velocidad del ${(factorDesaceleracion * 100).toStringAsFixed(1)}% en el tercio final de la carrera.";
      mejora += " Incorpora series de resistencia láctica y velocidad asistida para tolerar la fatiga neuromuscular tardía.";
    } else if (factorDesaceleracion > 0.10) {
      analisisFatiga = " Desaceleración moderada del ${(factorDesaceleracion * 100).toStringAsFixed(1)}% en la fase terminal.";
      mejora += " Optimiza tu zancada en fatiga enfocándote en mantener los hombros relajados y el braceo activo en los metros finales.";
    } else {
      analisisFatiga = " Excelente conservación de velocidad terminal (${(velocidadFinal).toStringAsFixed(1)} m/s). Pérdida por fatiga casi nula.";
    }

    String diagnosticoFinal = "📊 INFORME TÉCNICO CRISTO-FIT:\n\n"
        "• RENDIMIENTO GENERAL: $diagnosticoRitmo\n"
        "• ÍNDICE DE FATIGA:$analisisFatiga\n"
        "• DESVIACIÓN DE RITMO (Picos): ${variabilidadRitmo.toStringAsFixed(3)} m/s.\n\n"
        "💡 OPORTUNIDADES DE MEJORA:\n$mejora";

    setState(() {
      ecuacionPromedio = buildEcuacion;
      conclusionRendimiento = diagnosticoFinal;
    });
  }

  List<double> _resolverGaussJordan(List<List<double>> A, List<double> B) {
    int n = B.length;
    for (int i = 0; i < n; i++) {
      double pivot = A[i][i];
      if (pivot == 0) {
        pivot = 1e-9;
      } 
      for (int j = i; j < n; j++) {
        A[i][j] /= pivot;
      }
      B[i] /= pivot;

      for (int k = 0; k < n; k++) {
        if (k != i) {
          double factor = A[k][i];
          for (int j = i; j < n; j++) {
            A[k][j] -= factor * A[i][j];
          }
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
    while (i < datosCarreraActual.length - 1 && datosCarreraActual[i + 1].x < tTarget) {
      i++;
    }
    
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

  void mostrarAviso(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m), 
        backgroundColor: const Color(0xFF161824),
        behavior: SnackBarBehavior.floating,
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color colorTematico = widget.modo == 'ESP32' ? Colors.blueAccent : Colors.greenAccent;

    return Scaffold(
      appBar: AppBar(
        title: Text('TELEMETRÍA: ${widget.modo}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
        backgroundColor: const Color(0xFF111322),
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70), onPressed: reiniciarTodoElProceso)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Container(height: 8, decoration: BoxDecoration(color: carrerasCompletadas >= 1 ? Colors.greenAccent : Colors.white10, borderRadius: BorderRadius.circular(10), boxShadow: [if(carrerasCompletadas>=1) const BoxShadow(color: Colors.greenAccent, blurRadius: 8)]))),
                const SizedBox(width: 8),
                Expanded(child: Container(height: 8, decoration: BoxDecoration(color: carrerasCompletadas >= 2 ? Colors.greenAccent : Colors.white10, borderRadius: BorderRadius.circular(10), boxShadow: [if(carrerasCompletadas>=2) const BoxShadow(color: Colors.greenAccent, blurRadius: 8)]))),
              ],
            ),
            const SizedBox(height: 30),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (estaMidiendo || carrerasCompletadas >= 2) ? null : iniciarMedicion, 
                    style: ElevatedButton.styleFrom(backgroundColor: colorTematico, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                    child: Text(carrerasCompletadas == 0 ? 'ARRANCAR CORRIDA 1' : 'ARRANCAR CORRIDA 2', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    onPressed: estaMidiendo ? () => detenerMedicion() : null, 
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                    child: const Text('ABORTAR / PARAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            if (estaMidiendo) 
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: Text('🛰️ EN LÍNEA: Streaming de matriz inercial activo...', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5))),
              ),

            if (carrerasCompletadas == 2 && !estaMidiendo) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.analytics_outlined), 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white, padding: const EdgeInsets.all(18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
                onPressed: () => setState(() => mostrarModuloResultadosGlobales = true), 
                label: const Text('DECODIFICAR PRECISIÓN POLINÓMICA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            ],

            const SizedBox(height: 20),

            if (mostrarModuloResultadosGlobales) ...[
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161824),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.4), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(child: Text('ANÁLISIS DE ENTORNO POLINÓMICO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent, fontSize: 14, letterSpacing: 2))),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 240, 
                        width: double.infinity, 
                        child: CustomPaint(painter: GraficaPromedioPainter(datosPromedio: carreraPromedio, maximos: maximosLocales, minimos: minimosLocales)),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
                        width: double.infinity,
                        child: SelectableText(ecuacionPromedio, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.amberAccent)),
                      ),
                      const SizedBox(height: 15),
                      Text(conclusionRendimiento, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.white70)),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white10)),
                      Text('Picos (Máx): ${maximosLocales.isEmpty ? "Ninguno" : maximosLocales.map((m) => "(${m.x.toStringAsFixed(1)}s, ${m.y.toStringAsFixed(1)}m/s)").join(" | ")}', style: const TextStyle(fontSize: 11, color: Colors.greenAccent)),
                      const SizedBox(height: 6),
                      Text('Valles (Mín): ${minimosLocales.isEmpty ? "Ninguno" : minimosLocales.map((m) => "(${m.x.toStringAsFixed(1)}s, ${m.y.toStringAsFixed(1)}m/s)").join(" | ")}', style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
                    ],
                  ),
                ),
              ),
            ],

            if (medicionActualTerminada && !mostrarModuloResultadosGlobales) ...[
              const Center(child: Text("Toque cualquier cuadrante para evaluar derivadas locales:", style: TextStyle(fontSize: 12, color: Colors.white38))),
              const SizedBox(height: 12),
              GestureDetector(
                onTapDown: (details) => calcularDiferencialPorClick(details.localPosition.dx, context.size!.width - 40),
                child: Container(
                  height: 240, 
                  decoration: BoxDecoration(
                    color: const Color(0xFF161824), 
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorTematico.withOpacity(0.2)),
                  ), 
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CustomPaint(painter: GraficaPainter(datos: datosCarreraActual, tiempoMarcado: tiempoSeleccionado)),
                  ),
                ),
              ),
              
              if (tiempoSeleccionado != null) ...[
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF1A1D2E), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround, 
                        children: [
                          _buildDatoVisual(Icons.timer_outlined, 'INSTANTE (t)', tiempoSeleccionado! >= 180 ? '${(tiempoSeleccionado! / 60).toStringAsFixed(2)} min' : '${tiempoSeleccionado!.toStringAsFixed(2)}s', Colors.white),
                          _buildDatoVisual(Icons.speed_rounded, 'VELOCIDAD v(t)', '${velocidadCalculada!.toStringAsFixed(2)} m/s', Colors.cyanAccent),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround, 
                        children: [
                          _buildDatoVisual(Icons.trending_up_rounded, 'DERIVADA (dv/dt)', '${tasaCambioInstantanea!.toStringAsFixed(2)} m/s²', tasaCambioInstantanea! >= 0 ? Colors.greenAccent : Colors.redAccent),
                          _buildDatoVisual(Icons.favorite_border_rounded, 'TELE-PULSO', pulsoActualString, Colors.pinkAccent),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDatoVisual(IconData i, String t, String v, Color c) {
    return Column(
      children: [
        Icon(i, color: c, size: 24),
        const SizedBox(height: 6),
        Text(t, style: const TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.white38)),
        const SizedBox(height: 2),
        Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c)),
      ],
    );
  }
}

// =========================================================================
// CUSTOM PAINTERS CON FORMATO COMPATIBLE
// =========================================================================
class GraficaPainter extends CustomPainter {
  final List<math.Point<double>> datos; 
  final double? tiempoMarcado;
  GraficaPainter({required this.datos, required this.tiempoMarcado});
  
  @override 
  void paint(Canvas canvas, Size size) {
    if (datos.isEmpty) return;
    double xMin = datos.first.x, xMax = datos.last.x;
    double yMin = datos.map((p)=>p.y).reduce(math.min)-0.2;
    double yMax = datos.map((p)=>p.y).reduce(math.max)+0.5;
    
    if (xMax <= xMin) xMax = xMin + 1; 
    if (yMax <= yMin) yMax = yMin + 1;
    
    Offset mapP(math.Point<double> p) => Offset(((p.x-xMin)/(xMax-xMin))*size.width, size.height - ((p.y-yMin)/(yMax-yMin))*size.height);
    
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 1;
    for (int i = 1; i < 5; i++) {
      double yLine = size.height * (i / 5);
      canvas.drawLine(Offset(0, yLine), Offset(size.width, yLine), gridPaint);
    }

    final path = Path()..moveTo(mapP(datos.first).dx, mapP(datos.first).dy);
    for (var p in datos) {
      path.lineTo(mapP(p).dx, mapP(p).dy);
    }
    canvas.drawPath(path, Paint()..color = Colors.cyanAccent..strokeWidth = 3..style = PaintingStyle.stroke);
    
    bool usarMinutos = xMax >= 180;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    
    String etiquetaInicio = usarMinutos ? "0.0 min" : "0.0s";
    String etiquetaFin = usarMinutos ? "${(xMax / 60).toStringAsFixed(1)} min" : "${xMax.toStringAsFixed(1)}s";

    textPainter.text = TextSpan(text: etiquetaInicio, style: const TextStyle(color: Colors.white30, fontSize: 10));
    textPainter.layout();
    textPainter.paint(canvas, Offset(5, size.height - 15));

    textPainter.text = TextSpan(text: etiquetaFin, style: const TextStyle(color: Colors.white30, fontSize: 10));
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 5, size.height - 15));

    if (tiempoMarcado != null) {
      double xPos = ((tiempoMarcado!-xMin)/(xMax-xMin))*size.width;
      canvas.drawLine(Offset(xPos, 0), Offset(xPos, size.height), Paint()..color=Colors.amberAccent..strokeWidth=1.5);
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
    
    if (xMax <= xMin) xMax = xMin + 1; 
    if (yMax <= yMin) yMax = yMin + 1;
    
    Offset mapP(math.Point<double> p) => Offset(((p.x-xMin)/(xMax-xMin))*size.width, size.height - ((p.y-yMin)/(yMax-yMin))*size.height);
    
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 1;
    for (int i = 1; i < 5; i++) {
      double yLine = size.height * (i / 5);
      canvas.drawLine(Offset(0, yLine), Offset(size.width, yLine), gridPaint);
    }

    final path = Path()..moveTo(mapP(datosPromedio.first).dx, mapP(datosPromedio.first).dy);
    for (var p in datosPromedio) {
      path.lineTo(mapP(p).dx, mapP(p).dy);
    }
    canvas.drawPath(path, Paint()..color = Colors.purpleAccent..strokeWidth = 4..style = PaintingStyle.stroke);
    
    bool usarMinutos = xMax >= 180;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    String etiquetaFin = usarMinutos ? "${(xMax / 60).toStringAsFixed(1)} min" : "${xMax.toStringAsFixed(1)}s";

    textPainter.text = const TextSpan(text: "0.0s", style: TextStyle(color: Colors.white24, fontSize: 10));
    textPainter.layout();
    textPainter.paint(canvas, Offset(5, size.height - 15));

    textPainter.text = TextSpan(text: etiquetaFin, style: const TextStyle(color: Colors.white24, fontSize: 10));
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 5, size.height - 15));

    for (var m in maximos) { 
      canvas.drawCircle(mapP(m), 6, Paint()..color=Colors.greenAccent..style=PaintingStyle.fill); 
    }
    for (var m in minimos) { 
      canvas.drawCircle(mapP(m), 6, Paint()..color=Colors.redAccent..style=PaintingStyle.fill); 
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}