import 'signal_features.dart';

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
    this.confidence = 0,
    this.features,
  });

  final VibrationClassification classification;
  final double maximumAmplitude;
  final Duration duration;
  final int repetitions;
  final String riskLevel;
  final List<String> reasons;
  final double confidence;
  final SignalFeatures? features;

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

  Map<String, dynamic> toJson() => {
        'classification': classification.name,
        'maximumAmplitude': maximumAmplitude,
        'durationMs': duration.inMilliseconds,
        'repetitions': repetitions,
        'riskLevel': riskLevel,
        'reasons': reasons,
        'confidence': confidence,
      };

  factory AnalysisResult.fromJson(Map<String, dynamic> json) => AnalysisResult(
        classification: VibrationClassification.values
            .byName(json['classification'] as String),
        maximumAmplitude: (json['maximumAmplitude'] as num).toDouble(),
        duration: Duration(milliseconds: json['durationMs'] as int),
        repetitions: json['repetitions'] as int,
        riskLevel: json['riskLevel'] as String,
        reasons: (json['reasons'] as List<dynamic>).cast<String>(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
}
