// lib/puente_js_web.dart
import 'dart:js_interop';

@JS('solicitarPermisoSensores')
external JSPromise<JSBoolean> solicitarPermisoSensoresJS();

@JS('iniciarCapturaWeb')
external void iniciarCapturaWebJS();

@JS('detenerCapturaWeb')
external void detenerCapturaWebJS();

@JS('datosSensoresWeb')
external JSArray datosSensoresWebJS();

// Funciones puente compatibles con firmas genéricas
Future<bool> solicitarPermisoSensores() async {
  final resultado = await solicitarPermisoSensoresJS().toDart;
  return resultado.toDart;
}

void iniciarCapturaWeb() => iniciarCapturaWebJS();
void detenerCapturaWeb() => detenerCapturaWebJS();
List<dynamic> datosSensoresWeb() => datosSensoresWebJS().toDart.cast<dynamic>();