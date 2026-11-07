import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AlertSoundService {
  static const MethodChannel _channel =
      MethodChannel('com.pulsominero.alert/alarm');

  DateTime? _lastAlertTime;
  bool _isCurrentlyAlarming = false;

  bool get isCurrentlyAlarming => _isCurrentlyAlarming;

  Future<void> checkAndAlert({
    required double vibration,
    required double gasPpm,
  }) async {
    final isCritical = vibration >= 2.0 || gasPpm > 1000.0;

    if (isCritical) {
      _isCurrentlyAlarming = true;
      final now = DateTime.now();
      if (_lastAlertTime == null ||
          now.difference(_lastAlertTime!).inMilliseconds >= 1800) {
        _lastAlertTime = now;
        try {
          await _channel.invokeMethod('playCriticalAlarm');
        } catch (e) {
          debugPrint('Error invocando alarma sonora nativa: $e');
        }

        try {
          await HapticFeedback.heavyImpact();
          await SystemSound.play(SystemSoundType.alert);
        } catch (_) {}
      }
    } else {
      if (_isCurrentlyAlarming) {
        await stop();
      }
    }
  }

  Future<void> stop() async {
    _isCurrentlyAlarming = false;
    _lastAlertTime = null;
    try {
      await _channel.invokeMethod('stopCriticalAlarm');
    } catch (e) {
      debugPrint('Error deteniendo alarma nativa: $e');
    }
  }

  void dispose() {
    stop();
  }
}

