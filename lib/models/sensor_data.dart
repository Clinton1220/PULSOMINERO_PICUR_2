class SensorData {
  const SensorData({
    required this.timestamp,
    required this.accelerationX,
    required this.accelerationY,
    required this.accelerationZ,
    required this.inclination,
  });

  final DateTime timestamp;
  final double accelerationX;
  final double accelerationY;
  final double accelerationZ;
  final double inclination;

  double get magnitude => (accelerationX * accelerationX +
          accelerationY * accelerationY +
          accelerationZ * accelerationZ)
      .sqrt();
}

extension on double {
  double sqrt() {
    if (this <= 0) return 0;
    var value = this;
    var next = 0.5 * (value + this / value);
    for (var index = 0; index < 8; index++) {
      value = next;
      next = 0.5 * (value + this / value);
    }
    return next;
  }
}
