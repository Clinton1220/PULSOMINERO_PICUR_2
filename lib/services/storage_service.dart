import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vibration_record.dart';
import 'firebase_cloud_service.dart';

class StorageService extends ChangeNotifier {
  StorageService({FirebaseCloudService? cloudService})
      : cloudService = cloudService ?? FirebaseCloudService();

  final List<VibrationRecord> _records = [];
  final FirebaseCloudService cloudService;

  List<VibrationRecord> get records => List.unmodifiable(_records);

  /// Cantidad de ensayos pendientes por sincronizar en la nube
  int get pendingSyncCount =>
      _records.where((record) => !record.isSyncedToCloud).length;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList('vibration_records') ?? [];
    _records
      ..clear()
      ..addAll(raw.map((item) =>
          VibrationRecord.fromJson(jsonDecode(item) as Map<String, dynamic>)));
    notifyListeners();
  }

  /// Guarda el ensayo localmente de forma inmediata (Offline-First)
  /// e intenta sincronizarlo automáticamente a Firebase Firestore.
  /// Retorna `true` si se sincronizó con la nube o `false` si quedó en cola local.
  Future<bool> saveRecord(VibrationRecord record) async {
    _records.insert(0, record);
    await _persist();
    notifyListeners();

    // Intentar sincronización automática en la nube
    final synced = await cloudService.uploadVibrationRecord(record);
    if (synced) {
      final index = _records.indexWhere((r) => r.id == record.id);
      if (index != -1) {
        _records[index] = _records[index].copyWith(isSyncedToCloud: true);
        await _persist();
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  /// Sincroniza todos los ensayos locales que aún no están en Firebase.
  /// Retorna la cantidad de ensayos sincronizados exitosamente.
  Future<int> syncPendingRecords() async {
    var syncedCount = 0;
    for (var i = 0; i < _records.length; i++) {
      if (!_records[i].isSyncedToCloud) {
        final ok = await cloudService.uploadVibrationRecord(_records[i]);
        if (ok) {
          _records[i] = _records[i].copyWith(isSyncedToCloud: true);
          syncedCount++;
        }
      }
    }
    if (syncedCount > 0) {
      await _persist();
      notifyListeners();
    }
    return syncedCount;
  }

  Future<void> deleteRecord(String id) async {
    _records.removeWhere((record) => record.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _records.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('vibration_records',
        _records.map((record) => jsonEncode(record.toJson())).toList());
  }
}
