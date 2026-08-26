import '../models/sensor_data.dart';
import 'sensor_service.dart';

class BluetoothSensorService implements SensorService {
  BluetoothSensorService({required SensorService transport})
      : _transport = transport;

  final SensorService _transport;

  @override
  Stream<SensorData> get readings => _transport.readings;

  @override
  bool get isConnected => _transport.isConnected;

  @override
  Future<void> connect() => _transport.connect();

  @override
  Future<void> disconnect() => _transport.disconnect();

  @override
  void setDemoMode(DemoMode mode) => _transport.setDemoMode(mode);
}
