import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/sensor_data.dart';
import '../models/vibration_record.dart';
import 'ai_service.dart';
import 'alert_sound_service.dart';
import 'ble_sensor_service.dart';
import 'sensor_service.dart';
import 'storage_service.dart';
import 'wifi_sensor_service.dart';

enum ConnectionType { none, ble, wifi }

class SensorController extends ChangeNotifier {
  SensorController({required this.storage});

  final StorageService storage;
  final ai = AiService();
  final alertSoundService = AlertSoundService();

  final List<SensorData> samples = [];
  SensorService? _sensor;
  StreamSubscription<SensorData>? _subscription;

  ConnectionType activeConnection = ConnectionType.none;
  bool isCapturing = false;
  bool isPaused = false;
  String wifiIp = '192.168.4.1';
  AnalysisResult? lastResult;

  // Filtro de Suavizado EMA
  bool isFilterEnabled = true;
  static const double smoothAlpha = 0.28;
  double? emaMagnitude;
  double? emaX;
  double? emaY;
  double? emaZ;
  double? emaGas;
  double? emaPitch;
  double? emaRoll;

  SensorData? get latestReading => samples.isNotEmpty ? samples.last : null;

  double get currentVibration {
    if (isFilterEnabled && emaMagnitude != null) return emaMagnitude!;
    return latestReading?.dynamicVibration ?? 0.0;
  }

  double get currentGas {
    if (isFilterEnabled && emaGas != null) return emaGas!;
    return latestReading?.gasPpm ?? 0.0;
  }

  double get currentPitch {
    if (isFilterEnabled && emaPitch != null) return emaPitch!;
    return latestReading?.inclination ?? 0.0;
  }

  double get currentRoll {
    if (isFilterEnabled && emaRoll != null) return emaRoll!;
    return latestReading?.roll ?? 0.0;
  }

  double get currentTemp => latestReading?.temperature ?? 24.0;
  double get currentAccelX => latestReading?.accelerationX ?? 0.0;
  double get currentAccelY => latestReading?.accelerationY ?? 0.0;
  double get currentAccelZ => latestReading?.accelerationZ ?? 0.0;

  bool get isConnected => activeConnection != ConnectionType.none;

  bool get isCritical => currentVibration >= 2.0 || currentGas > 1000.0;

  bool get isWarning =>
      !isCritical && (currentVibration >= 1.0 || currentGas > 600.0);

  String get riskLabel {
    if (!isConnected) return 'DESCONECTADO';
    if (isCritical) return 'CRÍTICO';
    if (isWarning) return 'PRECAUCIÓN';
    return 'SEGURO';
  }

  String get connectionLabel {
    switch (activeConnection) {
      case ConnectionType.wifi:
        return 'Wi-Fi (ESP32)';
      case ConnectionType.ble:
        return 'Bluetooth BLE';
      case ConnectionType.none:
        return 'Desconectado';
    }
  }

  void _resetEma() {
    emaMagnitude = null;
    emaX = null;
    emaY = null;
    emaZ = null;
    emaGas = null;
    emaPitch = null;
    emaRoll = null;
  }

  void _updateEma(SensorData reading) {
    final currentMag = reading.dynamicVibration;
    final adjX = reading.accelerationX;
    final adjY = reading.accelerationY;
    final adjZ = reading.accelerationZ;

    if (emaMagnitude == null) {
      emaMagnitude = currentMag;
      emaX = adjX;
      emaY = adjY;
      emaZ = adjZ;
      emaGas = reading.gasPpm;
      emaPitch = reading.inclination;
      emaRoll = reading.roll;
    } else {
      emaMagnitude =
          (smoothAlpha * currentMag) + ((1.0 - smoothAlpha) * emaMagnitude!);
      emaX = (smoothAlpha * adjX) + ((1.0 - smoothAlpha) * emaX!);
      emaY = (smoothAlpha * adjY) + ((1.0 - smoothAlpha) * emaY!);
      emaZ = (smoothAlpha * adjZ) + ((1.0 - smoothAlpha) * emaZ!);
      emaGas = (smoothAlpha * reading.gasPpm) + ((1.0 - smoothAlpha) * emaGas!);
      emaPitch =
          (smoothAlpha * reading.inclination) + ((1.0 - smoothAlpha) * emaPitch!);
      emaRoll = (smoothAlpha * reading.roll) + ((1.0 - smoothAlpha) * emaRoll!);
    }
  }

  void toggleFilter() {
    isFilterEnabled = !isFilterEnabled;
    if (isFilterEnabled) _resetEma();
    notifyListeners();
  }

  void togglePause() {
    isPaused = !isPaused;
    if (isPaused) {
      alertSoundService.stop();
    }
    notifyListeners();
  }

  Future<void> connectBle() async {
    if (isCapturing) return;
    await alertSoundService.stop();
    samples.clear();
    _resetEma();
    lastResult = null;
    await _subscription?.cancel();
    await _sensor?.dispose();
    _sensor = BleSensorService();
    _listenToSensor();
    try {
      await _sensor!.connect();
      activeConnection = ConnectionType.ble;
      isCapturing = true;
      isPaused = false;
      notifyListeners();
    } on StateError {
      await _sensor?.disconnect();
      activeConnection = ConnectionType.none;
      isCapturing = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> connectWifi(String ip) async {
    if (isCapturing) return;
    await alertSoundService.stop();
    wifiIp = ip;
    samples.clear();
    _resetEma();
    lastResult = null;
    await _subscription?.cancel();
    await _sensor?.dispose();
    _sensor = WifiSensorService(host: ip, port: 81);
    _listenToSensor();
    try {
      await _sensor!.connect();
      activeConnection = ConnectionType.wifi;
      isCapturing = true;
      isPaused = false;
      notifyListeners();
    } on StateError {
      await _sensor?.disconnect();
      activeConnection = ConnectionType.none;
      isCapturing = false;
      notifyListeners();
      rethrow;
    }
  }

  void _listenToSensor() {
    _subscription = _sensor?.readings.listen((reading) {
      if (!isPaused) {
        samples.add(reading);
        _updateEma(reading);
        notifyListeners();

        alertSoundService.checkAndAlert(
          vibration: currentVibration,
          gasPpm: currentGas,
        );
      }
    });
  }

  Future<void> disconnect() async {
    await alertSoundService.stop();
    await _subscription?.cancel();
    await _sensor?.disconnect();
    await _sensor?.dispose();
    _sensor = null;
    activeConnection = ConnectionType.none;
    isCapturing = false;
    isPaused = false;
    notifyListeners();
  }

  Future<AnalysisResult> stopAndAnalyze() async {
    await alertSoundService.stop();
    await _sensor?.disconnect();
    final analysis = ai.analyze(samples);
    final newRecord = VibrationRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      startedAt: samples.isEmpty ? DateTime.now() : samples.first.timestamp,
      samples: List.unmodifiable(samples),
      analysis: analysis,
    );
    await storage.saveRecord(newRecord);
    isCapturing = false;
    isPaused = false;
    lastResult = analysis;
    notifyListeners();
    return analysis;
  }

  List<double> getDisplayWaveformSamples() {
    if (samples.isEmpty) return [0.0];
    final window =
        samples.sublist(samples.length > 35 ? samples.length - 35 : 0);
    final rawList = window.map((s) => s.dynamicVibration).toList();
    if (!isFilterEnabled || rawList.length < 3) return rawList;

    final smoothed = <double>[];
    double current = rawList.first;
    for (final val in rawList) {
      current = (smoothAlpha * val) + ((1.0 - smoothAlpha) * current);
      smoothed.add(current);
    }
    return smoothed;
  }

  @override
  void dispose() {
    alertSoundService.dispose();
    _subscription?.cancel();
    _sensor?.dispose();
    super.dispose();
  }
}

