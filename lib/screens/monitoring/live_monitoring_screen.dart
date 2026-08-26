import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/analysis_result.dart';
import '../../models/sensor_data.dart';
import '../../models/vibration_record.dart';
import '../../services/ai_service.dart';
import '../../services/sensor_service.dart';
import '../../services/storage_service.dart';

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  final sensor = SensorSimulator();
  late final StorageService storage;
  final ai = AiService();
  final samples = <SensorData>[];
  StreamSubscription<SensorData>? subscription;
  AnalysisResult? result;
  DemoMode selectedMode = DemoMode.isolated;
  bool isCapturing = false;

  @override
  void initState() {
    super.initState();
    storage = widget.storage;
    subscription = sensor.readings.listen((reading) {
      if (!mounted) return;
      setState(() => samples.add(reading));
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    sensor.dispose();
    super.dispose();
  }

  Future<void> toggleCapture() async {
    if (isCapturing) {
      await sensor.disconnect();
      final analysis = ai.analyze(samples);
      final record = VibrationRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        startedAt: samples.isEmpty ? DateTime.now() : samples.first.timestamp,
        samples: List.unmodifiable(samples),
        analysis: analysis,
      );
      await storage.saveRecord(record);
      if (!mounted) return;
      setState(() {
        isCapturing = false;
        result = analysis;
      });
      return;
    }

    samples.clear();
    result = null;
    sensor.setDemoMode(selectedMode);
    await sensor.connect();
    if (mounted) setState(() => isCapturing = true);
  }

  @override
  Widget build(BuildContext context) {
    final current = samples.isEmpty ? 0.0 : samples.last.magnitude;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text('Monitoreo en tiempo real',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
            isCapturing
                ? 'Simulador conectado · Capturando muestras'
                : 'Simulador listo · Sensor físico pendiente',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 18),
        _ModeSelector(
            value: selectedMode,
            onChanged: isCapturing
                ? null
                : (mode) => setState(() => selectedMode = mode)),
        const SizedBox(height: 14),
        _ReadingCard(value: current, sampleCount: samples.length),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: toggleCapture,
          icon: Icon(isCapturing
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outline),
          label: Text(
              isCapturing ? 'Detener ensayo y analizar' : 'Iniciar ensayo'),
          style: FilledButton.styleFrom(
              backgroundColor: isCapturing ? Colors.redAccent : AppTheme.green,
              foregroundColor: isCapturing ? Colors.white : Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 15)),
        ),
        const SizedBox(height: 16),
        if (result != null) _ResultCard(result: result!),
        if (result == null) const _InstructionCard(),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});
  final DemoMode value;
  final ValueChanged<DemoMode>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tipo de ensayo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        Row(children: [
          Expanded(
              child: ChoiceChip(
                  label: const Text('Aislada'),
                  selected: value == DemoMode.isolated,
                  onSelected: onChanged == null
                      ? null
                      : (_) => onChanged!(DemoMode.isolated))),
          const SizedBox(width: 10),
          Expanded(
              child: ChoiceChip(
                  label: const Text('Sostenida'),
                  selected: value == DemoMode.sustained,
                  onSelected: onChanged == null
                      ? null
                      : (_) => onChanged!(DemoMode.sustained)))
        ])
      ]);
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.value, required this.sampleCount});
  final double value;
  final int sampleCount;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        const Icon(Icons.graphic_eq, color: AppTheme.green, size: 35),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vibración actual', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text('${value.toStringAsFixed(2)} mm/s',
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          Text('$sampleCount muestras recibidas',
              style: const TextStyle(color: Colors.grey, fontSize: 11))
        ]))
      ]));
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF153D22),
          borderRadius: BorderRadius.circular(10)),
      child: const Text(
          'Selecciona un tipo de ensayo e inicia la captura. El simulador genera datos hasta que detengas la prueba y las reglas explicables mostrarán el resultado.',
          style: TextStyle(color: Color(0xFFD7EBD9), height: 1.45)));
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final AnalysisResult result;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF153D22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.green.withOpacity(.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.psychology_outlined, color: AppTheme.lime),
          const SizedBox(width: 10),
          Expanded(
              child: Text(result.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold))),
          Text(result.riskLevel,
              style: const TextStyle(
                  color: AppTheme.lime, fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 12),
        Text(
            'Amplitud máxima: ${result.maximumAmplitude.toStringAsFixed(2)} mm/s',
            style: const TextStyle(color: Color(0xFFD7EBD9))),
        Text('Repeticiones: ${result.repetitions}',
            style: const TextStyle(color: Color(0xFFD7EBD9))),
        const SizedBox(height: 12),
        const Text('Por qué:',
            style:
                TextStyle(color: AppTheme.lime, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...result.reasons.map((reason) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $reason',
                style: const TextStyle(color: Color(0xFFD7EBD9)))))
      ]));
}
