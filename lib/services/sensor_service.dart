import 'dart:async';
import 'dart:math';

import '../models/sensor_data.dart';

abstract class SensorService {
  Stream<SensorData> get readings;
  bool get isConnected;
  Future<void> connect();
  Future<void> disconnect();
  void setDemoMode(DemoMode mode);
  Future<void> dispose();
}

enum DemoMode { isolated, sustained }

class SensorSimulator implements SensorService {
  final _controller = StreamController<SensorData>.broadcast();
  final _random = Random();
  Timer? _timer;
  DemoMode _mode = DemoMode.isolated;
  DateTime _startedAt = DateTime.now();
  int _sampleIndex = 0;

  @override
  Stream<SensorData> get readings => _controller.stream;

  @override
  bool get isConnected => _timer != null;

  @override
  Future<void> connect() async {
    if (isConnected) return;
    _startedAt = DateTime.now();
    _sampleIndex = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final elapsed = _sampleIndex++;
      final isPeak =
          _mode == DemoMode.sustained ? elapsed % 4 == 2 : elapsed == 4;
      final amplitude = isPeak
          ? 1.25 + _random.nextDouble() * .35
          : .12 + _random.nextDouble() * .12;
      _controller.add(SensorData(
        timestamp: _startedAt.add(Duration(milliseconds: elapsed * 250)),
        accelerationX: amplitude,
        accelerationY: .05,
        accelerationZ: .02,
        inclination: 1.2 + (_random.nextDouble() - .5) * .1,
      ));
    });
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void setDemoMode(DemoMode mode) => _mode = mode;

  @override
  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
