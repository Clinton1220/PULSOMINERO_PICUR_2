import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../models/analysis_result.dart';
import '../../models/vibration_record.dart';
import '../../services/storage_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  VibrationClassification? selectedFilter;

  List<VibrationRecord> get filteredRecords {
    if (selectedFilter == null) return widget.storage.records;
    return widget.storage.records
        .where((record) => record.analysis.classification == selectedFilter)
        .toList();
  }

  Future<void> clearHistory() async {
    if (widget.storage.records.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar historial'),
        content: const Text('Se eliminarán todos los ensayos guardados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Borrar todo')),
        ],
      ),
    );
    if (confirmed == true) await widget.storage.clear();
  }

  void exportHistory() {
    final rows = <String>[
      'id,fecha,clasificacion,riesgo,amplitud_maxima,repeticiones'
    ];
    for (final record in widget.storage.records) {
      rows.add(
          '${record.id},${record.startedAt.toIso8601String()},${record.analysis.title},${record.analysis.riskLevel},${record.analysis.maximumAmplitude.toStringAsFixed(2)},${record.analysis.repetitions}');
    }
    Clipboard.setData(ClipboardData(text: rows.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resumen CSV copiado al portapapeles')));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.storage,
      builder: (context, _) {
        final records = filteredRecords;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(children: [
              const Expanded(
                  child: Text('Historial',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold))),
              IconButton(
                  onPressed: exportHistory,
                  tooltip: 'Exportar CSV',
                  icon: const Icon(Icons.file_copy_outlined)),
              IconButton(
                  onPressed: clearHistory,
                  tooltip: 'Borrar historial',
                  icon: const Icon(Icons.delete_sweep_outlined)),
            ]),
            const SizedBox(height: 14),
            _FilterBar(
                selected: selectedFilter,
                onChanged: (value) => setState(() => selectedFilter = value)),
            const SizedBox(height: 16),
            if (widget.storage.records.isEmpty)
              const _EmptyHistory()
            else if (records.isEmpty)
              const Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Center(
                      child: Text('No hay ensayos con este filtro',
                          style: TextStyle(color: Colors.grey))))
            else
              ...records.map((record) => _TestCard(
                  record: record,
                  onDelete: () => widget.storage.deleteRecord(record.id),
                  onOpen: () => _showDetails(record))),
          ],
        );
      },
    );
  }

  void _showDetails(VibrationRecord record) {
    final features = record.analysis.features;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (_) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.analysis.title,
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(record.startedAt.toLocal().toString(),
                        style: const TextStyle(color: Colors.grey)),
                    const Divider(height: 25),
                    _DetailLine(
                        label: 'Riesgo', value: record.analysis.riskLevel),
                    _DetailLine(
                        label: 'Confianza',
                        value:
                            '${(record.analysis.confidence * 100).toStringAsFixed(0)}%'),
                    _DetailLine(
                        label: 'Amplitud máxima',
                        value:
                            '${record.analysis.maximumAmplitude.toStringAsFixed(2)} mm/s'),
                    _DetailLine(
                        label: 'Duración',
                        value: '${record.analysis.duration.inMilliseconds} ms'),
                    _DetailLine(
                        label: 'Muestras', value: '${record.samples.length}'),
                    if (features != null)
                      _DetailLine(
                          label: 'RMS / frecuencia',
                          value:
                              '${features.rms.toStringAsFixed(2)} mm/s · ${features.dominantFrequency.toStringAsFixed(2)} Hz'),
                    const SizedBox(height: 10),
                    const Text('Explicación',
                        style: TextStyle(
                            color: AppTheme.lime, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...record.analysis.reasons.map((reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $reason'))),
                  ]))),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});
  final VibrationClassification? selected;
  final ValueChanged<VibrationClassification?> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _Filter(
            label: 'Todos',
            selected: selected == null,
            onTap: () => onChanged(null)),
        _Filter(
            label: 'Ruido',
            selected: selected == VibrationClassification.ambientNoise,
            onTap: () => onChanged(VibrationClassification.ambientNoise)),
        _Filter(
            label: 'Aislada',
            selected: selected == VibrationClassification.isolatedVibration,
            onTap: () => onChanged(VibrationClassification.isolatedVibration)),
        _Filter(
            label: 'Maquinaria',
            selected: selected == VibrationClassification.machineryVibration,
            onTap: () => onChanged(VibrationClassification.machineryVibration)),
        _Filter(
            label: 'Peligro',
            selected: selected == VibrationClassification.highRiskVibration,
            onTap: () => onChanged(VibrationClassification.highRiskVibration)),
      ]));
}

class _Filter extends StatelessWidget {
  const _Filter(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AppTheme.green,
          labelStyle:
              TextStyle(color: selected ? Colors.black : Colors.white)));
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.only(top: 55),
      child: Column(children: [
        Icon(Icons.history, size: 52, color: AppTheme.green),
        SizedBox(height: 12),
        Text('Aún no hay ensayos guardados',
            style: TextStyle(color: Colors.grey)),
        SizedBox(height: 5),
        Text('Inicia un ensayo desde Monitoreo',
            style: TextStyle(color: Colors.grey, fontSize: 12))
      ]));
}

class _TestCard extends StatelessWidget {
  const _TestCard(
      {required this.record, required this.onDelete, required this.onOpen});
  final VibrationRecord record;
  final VoidCallback onDelete;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(record.analysis.title,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(
                  onPressed: onDelete,
                  tooltip: 'Eliminar ensayo',
                  icon: const Icon(Icons.delete_outline, color: Colors.grey))
            ]),
            Text(record.startedAt.toLocal().toString().substring(0, 16),
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _Value(
                      label: 'Amplitud máxima',
                      value:
                          '${record.analysis.maximumAmplitude.toStringAsFixed(2)} mm/s')),
              Expanded(
                  child: _Value(
                      label: 'Riesgo',
                      value: record.analysis.riskLevel,
                      color: AppTheme.lime))
            ]),
            const SizedBox(height: 10),
            Text(
                '${record.samples.length} muestras · ${(record.analysis.confidence * 100).toStringAsFixed(0)}% confianza',
                style: const TextStyle(color: Colors.grey, fontSize: 11))
          ])));
}

class _Value extends StatelessWidget {
  const _Value(
      {required this.label, required this.value, this.color = Colors.white});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.w600))
      ]);
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
      ]));
}
