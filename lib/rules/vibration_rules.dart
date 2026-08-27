import '../models/analysis_result.dart';
import '../models/sensor_data.dart';

class VibrationRules {
  static const safeThreshold = 1.0;
  static const warningThreshold = 2.0;
  static const machineryDuration = Duration(seconds: 2);
  static const machineryRepetitions = 3;

  AnalysisResult analyze(List<SensorData> samples) {
    if (samples.isEmpty) {
      return const AnalysisResult(
        classification: VibrationClassification.ambientNoise,
        maximumAmplitude: 0,
        duration: Duration.zero,
        repetitions: 0,
        riskLevel: 'BAJO',
        reasons: ['No hay muestras suficientes para analizar.'],
      );
    }

    final maximum = samples
        .map((sample) => sample.magnitude)
        .reduce((a, b) => a > b ? a : b);
    final duration = samples.last.timestamp.difference(samples.first.timestamp);
    final repetitions = _countPeaks(samples);
    final sustained =
        duration >= machineryDuration && repetitions >= machineryRepetitions;
    final highRisk = maximum >= warningThreshold && sustained;

    if (highRisk) {
      return AnalysisResult(
        classification: VibrationClassification.highRiskVibration,
        maximumAmplitude: maximum,
        duration: duration,
        repetitions: repetitions,
        riskLevel: 'ALTO',
        reasons: _reasons(maximum, duration, repetitions),
      );
    }
    if (sustained) {
      return AnalysisResult(
        classification: VibrationClassification.machineryVibration,
        maximumAmplitude: maximum,
        duration: duration,
        repetitions: repetitions,
        riskLevel: maximum >= safeThreshold ? 'MEDIO' : 'BAJO',
        reasons: _reasons(maximum, duration, repetitions),
      );
    }
    if (maximum >= safeThreshold) {
      return AnalysisResult(
        classification: VibrationClassification.isolatedVibration,
        maximumAmplitude: maximum,
        duration: duration,
        repetitions: repetitions,
        riskLevel: 'BAJO',
        reasons: [
          'El pico no se mantuvo durante el tiempo mínimo.',
          'El patrón no fue repetitivo.'
        ],
      );
    }
    return AnalysisResult(
      classification: VibrationClassification.ambientNoise,
      maximumAmplitude: maximum,
      duration: duration,
      repetitions: repetitions,
      riskLevel: 'BAJO',
      reasons: [
        'La amplitud está por debajo de 1.0 mm/s.',
        'No se detectó un patrón repetitivo.'
      ],
    );
  }

  int _countPeaks(List<SensorData> samples) {
    var peaks = 0;
    for (var index = 1; index < samples.length - 1; index++) {
      final previous = samples[index - 1].magnitude;
      final current = samples[index].magnitude;
      final next = samples[index + 1].magnitude;
      if (current > previous && current >= next && current >= safeThreshold) {
        peaks++;
      }
    }
    return peaks;
  }

  List<String> _reasons(double maximum, Duration duration, int repetitions) => [
        'Amplitud máxima: ${maximum.toStringAsFixed(2)} mm/s.',
        'Duración detectada: ${duration.inMilliseconds} ms.',
        'Picos repetitivos detectados: $repetitions.',
      ];
}
