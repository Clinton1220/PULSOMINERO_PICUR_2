import '../models/analysis_result.dart';
import '../models/sensor_data.dart';
import '../rules/vibration_rules.dart';

class AiService {
  AiService({VibrationRules? rules}) : rules = rules ?? VibrationRules();

  final VibrationRules rules;

  AnalysisResult analyze(List<SensorData> samples) => rules.analyze(samples);
}
