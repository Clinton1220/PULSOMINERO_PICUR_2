import 'package:flutter_test/flutter_test.dart';
import 'package:pulso_minero/models/analysis_result.dart';
import 'package:pulso_minero/models/sensor_data.dart';
import 'package:pulso_minero/rules/vibration_rules.dart';

void main() {
  final rules = VibrationRules();
  final start = DateTime(2026, 8, 25, 9, 0);

  SensorData sample(int milliseconds, double amplitude) => SensorData(
        timestamp: start.add(Duration(milliseconds: milliseconds)),
        accelerationX: amplitude,
        accelerationY: 0,
        accelerationZ: 0,
        inclination: 1.2,
      );

  test('una vibracion aislada no se clasifica como maquinaria', () {
    final result = rules.analyze([
      sample(0, 0.2),
      sample(500, 1.4),
      sample(1000, 0.2),
    ]);

    expect(result.classification, VibrationClassification.isolatedVibration);
    expect(result.riskLevel, 'BAJO');
  });

  test('una vibracion repetitiva sostenida se clasifica como maquinaria', () {
    final result = rules.analyze([
      sample(0, 0.2),
      sample(1000, 1.4),
      sample(2000, 0.2),
      sample(3000, 1.5),
      sample(4000, 0.2),
      sample(5000, 1.3),
      sample(6000, 0.2),
    ]);

    expect(result.classification, VibrationClassification.machineryVibration);
    expect(result.repetitions, 3);
    expect(result.reasons, isNotEmpty);
  });
}
