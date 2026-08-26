import '../models/analysis_result.dart';
import '../models/sensor_data.dart';
import '../models/signal_features.dart';
import '../rules/vibration_rules.dart';

class AiService {
  AiService({VibrationRules? rules}) : rules = rules ?? VibrationRules();

  final VibrationRules rules;

  AnalysisResult analyze(List<SensorData> samples) {
    final result = rules.analyze(samples);
    final features = SignalFeatures.fromSamples(samples);
    final confidence = _confidence(features, result.classification);
    return AnalysisResult(
      classification: result.classification,
      maximumAmplitude: result.maximumAmplitude,
      duration: result.duration,
      repetitions: result.repetitions,
      riskLevel: result.riskLevel,
      reasons: [
        ...result.reasons,
        'RMS calculado: ${features.rms.toStringAsFixed(2)} mm/s.',
        'Frecuencia estimada: ${features.dominantFrequency.toStringAsFixed(2)} Hz.',
      ],
      confidence: confidence,
      features: features,
    );
  }

  double _confidence(
      SignalFeatures features, VibrationClassification classification) {
    if (features.repetitions == 0)
      return classification == VibrationClassification.ambientNoise ? .96 : .75;
    final durationFactor =
        (features.duration.inMilliseconds / 5000).clamp(0.0, 1.0);
    final repetitionFactor = (features.repetitions / 8).clamp(0.0, 1.0);
    return (.65 + durationFactor * .15 + repetitionFactor * .2).clamp(0.0, .99);
  }
}
