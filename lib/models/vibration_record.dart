import 'analysis_result.dart';
import 'sensor_data.dart';

class VibrationRecord {
  const VibrationRecord({
    required this.id,
    required this.startedAt,
    required this.samples,
    required this.analysis,
  });

  final String id;
  final DateTime startedAt;
  final List<SensorData> samples;
  final AnalysisResult analysis;
}
