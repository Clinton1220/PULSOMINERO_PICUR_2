import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/storage_service.dart';
import '../../models/analysis_result.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: storage,
      builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const Text('Alertas',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const _FilterTabs(),
                const SizedBox(height: 16),
                if (storage.records.isEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Center(
                          child: Text('No hay alertas generadas',
                              style: TextStyle(color: Colors.grey))))
                else
                  ...storage.records.map((record) => _AlertCard.fromAnalysis(
                      record.analysis, record.startedAt))
              ]));
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['Todas', 'Críticas', 'Advertencias', 'Info'].map((label) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 5),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: label == 'Todas' ? AppTheme.green : AppTheme.surface,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: label == 'Todas' ? Colors.black : Colors.grey))),
          ),
        );
      }).toList(),
    );
  }
}

class _AlertCard extends StatelessWidget {
  factory _AlertCard.fromAnalysis(AnalysisResult result, DateTime date) {
    final critical =
        result.classification == VibrationClassification.highRiskVibration;
    final machinery =
        result.classification == VibrationClassification.machineryVibration;
    return _AlertCard(
        icon: critical || machinery
            ? Icons.warning_amber_rounded
            : Icons.info_outline,
        title: result.title,
        date: date.toLocal().toString().substring(0, 16),
        detail: result.reasons.join(' '),
        color: critical
            ? Colors.redAccent
            : machinery
                ? Colors.amber
                : AppTheme.green,
        tag: critical
            ? 'Crítica'
            : machinery
                ? 'Advertencia'
                : 'Info');
  }
  const _AlertCard(
      {required this.icon,
      required this.title,
      required this.date,
      required this.detail,
      required this.color,
      required this.tag});
  final IconData icon;
  final String title, date, detail, tag;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: color.withOpacity(.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(.35))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withOpacity(.16),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(tag, style: TextStyle(color: color, fontSize: 10)))
          ]),
          const SizedBox(height: 3),
          Text(date, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 12),
          Text(detail,
              style: const TextStyle(color: Color(0xFFCCD1D2), height: 1.4)),
        ])),
      ]),
    );
  }
}
