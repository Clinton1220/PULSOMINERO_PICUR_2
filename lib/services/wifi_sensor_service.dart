import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/sensor_data.dart';
import 'sensor_service.dart';

class WifiSensorService implements SensorService {
  WifiSensorService({this.host = '192.168.4.1', this.port = 81});

  final String host;
  final int port;
  final _controller = StreamController<SensorData>.broadcast();
  WebSocket? _webSocket;
  Socket? _rawSocket;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  String _buffer = '';

  @override
  Stream<SensorData> get readings => _controller.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    _isConnected = false;
    _buffer = '';

    // Intento 1: Conexión por WebSocket (ws://ip:port)
    try {
      final wsUrl = 'ws://$host:$port';
      _webSocket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      _isConnected = true;
      _subscription = _webSocket!.listen(
        (data) {
          if (data is String) {
            _processData(data);
          } else if (data is List<int>) {
            _processData(utf8.decode(data, allowMalformed: true));
          }
        },
        onError: (err) {
          disconnect();
        },
        onDone: () {
          disconnect();
        },
      );
      return;
    } catch (_) {
      // Si falla WebSocket, intentar socket TCP directo
    }

    // Intento 2: Conexión TCP Socket cruda (ip:port)
    try {
      _rawSocket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _isConnected = true;
      _subscription = _rawSocket!.listen(
        (data) {
          _processData(utf8.decode(data, allowMalformed: true));
        },
        onError: (err) {
          disconnect();
        },
        onDone: () {
          disconnect();
        },
      );
      return;
    } catch (e) {
      _isConnected = false;
      throw StateError('No se pudo conectar al ESP32 por Wi-Fi en $host:$port. Verifica que estés conectado a la red Wi-Fi del ESP32.');
    }
  }

  void _processData(String text) {
    _buffer += text;
    final lines = _buffer.split('\n');
    _buffer = lines.removeLast();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final map = jsonDecode(line.trim()) as Map<String, dynamic>;
        _controller.add(SensorData.fromJson(map, line.trim()));
      } catch (_) {
        // Ignorar tramas corruptas
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    await _subscription?.cancel();
    _subscription = null;
    await _webSocket?.close();
    _webSocket = null;
    await _rawSocket?.close();
    _rawSocket = null;
    _buffer = '';
  }

  @override
  void setDemoMode(DemoMode mode) {}

  @override
  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
