import 'package:flutter/material.dart';

import '../../app/theme.dart';

class MonitoringScreen extends StatelessWidget {
  const MonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text('Monitoreo en tiempo real',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Acelerómetro conectado · Actualizado: 09:41:23 AM',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 20),
        _SegmentedControl(),
        const SizedBox(height: 16),
        _CurrentReading(),
        const SizedBox(height: 14),
        _ChartCard(),
        const SizedBox(height: 14),
        const Row(children: [
          Expanded(
              child: _RangeCard(
                  title: '< 1.0', label: 'Seguro', color: AppTheme.green)),
          SizedBox(width: 8),
          Expanded(
              child: _RangeCard(
                  title: '1.0 - 2.0',
                  label: 'Precaución',
                  color: Colors.amber)),
          SizedBox(width: 8),
          Expanded(
              child: _RangeCard(
                  title: '> 2.0', label: 'Peligro', color: Colors.redAccent))
        ]),
        const SizedBox(height: 14),
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border)),
            child: const Row(children: [
              Icon(Icons.sensors_outlined, color: AppTheme.green),
              SizedBox(width: 12),
              Expanded(
                  child: Text('Sensor\nAcelerómetro',
                      style: TextStyle(height: 1.5))),
              Text('Frecuencia\n100 Hz',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.grey, height: 1.5))
            ])),
      ],
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF29302E),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Center(
                child: Text(
                  'Vibración',
                  style: TextStyle(
                    color: AppTheme.lime,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text('Inclinación', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentReading extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Vibración actual', style: TextStyle(color: Colors.grey)),
          SizedBox(height: 8),
          Text('0.28',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        ])),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFF153D22),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('Baja',
                style: TextStyle(
                    color: AppTheme.lime, fontWeight: FontWeight.bold)))
      ]));
}

class _ChartCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Gráfico de vibración (mm/s)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
            height: 130,
            child: CustomPaint(
                painter: _ChartPainter(), child: const SizedBox.expand())),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('09:36', style: TextStyle(color: Colors.grey, fontSize: 10)),
          Text('09:38', style: TextStyle(color: Colors.grey, fontSize: 10)),
          Text('09:40', style: TextStyle(color: Colors.grey, fontSize: 10)),
          Text('09:41', style: TextStyle(color: Colors.grey, fontSize: 10))
        ])
      ]));
}

class _ChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF263033)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, size.height * i / 5),
          Offset(size.width, size.height * i / 5), grid);
    }
    for (var i = 1; i < 7; i++) {
      canvas.drawLine(Offset(size.width * i / 7, 0),
          Offset(size.width * i / 7, size.height), grid);
    }
    final points = [
      0.61,
      .58,
      .66,
      .62,
      .71,
      .55,
      .60,
      .46,
      .52,
      .41,
      .48,
      .38,
      .44,
      .34,
      .39,
      .31,
      .35,
      .29,
      .34,
      .27,
      .31,
      .25
    ];
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point =
          Offset(size.width * i / (points.length - 1), size.height * points[i]);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppTheme.green
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RangeCard extends StatelessWidget {
  const _RangeCard(
      {required this.title, required this.label, required this.color});
  final String title, label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(9)),
      child: Column(children: [
        Text(title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11))
      ]));
}
