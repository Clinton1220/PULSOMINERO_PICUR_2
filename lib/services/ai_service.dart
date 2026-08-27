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

    final maxGas = samples.isEmpty
        ? 0.0
        : samples.map((s) => s.gasPpm).reduce((a, b) => a > b ? a : b);
    final String gasStatus;
    var risk = result.riskLevel;

    if (maxGas > 1000) {
      gasStatus =
          'ALERTA DE GAS: Concentración crítica (${maxGas.toStringAsFixed(0)} PPM).';
      risk = 'ALTO';
    } else if (maxGas > 600) {
      gasStatus =
          'PRECAUCIÓN DE GAS: Concentración moderada (${maxGas.toStringAsFixed(0)} PPM).';
      if (risk == 'BAJO') risk = 'MEDIO';
    } else {
      gasStatus =
          'Calidad de aire (MQ-135): Normal (${maxGas.toStringAsFixed(0)} PPM).';
    }

    return AnalysisResult(
      classification: result.classification,
      maximumAmplitude: result.maximumAmplitude,
      duration: result.duration,
      repetitions: result.repetitions,
      riskLevel: risk,
      reasons: [
        ...result.reasons,
        'RMS calculado: ${features.rms.toStringAsFixed(2)} mm/s.',
        'Frecuencia estimada: ${features.dominantFrequency.toStringAsFixed(2)} Hz.',
        gasStatus,
      ],
      confidence: confidence,
      features: features,
    );
  }

  double _confidence(
      SignalFeatures features, VibrationClassification classification) {
    if (features.repetitions == 0) {
      return classification == VibrationClassification.ambientNoise ? .96 : .75;
    }
    final durationFactor =
        (features.duration.inMilliseconds / 5000).clamp(0.0, 1.0);
    final repetitionFactor = (features.repetitions / 8).clamp(0.0, 1.0);
    return (.65 + durationFactor * .15 + repetitionFactor * .2).clamp(0.0, .99);
  }
}
