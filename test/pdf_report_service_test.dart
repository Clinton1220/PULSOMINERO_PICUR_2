import 'package:flutter_test/flutter_test.dart';
import 'package:pulso_minero/models/analysis_result.dart';
import 'package:pulso_minero/models/sensor_data.dart';
import 'package:pulso_minero/models/vibration_record.dart';
import 'package:pulso_minero/services/pdf_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfReportService', () {
    final now = DateTime(2026, 9, 14, 15, 30);
    final sampleRecord = VibrationRecord(
      id: 'ensayo_test_pdf_01',
      startedAt: now,
      isSyncedToCloud: true,
      samples: [
        SensorData(
          timestamp: now,
          accelerationX: 1.25,
          accelerationY: 0.1,
          accelerationZ: 0.05,
          inclination: 2.3,
          gasPpm: 420.0,
        ),
        SensorData(
          timestamp: now.add(const Duration(milliseconds: 250)),
          accelerationX: 1.85,
          accelerationY: 0.15,
          accelerationZ: 0.08,
          inclination: 2.5,
          gasPpm: 460.0,
        ),
      ],
      analysis: const AnalysisResult(
        classification: VibrationClassification.machineryVibration,
        maximumAmplitude: 1.85,
        duration: Duration(seconds: 3),
        repetitions: 4,
        riskLevel: 'MEDIO',
        reasons: [
          'Vibración periódica continua.',
          'Amplitud sostenida característica de motor diésel.'
        ],
        confidence: 0.94,
      ),
    );

    test('generateSingleRecordPdf produce un archivo PDF válido en bytes',
        () async {
      final bytes =
          await PdfReportService.generateSingleRecordPdf(sampleRecord);

      expect(bytes, isNotEmpty);
      // Los primeros 4 bytes de un PDF estándar corresponden al encabezado '%PDF' (0x25, 0x50, 0x44, 0x46)
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    });

    test('generateConsolidatedPdf produce un archivo PDF con múltiples ensayos',
        () async {
      final bytes = await PdfReportService.generateConsolidatedPdf(
        [sampleRecord],
      );

      expect(bytes, isNotEmpty);
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    });
  });
}
