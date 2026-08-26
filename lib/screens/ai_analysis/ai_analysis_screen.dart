import 'package:flutter/material.dart';

import '../../app/theme.dart';

class AiAnalysisScreen extends StatelessWidget {
  const AiAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), children: [
        const Center(
            child: Icon(Icons.psychology_outlined,
                color: AppTheme.green, size: 55)),
        const SizedBox(height: 10),
        const Center(
            child: Text('Explicación de la IA',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        const SizedBox(height: 22),
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border)),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Análisis con IA',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  SizedBox(height: 14),
                  Text(
                      'La IA ha analizado los patrones de vibración detectados y determinó que:',
                      style: TextStyle(color: Colors.grey, height: 1.5)),
                  SizedBox(height: 14),
                  _ResultBox(),
                  SizedBox(height: 18),
                  Text('Factores que influyeron en la decisión:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 10),
                  _Factor(text: 'Duración corta de la vibración (< 2s)'),
                  _Factor(text: 'Baja amplitud (0.42 mm/s)'),
                  _Factor(text: 'Patrón no repetitivo'),
                  _Factor(
                      text:
                          'Frecuencia fuera del rango típico de maquinaria pesada'),
                  SizedBox(height: 18),
                  _Confidence()
                ]))
      ]);
}

class _ResultBox extends StatelessWidget {
  const _ResultBox();
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: const Color(0xFF153D22),
          borderRadius: BorderRadius.circular(8)),
      child: const Row(children: [
        Icon(Icons.check_circle, color: AppTheme.lime),
        SizedBox(width: 10),
        Expanded(
            child: Text(
                'No es vibración de maquinaria\n\nPatrón clasificado como:\nVibración aislada / ruido ambiental',
                style: TextStyle(color: Color(0xFFD7EBD9), height: 1.35)))
      ]));
}

class _Factor extends StatelessWidget {
  const _Factor({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        const Icon(Icons.check, color: AppTheme.green, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text, style: const TextStyle(color: Color(0xFFCBD2D3))))
      ]));
}

class _Confidence extends StatelessWidget {
  const _Confidence();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          border: Border.all(color: AppTheme.green),
          borderRadius: BorderRadius.circular(8)),
      child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Confianza del modelo',
                style: TextStyle(color: AppTheme.lime)),
            Text('95%',
                style: TextStyle(
                    color: AppTheme.lime,
                    fontSize: 20,
                    fontWeight: FontWeight.bold))
          ]));
}
