enum VibrationClassification {
  ambientNoise,
  isolatedVibration,
  machineryVibration,
  highRiskVibration,
}

class AnalysisResult {
  const AnalysisResult({
    required this.classification,
    required this.maximumAmplitude,
    required this.duration,
    required this.repetitions,
    required this.riskLevel,
    required this.reasons,
  });

  final VibrationClassification classification;
  final double maximumAmplitude;
  final Duration duration;
  final int repetitions;
  final String riskLevel;
  final List<String> reasons;

  String get title {
    switch (classification) {
      case VibrationClassification.ambientNoise:
        return 'Ruido ambiental';
      case VibrationClassification.isolatedVibration:
        return 'Vibración aislada';
      case VibrationClassification.machineryVibration:
        return 'Vibración de maquinaria';
      case VibrationClassification.highRiskVibration:
        return 'Vibración peligrosa';
    }
  }
}
