import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/vibration_record.dart';
import '../../services/storage_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: storage,
      builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const Text('Historial',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const _Tabs(),
                const SizedBox(height: 16),
                if (storage.records.isEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Center(
                          child: Text('Aún no hay ensayos guardados',
                              style: TextStyle(color: Colors.grey))))
                else
                  ...storage.records.map((record) => _TestCard(
                      record: record,
                      onDelete: () => storage.deleteRecord(record.id)))
              ]));
}

class _Tabs extends StatelessWidget {
  const _Tabs();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(9)),
      child: Row(children: [
        Expanded(
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFF29302E),
                    borderRadius: BorderRadius.circular(7)),
                child: const Center(
                    child: Text('Ensayos',
                        style: TextStyle(
                            color: AppTheme.lime,
                            fontWeight: FontWeight.w600))))),
        const Expanded(
            child: Center(
                child: Text('Exportaciones',
                    style: TextStyle(color: Colors.grey))))
      ]));
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.record, required this.onDelete});
  final VibrationRecord record;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(record.analysis.title,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.grey))
        ]),
        Text(record.startedAt.toLocal().toString().substring(0, 16),
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 12),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
                color: const Color(0xFF153D22),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('Sin falsos positivos',
                style: TextStyle(color: AppTheme.lime, fontSize: 11))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Vibración máxima',
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
                Text(
                    '${record.analysis.maximumAmplitude.toStringAsFixed(2)} mm/s',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600))
              ])),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Nivel de riesgo',
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
                Text(record.analysis.riskLevel,
                    style: TextStyle(
                        color: AppTheme.lime,
                        fontSize: 16,
                        fontWeight: FontWeight.w600))
              ]))
        ]),
      ]),
    );
  }
}
