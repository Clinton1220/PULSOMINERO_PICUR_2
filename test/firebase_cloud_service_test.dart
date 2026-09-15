import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulso_minero/models/analysis_result.dart';
import 'package:pulso_minero/models/sensor_data.dart';
import 'package:pulso_minero/models/vibration_record.dart';
import 'package:pulso_minero/services/firebase_cloud_service.dart';
import 'package:pulso_minero/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FirebaseCloudService', () {
    final now = DateTime(2026, 9, 14, 12, 0, 0);
    final record = VibrationRecord(
      id: 'test_rec_123',
      startedAt: now,
      samples: [
        SensorData(
          timestamp: now,
          accelerationX: 1.5,
          accelerationY: 0.2,
          accelerationZ: 0.1,
          inclination: 3.5,
          gasPpm: 450.0,
        ),
        SensorData(
          timestamp: now.add(const Duration(milliseconds: 250)),
          accelerationX: 2.1,
          accelerationY: 0.3,
          accelerationZ: 0.2,
          inclination: 4.0,
          gasPpm: 520.0,
        ),
      ],
      analysis: const AnalysisResult(
        classification: VibrationClassification.machineryVibration,
        maximumAmplitude: 2.1,
        duration: Duration(seconds: 4),
        repetitions: 3,
        riskLevel: 'MEDIO',
        reasons: ['Vibración sostenida de maquinaria.'],
        confidence: 0.92,
      ),
    );

    test('construye el payload de Firestore con formato y campos requeridos', () {
      final service = FirebaseCloudService(projectId: 'mi-proyecto-test');
      final payload = service.buildFirestorePayload(record);

      expect(payload, contains('fields'));
      final fields = payload['fields'] as Map<String, dynamic>;

      expect(fields['id']['stringValue'], 'test_rec_123');
      expect(fields['riskLevel']['stringValue'], 'MEDIO');
      expect(fields['maxAmplitude']['doubleValue'], 2.1);
      expect(fields['maxGasPpm']['doubleValue'], 520.0);
      expect(fields['maxInclination']['doubleValue'], 4.0);
      expect(fields['sampleCount']['integerValue'], '2');
      expect(fields['confidence']['doubleValue'], 0.92);
      expect(fields['reasons']['arrayValue']['values'], isNotEmpty);
    });

    test('uploadVibrationRecord retorna true cuando la API responde HTTP 200',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.toString(), contains('ensayos_mineros/test_rec_123'));
        return http.Response(jsonEncode({'name': 'doc_created'}), 200);
      });

      final service = FirebaseCloudService(
        projectId: 'test-project',
        client: mockClient,
      );

      final success = await service.uploadVibrationRecord(record);
      expect(success, isTrue);
    });

    test('uploadVibrationRecord retorna false de forma segura si la API falla',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('Error de permisos o cuota', 403);
      });

      final service = FirebaseCloudService(
        projectId: 'test-project',
        client: mockClient,
      );

      final success = await service.uploadVibrationRecord(record);
      expect(success, isFalse);
    });
  });

  group('StorageService con Cloud Sync', () {
    test('saveRecord guarda el ensayo y actualiza isSyncedToCloud si hay conexión',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"ok": true}', 200);
      });

      final cloudService = FirebaseCloudService(
        projectId: 'test-project',
        client: mockClient,
      );

      final storage = StorageService(cloudService: cloudService);
      final now = DateTime(2026, 9, 14);
      final record = VibrationRecord(
        id: 'rec_offline_1',
        startedAt: now,
        samples: const [],
        analysis: const AnalysisResult(
          classification: VibrationClassification.ambientNoise,
          maximumAmplitude: 0.1,
          duration: Duration.zero,
          repetitions: 0,
          riskLevel: 'BAJO',
          reasons: [],
        ),
      );

      final synced = await storage.saveRecord(record);
      expect(synced, isTrue);
      expect(storage.records.first.isSyncedToCloud, isTrue);
      expect(storage.pendingSyncCount, 0);
    });
  });
}
