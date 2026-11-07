import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AlertSoundService {
  static const MethodChannel _channel =
      MethodChannel('com.pulsominero.alert/alarm');

  bool _isCurrentlyAlarming = false;

  bool get isCurrentlyAlarming => _isCurrentlyAlarming;

  Future<void> checkAndAlert({
    required double vibration,
    required double gasPpm,
  }) async {
    final isCritical = vibration >= 2.0 || gasPpm > 1000.0;

    if (isCritical) {
      if (!_isCurrentlyAlarming) {
        _isCurrentlyAlarming = true;
        try {
          await _channel.invokeMethod('playCriticalAlarm');
        } catch (e) {
          debugPrint('Error invocando alarma sonora nativa: $e');
        }

        try {
          await HapticFeedback.heavyImpact();
        } catch (_) {}
      }
    } else {
      if (_isCurrentlyAlarming) {
        await stop();
      }
    }
  }

  Future<void> stop() async {
    if (!_isCurrentlyAlarming) return;
    _isCurrentlyAlarming = false;
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
