import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../models/vibration_record.dart';
import '../../services/pdf_report_service.dart';
import '../../services/storage_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String selectedRiskFilter = 'TODOS';
  DateTimeRange? selectedDateRange;
  bool isSyncing = false;

  List<VibrationRecord> get filteredRecords {
    return widget.storage.records.where((record) {
      // 1. Filtro por nivel de riesgo
      final risk = record.analysis.riskLevel.toUpperCase();
      if (selectedRiskFilter == 'SEGURO' && risk != 'BAJO') return false;
      if (selectedRiskFilter == 'PRECAUCIÓN' && risk != 'MEDIO') return false;
      if (selectedRiskFilter == 'PELIGRO' && risk != 'ALTO') return false;

      // 2. Filtro por rango de fechas del calendario
      if (selectedDateRange != null) {
        final date = record.startedAt;
        final start = DateTime(
          selectedDateRange!.start.year,
          selectedDateRange!.start.month,
          selectedDateRange!.start.day,
        );
        final end = DateTime(
          selectedDateRange!.end.year,
          selectedDateRange!.end.month,
          selectedDateRange!.end.day,
          23,
          59,
          59,
        );
        if (date.isBefore(start) || date.isAfter(end)) return false;
      }

      return true;
    }).toList();
  }

  Future<void> pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: selectedDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.green,
              onPrimary: Colors.black,
              surface: AppTheme.surface,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => selectedDateRange = picked);
    }
  }

  void setQuickDate(String option) {
    final now = DateTime.now();
    setState(() {
      if (option == 'HOY') {
        selectedDateRange = DateTimeRange(start: now, end: now);
      } else if (option == '7_DIAS') {
        selectedDateRange = DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      } else {
        selectedDateRange = null;
      }
    });
  }

  Future<void> exportConsolidatedPdf() async {
    final records = filteredRecords;
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay ensayos en el rango para exportar')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.lime,
              ),
            ),
            SizedBox(width: 10),
            Text('Generando Informe Oficial de Telemetría en PDF...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    final bytes = await PdfReportService.generateConsolidatedPdf(
      records,
      dateRange: selectedDateRange,
    );

    await PdfReportService.printOrSharePdf(
      bytes,
      filename:
          'Informe_Consolidado_PulsoMinero_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
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

  void exportHistoryCsv() {
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
        final allRecords = widget.storage.records;
        final pendingCount = widget.storage.pendingSyncCount;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // 1. ENCABEZADO Y BOTONES DE EXPORTACIÓN
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
                        '${records.length} de ${allRecords.length} ensayos mostrados',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: exportConsolidatedPdf,
                  tooltip: 'Exportar Informe Oficial PDF',
                  icon: const Icon(Icons.picture_as_pdf,
                      color: Colors.redAccent, size: 22),
                ),
                IconButton(
                  onPressed: exportHistoryCsv,
                  tooltip: 'Copiar tabla CSV',
                  icon: const Icon(Icons.file_copy_outlined,
                      color: AppTheme.lime, size: 20),
                ),
                IconButton(
                  onPressed: clearHistory,
                  tooltip: 'Borrar historial',
                  icon: const Icon(Icons.delete_sweep_outlined,
                      color: Colors.grey, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. BANNER DE ESTADO EN LA NUBE (FIREBASE SYNC)
            _CloudSyncBanner(
              pendingCount: pendingCount,
              isSyncing: isSyncing,
              onSync: syncWithCloud,
              projectId: widget.storage.cloudService.projectId,
            ),
            const SizedBox(height: 14),

            // 3. GRÁFICO DE TENDENCIA HISTÓRICA (OPCIÓN A)
            if (allRecords.isNotEmpty) ...[
              _HistoricalTrendChart(records: allRecords),
              const SizedBox(height: 14),
            ],

            // 4. BARRA DE FILTRO POR CALENDARIO Y RANGOS RÁPIDOS
            _DateFilterBar(
              selectedRange: selectedDateRange,
              onPickCalendar: pickDateRange,
              onQuickSelect: setQuickDate,
            ),
            const SizedBox(height: 10),

            // 5. BARRA DE FILTROS POR SEMÁFORO DE RIESGO
            _RiskFilterSelector(
              selected: selectedRiskFilter,
              onSelected: (val) => setState(() => selectedRiskFilter = val),
            ),
            const SizedBox(height: 16),

            // 6. LISTA DE ENSAYOS O ESTADO VACÍO
            if (allRecords.isEmpty)
              const _EmptyHistory()
            else if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'No hay ensayos que coincidan con la fecha o filtro seleccionado',
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
              const Divider(height: 22),

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
                      value:
                          '${features.dominantFrequency.toStringAsFixed(1)} Hz',
                      color: Colors.cyanAccent,
                    ),
                ],
              ),
              const SizedBox(height: 16),

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
              const SizedBox(height: 18),

              // BOTÓN PARA EXPORTAR REPORTE OFICIAL PDF DE ESTE ENSAYO
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Generando Informe Oficial en PDF...'),
                          ],
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );

                    final bytes =
                        await PdfReportService.generateSingleRecordPdf(record);
                    await PdfReportService.printOrSharePdf(
                      bytes,
                      filename: 'Informe_SST_${record.id}.pdf',
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text(
                    'Exportar Informe Oficial en PDF (SST)',
                    style: TextStyle(fontWeight: FontWeight.bold),
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

/// Gráfico de Tendencia Histórica de Vibración (Opción A)
class _HistoricalTrendChart extends StatelessWidget {
  const _HistoricalTrendChart({required this.records});
  final List<VibrationRecord> records;

  @override
  Widget build(BuildContext context) {
    // Tomar hasta los últimos 12 ensayos en orden cronológico
    final displayRecords = records.length > 12
        ? records.sublist(0, 12).reversed.toList()
        : records.reversed.toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.show_chart, color: AppTheme.lime, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Tendencia de Vibración',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  _legendDot(Colors.amber, '1.0 m/s²'),
                  const SizedBox(width: 8),
                  _legendDot(Colors.redAccent, '2.0 m/s²'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendChartPainter(records: displayRecords),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Primeros ensayos',
                  style: TextStyle(color: Colors.grey, fontSize: 10)),
              Text('Ensayos recientes →',
                  style: TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _legendDot(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({required this.records});
  final List<VibrationRecord> records;

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty) return;

    final maxAmplitude = records
        .map((r) => r.analysis.maximumAmplitude)
        .reduce((a, b) => a > b ? a : b);
    final maxScale = (maxAmplitude > 2.5 ? maxAmplitude * 1.2 : 2.5);

    double getY(double val) {
      final normalized = (val / maxScale).clamp(0.0, 1.0);
      return size.height - (normalized * (size.height - 16) + 8);
    }

    // 1. Dibujar líneas de umbral horizontal punteadas
    final warnY = getY(1.0);
    final critY = getY(2.0);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    _drawDashedLine(canvas, 0, size.width, warnY,
        linePaint..color = Colors.amber.withValues(alpha: 0.45));
    _drawDashedLine(canvas, 0, size.width, critY,
        linePaint..color = Colors.redAccent.withValues(alpha: 0.45));

    // 2. Coordenadas de los puntos
    final dx = size.width / (records.length > 1 ? (records.length - 1) : 1);
    final points = <Offset>[];

    for (var i = 0; i < records.length; i++) {
      final x = records.length == 1 ? size.width / 2 : i * dx;
      final y = getY(records[i].analysis.maximumAmplitude);
      points.add(Offset(x, y));
    }

    // 3. Dibujar área con degradado bajo la curva
    if (points.length > 1) {
      final fillPath = Path();
      fillPath.moveTo(points.first.dx, points.first.dy);

      for (var i = 1; i < points.length; i++) {
        final p0 = points[i - 1];
        final p1 = points[i];
        final midX = (p0.dx + p1.dx) / 2;
        fillPath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
      }

      fillPath.lineTo(points.last.dx, size.height);
      fillPath.lineTo(points.first.dx, size.height);
      fillPath.close();

      final gradientPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.green.withValues(alpha: 0.35),
            AppTheme.green.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, gradientPaint);
    }

    // 4. Dibujar línea continua conectora
    if (points.length > 1) {
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);

      for (var i = 1; i < points.length; i++) {
        final p0 = points[i - 1];
        final p1 = points[i];
        final midX = (p0.dx + p1.dx) / 2;
        path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
      }

      final curvePaint = Paint()
        ..color = AppTheme.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, curvePaint);
    }

    // 5. Dibujar puntos individuales con color de semáforo
    for (var i = 0; i < records.length; i++) {
      final pt = points[i];
      final val = records[i].analysis.maximumAmplitude;
      final riskColor = val >= 2.0
          ? Colors.redAccent
          : (val >= 1.0 ? Colors.amber : AppTheme.green);

      // Aro exterior blanco
      canvas.drawCircle(
        pt,
        4.5,
        Paint()..color = Colors.white,
      );
      // Punto interior con color de riesgo
      canvas.drawCircle(
        pt,
        3.0,
        Paint()..color = riskColor,
      );
    }
  }

  void _drawDashedLine(
      Canvas canvas, double x1, double x2, double y, Paint paint) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    var startX = x1;
    while (startX < x2) {
      canvas.drawLine(
        Offset(startX, y),
        Offset(startX + dashWidth, y),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) => true;
}

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({
    required this.selectedRange,
    required this.onPickCalendar,
    required this.onQuickSelect,
  });

  final DateTimeRange? selectedRange;
  final VoidCallback onPickCalendar;
  final ValueChanged<String> onQuickSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Botón del calendario
          InkWell(
            onTap: onPickCalendar,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selectedRange != null
                    ? AppTheme.green.withValues(alpha: 0.2)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selectedRange != null
                      ? AppTheme.green
                      : AppTheme.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month,
                    size: 16,
                    color: selectedRange != null
                        ? AppTheme.green
                        : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selectedRange == null
                        ? 'Filtrar Fecha'
                        : '${selectedRange!.start.day}/${selectedRange!.start.month} - ${selectedRange!.end.day}/${selectedRange!.end.month}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: selectedRange != null
                          ? AppTheme.green
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Chips rápidos
          _quickChip('Todos', selectedRange == null, () => onQuickSelect('TODOS')),
          const SizedBox(width: 6),
          _quickChip('Hoy', false, () => onQuickSelect('HOY')),
          const SizedBox(width: 6),
          _quickChip('Últimos 7 días', false, () => onQuickSelect('7_DIAS')),
        ],
      ),
    );
  }

  Widget _quickChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                'Firebase Firestore conectado ($projectId)',
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
