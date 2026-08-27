import 'dart:math' as math;

import 'sensor_data.dart';

class SignalFeatures {
  const SignalFeatures({
    required this.duration,
    required this.maximumAmplitude,
    required this.rms,
    required this.mean,
    required this.standardDeviation,
    required this.repetitions,
    required this.dominantFrequency,
    required this.inclination,
  });

  final Duration duration;
  final double maximumAmplitude;
  final double rms;
  final double mean;
  final double standardDeviation;
  final int repetitions;
  final double dominantFrequency;
  final double inclination;

  factory SignalFeatures.fromSamples(List<SensorData> samples) {
    if (samples.isEmpty) {
      return const SignalFeatures(
          duration: Duration.zero,
          maximumAmplitude: 0,
          rms: 0,
          mean: 0,
          standardDeviation: 0,
          repetitions: 0,
          dominantFrequency: 0,
          inclination: 0);
    }
    final values = samples.map((sample) => sample.magnitude).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final rms = math.sqrt(
        values.map((value) => value * value).reduce((a, b) => a + b) /
            values.length);
    final variance = values
            .map((value) => math.pow(value - mean, 2))
            .reduce((a, b) => a + b) /
        values.length;
    final duration = samples.last.timestamp.difference(samples.first.timestamp);
    final peaks = _peakCount(values, 1.0);
    final frequency = duration.inMilliseconds > 0
        ? peaks / duration.inMilliseconds * 1000
        : 0.0;
    return SignalFeatures(
      duration: duration,
      maximumAmplitude: values.reduce(math.max),
      rms: rms,
      mean: mean,
      standardDeviation: math.sqrt(variance),
      repetitions: peaks,
      dominantFrequency: frequency,
      inclination:
          samples.map((sample) => sample.inclination).reduce((a, b) => a + b) /
              samples.length,
    );
  }

  static int _peakCount(List<double> values, double threshold) {
    var peaks = 0;
    for (var index = 1; index < values.length - 1; index++) {
      if (values[index] > values[index - 1] &&
          values[index] >= values[index + 1] &&
          values[index] >= threshold) {
        peaks++;
      }
    }
    return peaks;
  }
}
