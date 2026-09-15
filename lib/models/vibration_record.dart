import 'analysis_result.dart';
import 'sensor_data.dart';

class VibrationRecord {
  const VibrationRecord({
    required this.id,
    required this.startedAt,
    required this.samples,
    required this.analysis,
    this.isSyncedToCloud = false,
  });

  final String id;
  final DateTime startedAt;
  final List<SensorData> samples;
  final AnalysisResult analysis;
  final bool isSyncedToCloud;

  VibrationRecord copyWith({
    String? id,
    DateTime? startedAt,
    List<SensorData>? samples,
    AnalysisResult? analysis,
    bool? isSyncedToCloud,
  }) =>
      VibrationRecord(
        id: id ?? this.id,
        startedAt: startedAt ?? this.startedAt,
        samples: samples ?? this.samples,
        analysis: analysis ?? this.analysis,
        isSyncedToCloud: isSyncedToCloud ?? this.isSyncedToCloud,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'samples': samples.map((sample) => sample.toJson()).toList(),
        'analysis': analysis.toJson(),
        'isSyncedToCloud': isSyncedToCloud,
      };

  factory VibrationRecord.fromJson(Map<String, dynamic> json) =>
      VibrationRecord(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        samples: (json['samples'] as List<dynamic>)
            .map(
                (sample) => SensorData.fromJson(sample as Map<String, dynamic>))
            .toList(),
        analysis:
            AnalysisResult.fromJson(json['analysis'] as Map<String, dynamic>),
        isSyncedToCloud: (json['isSyncedToCloud'] as bool?) ?? false,
      );
}
