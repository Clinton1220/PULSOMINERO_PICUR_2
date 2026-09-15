import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/vibration_record.dart';

/// Servicio de integración en la nube con Firebase Firestore mediante API REST.
/// Permite sincronizar ensayos mineros sin requerir archivos google-services.json
/// ni dependencias de Gradle complejas.
class FirebaseCloudService {
  FirebaseCloudService({
    this.projectId = 'pulsominero-7c202',
    http.Client? client,
  }) : _client = client ?? http.Client();

  String projectId;
  final http.Client _client;

  /// URL base de Firestore Database REST API
  String get firestoreEndpoint =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/ensayos_mineros';

  /// Sube un ensayo minero a la colección `ensayos_mineros` en Firebase Firestore.
  /// Retorna `true` si se subió correctamente o `false` si no hubo conexión o falló.
  Future<bool> uploadVibrationRecord(VibrationRecord record) async {
    try {
      final docUrl = Uri.parse('$firestoreEndpoint/${record.id}');
      final payload = buildFirestorePayload(record);

      developer.log(
        'Subiendo ensayo ${record.id} a Firebase Firestore ($projectId)...',
        name: 'FirebaseCloudService',
      );

      final response = await _client
          .patch(
            docUrl,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        developer.log(
          '✅ Ensayo ${record.id} sincronizado exitosamente en Firebase (HTTP ${response.statusCode})',
          name: 'FirebaseCloudService',
        );
        return true;
      } else {
        developer.log(
          '⚠️ Firebase respondió con código ${response.statusCode}: ${response.body}',
          name: 'FirebaseCloudService',
        );
        return false;
      }
    } on TimeoutException {
      developer.log(
        '⚠️ Tiempo de espera agotado al conectar con Firebase (posible falta de internet)',
        name: 'FirebaseCloudService',
      );
      return false;
    } catch (e) {
      developer.log(
        '⚠️ Error de red al sincronizar con Firebase: $e',
        name: 'FirebaseCloudService',
      );
      return false;
    }
  }

  /// Construye el payload en formato estricto de Firestore REST API.
  Map<String, dynamic> buildFirestorePayload(VibrationRecord record) {
    double maxGas = 0.0;
    double maxInc = 0.0;

    for (final s in record.samples) {
      if (s.gasPpm > maxGas) maxGas = s.gasPpm;
      if (s.inclination.abs() > maxInc) maxInc = s.inclination.abs();
    }

    return {
      'fields': {
        'id': {'stringValue': record.id},
        'startedAt': {'stringValue': record.startedAt.toIso8601String()},
        'sampleCount': {'integerValue': record.samples.length.toString()},
        'maxAmplitude': {'doubleValue': record.analysis.maximumAmplitude},
        'riskLevel': {'stringValue': record.analysis.riskLevel},
        'classification': {'stringValue': record.analysis.title},
        'confidence': {'doubleValue': record.analysis.confidence},
        'maxGasPpm': {'doubleValue': maxGas},
        'maxInclination': {'doubleValue': maxInc},
        'repetitions': {'integerValue': record.analysis.repetitions.toString()},
        'durationMs': {
          'integerValue': record.analysis.duration.inMilliseconds.toString()
        },
        'reasons': {
          'arrayValue': {
            'values': record.analysis.reasons
                .map((r) => {'stringValue': r})
                .toList(),
          }
        },
        'syncedAt': {'stringValue': DateTime.now().toIso8601String()},
        'appSource': {'stringValue': 'PulsoMinero-Flutter-App'},
      }
    };
  }

  void dispose() {
    _client.close();
  }
}
