import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sensor_data.dart';
import 'sensor_service.dart';

class BleSensorService implements SensorService {
  BleSensorService({this.deviceName = 'PulsoMinero-ESP32'});

  static final serviceUuid = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final characteristicUuid =
      Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
  final String deviceName;
  final _controller = StreamController<SensorData>.broadcast();
  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _notificationSubscription;
  String _buffer = '';

  @override
  Stream<SensorData> get readings => _controller.stream;

  @override
  bool get isConnected => _device?.isConnected ?? false;

  @override
  Future<void> connect() async {
    final permissions =
        await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    if (permissions.values.any((permission) => !permission.isGranted)) {
      throw StateError('Concede permisos de Bluetooth para buscar el ESP32.');
    }
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw StateError('Activa Bluetooth para conectar el ESP32.');
    }
    await FlutterBluePlus.startScan(
        withServices: [serviceUuid], timeout: const Duration(seconds: 8));
    final result = await FlutterBluePlus.scanResults
        .expand((items) => items)
        .firstWhere((item) =>
            item.device.platformName == deviceName ||
            item.advertisementData.serviceUuids.contains(serviceUuid));
    await FlutterBluePlus.stopScan();
    _device = result.device;
    await _device!
        .connect(timeout: const Duration(seconds: 12), autoConnect: false);
    final services = await _device!.discoverServices();
    final service = services.firstWhere((item) => item.uuid == serviceUuid);
    final characteristic = service.characteristics
        .firstWhere((item) => item.uuid == characteristicUuid);
    await characteristic.setNotifyValue(true);
    _notificationSubscription =
        characteristic.lastValueStream.listen(_consumeBytes);
  }

  @override
  Future<void> disconnect() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _device?.disconnect();
    _device = null;
    _buffer = '';
  }

  @override
  void setDemoMode(DemoMode mode) {}

  void _consumeBytes(List<int> bytes) {
    _buffer += utf8.decode(bytes, allowMalformed: true);
    final lines = _buffer.split('\n');
    _buffer = lines.removeLast();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final map = jsonDecode(line.trim()) as Map<String, dynamic>;
        _controller.add(SensorData.fromJson(map, line.trim()));
      } on FormatException {
        // Descarta solo la trama dañada y continúa leyendo el stream BLE.
      }
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
