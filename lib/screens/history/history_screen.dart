import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../models/vibration_record.dart';
import '../../services/storage_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String selectedRiskFilter = 'TODOS';
  bool isSyncing = false;

  List<VibrationRecord> get filteredRecords {
    if (selectedRiskFilter == 'TODOS') return widget.storage.records;
    return widget.storage.records.where((record) {
      final risk = record.analysis.riskLevel.toUpperCase();
      if (selectedRiskFilter == 'SEGURO') return risk == 'BAJO';
      if (selectedRiskFilter == 'PRECAUCIÓN') return risk == 'MEDIO';
      if (selectedRiskFilter == 'PELIGRO') return risk == 'ALTO';
      return true;
    }).toList();
  }

  Future<void> syncWithCloud() async {
    if (isSyncing) return;
    setState(() => isSyncing = true);

    final syncedCount = await widget.storage.syncPendingRecords();

    if (mounted) {
      setState(() => isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surface,
          content: Row(
            children: [
              Icon(
                syncedCount > 0 ? Icons.cloud_done : Icons.cloud_off,
                color: syncedCount > 0 ? AppTheme.green : Colors.amber,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  syncedCount > 0
                      ? '☁️ $syncedCount ensayos sincronizados con Firebase Firestore'
                      : 'ℹ️ No se pudieron sincronizar (revisa tu conexión a internet)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> clearHistory() async {
    if (widget.storage.records.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Borrar historial local'),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas eliminar todos los ensayos guardados en este dispositivo?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar todo'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.storage.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Historial local vaciado correctamente')),
        );
      }
    }
  }

  void exportHistory() {
    if (widget.storage.records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay ensayos guardados para exportar')),
      );
      return;
    }

    final rows = <String>[
      'id,fecha,clasificacion,riesgo,amplitud_maxima_ms2,inclinacion_grados,gas_max_ppm,repeticiones,sincronizado_nube'
    ];
    for (final record in widget.storage.records) {
      final maxInc = record.samples.isEmpty
          ? 0.0
          : record.samples
              .map((s) => s.inclination.abs())
              .reduce((a, b) => a > b ? a : b);
      final maxGas = record.samples.isEmpty
          ? 0.0
          : record.samples
              .map((s) => s.gasPpm)
              .reduce((a, b) => a > b ? a : b);

      rows.add(
        '${record.id},${record.startedAt.toIso8601String()},${record.analysis.title},${record.analysis.riskLevel},${record.analysis.maximumAmplitude.toStringAsFixed(2)},${maxInc.toStringAsFixed(1)},${maxGas.toStringAsFixed(0)},${record.analysis.repetitions},${record.isSyncedToCloud}',
      );
    }
    Clipboard.setData(ClipboardData(text: rows.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Reporte técnico CSV copiado al portapapeles con éxito'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.storage,
      builder: (context, _) {
        final records = filteredRecords;
        final pendingCount = widget.storage.pendingSyncCount;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // 1. ENCABEZADO Y ACCIONES
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Historial de Ensayos',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.storage.records.length} ensayos registrados',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: exportHistory,
                  tooltip: 'Exportar CSV',
                  icon: const Icon(Icons.file_copy_outlined,
                      color: AppTheme.lime),
                ),
                IconButton(
                  onPressed: clearHistory,
                  tooltip: 'Borrar historial',
                  icon: const Icon(Icons.delete_sweep_outlined,
                      color: Colors.redAccent),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 2. BANNER DE ESTADO EN LA NUBE (FIREBASE SYNC BAR)
            _CloudSyncBanner(
              pendingCount: pendingCount,
              isSyncing: isSyncing,
              onSync: syncWithCloud,
              projectId: widget.storage.cloudService.projectId,
            ),
            const SizedBox(height: 14),

            // 3. BARRA DE FILTROS POR SEMÁFORO DE RIESGO
            _RiskFilterSelector(
              selected: selectedRiskFilter,
              onSelected: (val) => setState(() => selectedRiskFilter = val),
            ),
            const SizedBox(height: 16),

            // 4. LISTA DE ENSAYOS O ESTADO VACÍO
            if (widget.storage.records.isEmpty)
              const _EmptyHistory()
            else if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 50),
                child: Center(
                  child: Text(
                    'No hay ensayos que coincidan con este filtro',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...records.map(
                (record) => _TestCard(
                  record: record,
                  onDelete: () => widget.storage.deleteRecord(record.id),
                  onOpen: () => _showDetails(record),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showDetails(VibrationRecord record) {
    final features = record.analysis.features;
    final maxInc = record.samples.isEmpty
        ? 0.0
        : record.samples
            .map((s) => s.inclination.abs())
            .reduce((a, b) => a > b ? a : b);
    final maxGas = record.samples.isEmpty
        ? 0.0
        : record.samples.map((s) => s.gasPpm).reduce((a, b) => a > b ? a : b);

    final risk = record.analysis.riskLevel.toUpperCase();
    final riskColor = risk == 'ALTO'
        ? Colors.redAccent
        : (risk == 'MEDIO' ? Colors.amber : AppTheme.green);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: riskColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.analysis.title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _CloudStatusBadge(isSynced: record.isSyncedToCloud),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'ID: ${record.id} · ${record.startedAt.toLocal().toString().substring(0, 19)}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const Divider(height: 25),

              // Métricas Clave en Grid de chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricBadge(
                    label: 'Vibración Pico',
                    value:
                        '${record.analysis.maximumAmplitude.toStringAsFixed(2)} m/s²',
                    color: riskColor,
                  ),
                  _MetricBadge(
                    label: 'Gas Pico (MQ-135)',
                    value: '${maxGas.toStringAsFixed(0)} PPM',
                    color: maxGas > 1000
                        ? Colors.redAccent
                        : (maxGas > 600 ? Colors.amber : AppTheme.green),
                  ),
                  _MetricBadge(
                    label: 'Inclinación Máx',
                    value: '${maxInc.toStringAsFixed(1)}°',
                    color: maxInc > 15.0 ? Colors.redAccent : Colors.white70,
                  ),
                  _MetricBadge(
                    label: 'Confianza IA',
                    value:
                        '${(record.analysis.confidence * 100).toStringAsFixed(0)}%',
                    color: AppTheme.lime,
                  ),
                  _MetricBadge(
                    label: 'Muestras',
                    value: '${record.samples.length}',
                    color: Colors.white70,
                  ),
                  if (features != null)
                    _MetricBadge(
                      label: 'Frec. Dominante',
                      value: '${features.dominantFrequency.toStringAsFixed(1)} Hz',
                      color: Colors.cyanAccent,
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // Dictamen Explicable del Motor de IA (XAI)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.green.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.psychology, color: AppTheme.lime, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Dictamen de Inteligencia Artificial (XAI):',
                          style: TextStyle(
                            color: AppTheme.lime,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...record.analysis.reasons.map(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(
                                    color: AppTheme.lime,
                                    fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(
                                reason,
                                style: const TextStyle(
                                    fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudSyncBanner extends StatelessWidget {
  const _CloudSyncBanner({
    required this.pendingCount,
    required this.isSyncing,
    required this.onSync,
    required this.projectId,
  });

  final int pendingCount;
  final bool isSyncing;
  final VoidCallback onSync;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppTheme.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_done, color: AppTheme.green, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Firebase Firestore al día ($projectId)',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.green,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined,
              color: Colors.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$pendingCount ${pendingCount == 1 ? "ensayo pendiente" : "ensayos pendientes"} por subir',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.amber),
                ),
                const Text(
                  'Guardados localmente en memoria',
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: isSyncing ? null : onSync,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(fontSize: 11),
            ),
            icon: isSyncing
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.sync, size: 14),
            label: Text(isSyncing ? 'Subiendo...' : 'Sincronizar'),
          ),
        ],
      ),
    );
  }
}

class _RiskFilterSelector extends StatelessWidget {
  const _RiskFilterSelector({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = ['TODOS', 'SEGURO', 'PRECAUCIÓN', 'PELIGRO'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = selected == filter;
          Color activeColor = AppTheme.green;
          if (filter == 'PRECAUCIÓN') activeColor = Colors.amber;
          if (filter == 'PELIGRO') activeColor = Colors.redAccent;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (_) => onSelected(filter),
              selectedColor: activeColor,
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.record,
    required this.onDelete,
    required this.onOpen,
  });

  final VibrationRecord record;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final risk = record.analysis.riskLevel.toUpperCase();
    final riskColor = risk == 'ALTO'
        ? Colors.redAccent
        : (risk == 'MEDIO' ? Colors.amber : AppTheme.green);

    final maxInc = record.samples.isEmpty
        ? 0.0
        : record.samples
            .map((s) => s.inclination.abs())
            .reduce((a, b) => a > b ? a : b);
    final maxGas = record.samples.isEmpty
        ? 0.0
        : record.samples.map((s) => s.gasPpm).reduce((a, b) => a > b ? a : b);

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: riskColor.withValues(alpha: 0.3)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Franja lateral con semáforo de riesgo
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: riskColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              record.analysis.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          _CloudStatusBadge(isSynced: record.isSyncedToCloud),
                          IconButton(
                            onPressed: onDelete,
                            tooltip: 'Eliminar ensayo',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.grey, size: 18),
                          ),
                        ],
                      ),
                      Text(
                        record.startedAt.toLocal().toString().substring(0, 16),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(height: 10),

                      // Valores Clave
                      Row(
                        children: [
                          Expanded(
                            child: _Value(
                              label: 'Vibración Resultante',
                              value:
                                  '${record.analysis.maximumAmplitude.toStringAsFixed(2)} m/s²',
                              color: riskColor,
                            ),
                          ),
                          Expanded(
                            child: _Value(
                              label: 'Gas / Inclinación',
                              value:
                                  '${maxGas.toStringAsFixed(0)} PPM · ${maxInc.toStringAsFixed(1)}°',
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Pie de tarjeta
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: riskColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Riesgo: ${record.analysis.riskLevel}',
                              style: TextStyle(
                                color: riskColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${record.samples.length} pts · ${(record.analysis.confidence * 100).toStringAsFixed(0)}% confianza',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudStatusBadge extends StatelessWidget {
  const _CloudStatusBadge({required this.isSynced});
  final bool isSynced;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSynced
            ? AppTheme.green.withValues(alpha: 0.15)
            : Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSynced ? Icons.cloud_done : Icons.cloud_queue,
            size: 11,
            color: isSynced ? AppTheme.green : Colors.amber,
          ),
          const SizedBox(width: 3),
          Text(
            isSynced ? 'Firebase' : 'Local',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isSynced ? AppTheme.green : Colors.amber,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.label,
    required this.value,
    this.color = Colors.white,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 55),
        child: Column(
          children: [
            Icon(Icons.history, size: 52, color: AppTheme.green),
            SizedBox(height: 12),
            Text(
              'Aún no hay ensayos guardados',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 5),
            Text(
              'Inicia un ensayo desde la pantalla de Monitoreo',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
}
