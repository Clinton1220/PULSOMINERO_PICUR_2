import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vibration_record.dart';

class StorageService extends ChangeNotifier {
  final List<VibrationRecord> _records = [];

  List<VibrationRecord> get records => List.unmodifiable(_records);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList('vibration_records') ?? [];
    _records
      ..clear()
      ..addAll(raw.map((item) =>
          VibrationRecord.fromJson(jsonDecode(item) as Map<String, dynamic>)));
    notifyListeners();
  }

  Future<void> saveRecord(VibrationRecord record) async {
    _records.insert(0, record);
    await _persist();
    notifyListeners();
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
