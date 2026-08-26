import 'package:flutter/foundation.dart';

import '../models/vibration_record.dart';

class StorageService extends ChangeNotifier {
  final List<VibrationRecord> _records = [];

  List<VibrationRecord> get records => List.unmodifiable(_records);

  Future<void> saveRecord(VibrationRecord record) async {
    _records.insert(0, record);
    notifyListeners();
  }

  Future<void> deleteRecord(String id) async {
    _records.removeWhere((record) => record.id == id);
    notifyListeners();
  }

  Future<void> clear() async {
    _records.clear();
    notifyListeners();
  }
}
