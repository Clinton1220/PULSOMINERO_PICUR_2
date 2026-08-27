import 'dart:math' as math;

class SensorData {
  const SensorData({
    required this.timestamp,
    required this.accelerationX,
    required this.accelerationY,
    required this.accelerationZ,
    required this.inclination,
    this.roll = 0.0,
    this.gyroX = 0.0,
    this.gyroY = 0.0,
    this.gyroZ = 0.0,
    this.temperature = 25.0,
    this.gasPpm = 0.0,
    this.gasRaw = 0,
    this.gasVoltage = 0.0,
    this.mpuOk = true,
    this.mqOk = true,
    this.sequence = 0,
    this.rawPayload = '',
  });

  final DateTime timestamp;
  final double accelerationX;
  final double accelerationY;
  final double accelerationZ;
  final double inclination;
  final double roll;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double temperature;
  final double gasPpm;
  final int gasRaw;
  final double gasVoltage;
  final bool mpuOk;
  final bool mqOk;
  final int sequence;
  final String rawPayload;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'seq': sequence,
        'x': accelerationX,
        'y': accelerationY,
        'z': accelerationZ,
        'gx': gyroX,
        'gy': gyroY,
        'gz': gyroZ,
        'temp': temperature,
        'inclination': inclination,
        'roll': roll,
        'gas': gasPpm,
        'gas_raw': gasRaw,
        'gas_volt': gasVoltage,
        'mpu_ok': mpuOk,
        'mq_ok': mqOk,
      };

  factory SensorData.fromJson(Map<String, dynamic> json, [String raw = '']) =>
      SensorData(
        timestamp: json['timestamp'] is String
            ? DateTime.parse(json['timestamp'] as String)
            : (json['timestamp'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (json['timestamp'] as num).toInt())
                : DateTime.now()),
        accelerationX: (json['x'] as num?)?.toDouble() ?? 0.0,
        accelerationY: (json['y'] as num?)?.toDouble() ?? 0.0,
        accelerationZ: (json['z'] as num?)?.toDouble() ?? 0.0,
        inclination: (json['inclination'] as num?)?.toDouble() ?? 0.0,
        roll: (json['roll'] as num?)?.toDouble() ?? 0.0,
        gyroX: (json['gx'] as num?)?.toDouble() ?? 0.0,
        gyroY: (json['gy'] as num?)?.toDouble() ?? 0.0,
        gyroZ: (json['gz'] as num?)?.toDouble() ?? 0.0,
        temperature: (json['temp'] as num?)?.toDouble() ?? 25.0,
        gasPpm: (json['gas'] as num?)?.toDouble() ?? 0.0,
        gasRaw: (json['gas_raw'] as num?)?.toInt() ?? 0,
        gasVoltage: (json['gas_volt'] as num?)?.toDouble() ?? 0.0,
        mpuOk: json['mpu_ok'] is bool
            ? json['mpu_ok'] as bool
            : (json['mpu_ok'] == 'true'),
        mqOk: json['mq_ok'] is bool
            ? json['mq_ok'] as bool
            : (json['mq_ok'] == 'true'),
        sequence: (json['seq'] as num?)?.toInt() ??
            (json['sequence'] as num?)?.toInt() ??
            0,
        rawPayload: raw,
      );

  /// Magnitud total de la aceleración resultante: √(x² + y² + z²)
  double get magnitude => math.sqrt(accelerationX * accelerationX +
      accelerationY * accelerationY +
      accelerationZ * accelerationZ);

  /// Vibración dinámica neta (descontando la gravedad de 9.81 m/s²): |√(x²+y²+z²) - 9.81|
  double get dynamicVibration {
    final net = magnitude - 9.81;
    return net.abs();
  }
}
