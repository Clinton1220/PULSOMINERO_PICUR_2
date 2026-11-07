import 'dart:async';

import '../models/sensor_data.dart';

abstract class SensorService {
  Stream<SensorData> get readings;
  bool get isConnected;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> dispose();
}
