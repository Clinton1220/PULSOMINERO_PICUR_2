import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/analysis_result.dart';
import '../../models/sensor_data.dart';
import '../../models/vibration_record.dart';
import '../../services/ai_service.dart';
import '../../services/ble_sensor_service.dart';
import '../../services/sensor_service.dart';
import '../../services/storage_service.dart';
import '../../services/wifi_sensor_service.dart';

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

enum ConnectionType { simulator, ble, wifi }

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  final ai = AiService();
  final samples = <SensorData>[];
  late SensorService sensor;
  StreamSubscription<SensorData>? subscription;
  AnalysisResult? result;
  DemoMode selectedMode = DemoMode.isolated;
  bool isCapturing = false;
  ConnectionType activeConnection = ConnectionType.simulator;
  String wifiIp = '192.168.4.1';

  // Calibración de cero (Tara)
  double zeroOffsetX = 0.0;
  double zeroOffsetY = 0.0;
  double zeroOffsetZ = 0.0;
  bool isZeroCalibrated = false;

  @override
  void initState() {
    super.initState();
    sensor = SensorSimulator();
    _listenToSensor();
  }

  void _listenToSensor() {
    subscription = sensor.readings.listen((reading) {
      if (mounted) setState(() => samples.add(reading));
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    sensor.dispose();
    super.dispose();
  }

  void calibrateZero() {
    if (samples.isEmpty) return;
    final last = samples.last;
    setState(() {
      zeroOffsetX = last.accelerationX;
      zeroOffsetY = last.accelerationY;
      zeroOffsetZ = last.accelerationZ - 9.81;
      isZeroCalibrated = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Punto cero calibrado. Mediciones ajustadas a 0.00 m/s²'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void resetCalibration() {
    setState(() {
      zeroOffsetX = 0.0;
      zeroOffsetY = 0.0;
      zeroOffsetZ = 0.0;
      isZeroCalibrated = false;
    });
  }

  Future<void> startDemo() async {
    samples.clear();
    result = null;
    sensor.setDemoMode(selectedMode);
    await sensor.connect();
    if (mounted) {
      setState(() {
        activeConnection = ConnectionType.simulator;
        isCapturing = true;
      });
    }
  }

  Future<void> connectEsp32Ble() async {
    if (isCapturing) return;
    await subscription?.cancel();
    await sensor.dispose();
    sensor = BleSensorService();
    _listenToSensor();
    try {
      await sensor.connect();
      if (mounted) {
        setState(() {
          activeConnection = ConnectionType.ble;
          isCapturing = true;
        });
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        await sensor.disconnect();
        setState(() => activeConnection = ConnectionType.simulator);
      }
    }
  }

  Future<void> showWifiDialog() async {
    final controller = TextEditingController(text: wifiIp);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.wifi, color: AppTheme.green),
            SizedBox(width: 10),
            Text('Conexión Wi-Fi ESP32'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Conéctate a la red "PulsoMinero-WiFi" (clave: 12345678) y presiona Conectar.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Dirección IP del ESP32',
                hintText: '192.168.4.1',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.router),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              wifiIp = controller.text.trim();
              Navigator.pop(ctx, true);
            },
            child: const Text('Conectar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await connectEsp32Wifi(wifiIp);
    }
  }

  Future<void> connectEsp32Wifi(String ip) async {
    if (isCapturing) return;
    await subscription?.cancel();
    await sensor.dispose();
    sensor = WifiSensorService(host: ip, port: 81);
    _listenToSensor();
    try {
      await sensor.connect();
      if (mounted) {
        setState(() {
          activeConnection = ConnectionType.wifi;
          isCapturing = true;
        });
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        await sensor.disconnect();
        setState(() => activeConnection = ConnectionType.simulator);
      }
    }
  }

  Future<void> stopAndAnalyze() async {
    await sensor.disconnect();
    final analysis = ai.analyze(samples);
    await widget.storage.saveRecord(VibrationRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        startedAt: samples.isEmpty ? DateTime.now() : samples.first.timestamp,
        samples: List.unmodifiable(samples),
        analysis: analysis));
    if (mounted) {
      setState(() {
        isCapturing = false;
        result = analysis;
      });
    }
  }

  void showRawPayloadModal() {
    final lastPayload = samples.isEmpty
        ? 'No hay tramas recibidas aún. Conecta el ESP32 para ver la telemetría en tiempo real.'
        : samples.last.rawPayload.isNotEmpty
            ? samples.last.rawPayload
            : samples.last.toJson().toString();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.terminal, color: AppTheme.green),
                SizedBox(width: 10),
                Text('Inspector de Telemetría JSON (ESP32)',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Trama de datos cruda transmitida por Socket TCP/IP desde el microcontrolador:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: SelectableText(
                lastPayload,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: AppTheme.lime,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getConnectionStatusText() {
    if (!isCapturing) {
      return 'Listo para conectar por Wi-Fi, Bluetooth o Simulador';
    }
    switch (activeConnection) {
      case ConnectionType.ble:
        return 'ESP32 conectado · Transmitiendo por Bluetooth BLE';
      case ConnectionType.wifi:
        return 'ESP32 conectado · Transmitiendo por Wi-Fi ($wifiIp:81)';
      case ConnectionType.simulator:
        return 'Modo Simulador de Pruebas · Capturando muestras';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastSample = samples.isEmpty ? null : samples.last;
    final rawCurrent = lastSample?.magnitude ?? 0.0;
    final adjX = (lastSample?.accelerationX ?? 0.0) - zeroOffsetX;
    final adjY = (lastSample?.accelerationY ?? 0.0) - zeroOffsetY;
    final adjZ = (lastSample?.accelerationZ ?? 0.0) - zeroOffsetZ;
    final currentMagnitude = isZeroCalibrated
        ? (adjX * adjX + adjY * adjY + adjZ * adjZ > 0
            ? lastSample?.dynamicVibration ?? 0.0
            : 0.0)
        : rawCurrent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // Encabezado
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Monitoreo en tiempo real',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_getConnectionStatusText(),
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            IconButton(
              onPressed: showRawPayloadModal,
              tooltip: 'Ver trama JSON cruda',
              icon: const Icon(Icons.code, color: AppTheme.lime),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 1. BARRA DE ESTADO DE SALUD DE LOS SENSORES
        _SensorHealthBar(
          isEspOnline: isCapturing,
          activeConn: activeConnection,
          wifiIp: wifiIp,
          isMpuOk: lastSample?.mpuOk ?? true,
          isMqOk: lastSample?.mqOk ?? true,
          chipTemp: lastSample?.temperature ?? 25.0,
          gasVolt: lastSample?.gasVoltage ?? 1.25,
        ),
        const SizedBox(height: 14),

        // 2. SELECTOR DE MODO
        _ModeSelector(
          value: selectedMode,
          enabled: !isCapturing,
          onChanged: (mode) => setState(() => selectedMode = mode),
        ),
        const SizedBox(height: 14),

        // 3. TARJETA PRINCIPAL DE LECTURAS Y OSCILOSCOPIO
        _ReadingCard(
          value: currentMagnitude,
          sampleCount: samples.length,
          inclination: lastSample?.inclination ?? 0.0,
          roll: lastSample?.roll ?? 0.0,
          gasPpm: lastSample?.gasPpm ?? 0.0,
          accelX: adjX,
          accelY: adjY,
          accelZ: adjZ,
          chipTemp: lastSample?.temperature ?? 25.0,
          isZeroCalibrated: isZeroCalibrated,
          onCalibrate: calibrateZero,
          onResetCalibrate: resetCalibration,
          recentSamples: samples.isEmpty
              ? [0.0]
              : samples
                  .sublist(samples.length > 35 ? samples.length - 35 : 0)
                  .map((s) => s.magnitude)
                  .toList(),
        ),
        const SizedBox(height: 14),

        // 4. BOTONES DE CONEXIÓN Y ACCIÓN
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isCapturing ? null : connectEsp32Ble,
                icon: const Icon(Icons.bluetooth, size: 18),
                label: const Text('Bluetooth'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isCapturing ? null : showWifiDialog,
                icon: const Icon(Icons.wifi, size: 18),
                label: const Text('Wi-Fi (ESP32)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        FilledButton.icon(
          onPressed: isCapturing ? stopAndAnalyze : startDemo,
          icon: Icon(isCapturing
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outline),
          label: Text(
              isCapturing ? 'Detener ensayo y analizar con IA' : 'Iniciar Simulador'),
          style: FilledButton.styleFrom(
            backgroundColor:
                isCapturing ? Colors.redAccent : AppTheme.green,
            foregroundColor: isCapturing ? Colors.white : Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
        const SizedBox(height: 16),

        // 5. RESULTADOS DE IA O INSTRUCCIONES
        if (result != null)
          _ResultCard(result: result!)
        else
          const _InstructionCard(),
      ],
    );
  }
}

class _SensorHealthBar extends StatelessWidget {
  const _SensorHealthBar({
    required this.isEspOnline,
    required this.activeConn,
    required this.wifiIp,
    required this.isMpuOk,
    required this.isMqOk,
    required this.chipTemp,
    required this.gasVolt,
  });

  final bool isEspOnline;
  final ConnectionType activeConn;
  final String wifiIp;
  final bool isMpuOk;
  final bool isMqOk;
  final double chipTemp;
  final double gasVolt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ESP32 Health
          _HealthBadge(
            icon: Icons.memory,
            title: 'ESP32',
            subtitle: isEspOnline
                ? (activeConn == ConnectionType.wifi
                    ? 'Wi-Fi 81'
                    : (activeConn == ConnectionType.ble ? 'BLE' : 'Sim'))
                : 'Offline',
            isOk: isEspOnline,
          ),
          const VerticalDivider(width: 1),
          // MPU6050 Health
          _HealthBadge(
            icon: Icons.sensors,
            title: 'MPU6050',
            subtitle: isMpuOk ? '${chipTemp.toStringAsFixed(0)}°C · ±2g' : 'Fallo I2C',
            isOk: isMpuOk && isEspOnline,
          ),
          const VerticalDivider(width: 1),
          // MQ-135 Health
          _HealthBadge(
            icon: Icons.air,
            title: 'MQ-135',
            subtitle: isMqOk ? '${gasVolt.toStringAsFixed(2)}V · Activo' : 'Fallo ADC',
            isOk: isMqOk && isEspOnline,
          ),
        ],
      ),
    );
  }
}

class _HealthBadge extends StatelessWidget {
  const _HealthBadge({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isOk,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isOk;

  @override
  Widget build(BuildContext context) {
    final color = isOk ? AppTheme.green : Colors.grey;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            Text(subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ],
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.value,
    required this.sampleCount,
    required this.inclination,
    required this.roll,
    required this.gasPpm,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.chipTemp,
    required this.isZeroCalibrated,
    required this.onCalibrate,
    required this.onResetCalibrate,
    required this.recentSamples,
  });

  final double value;
  final int sampleCount;
  final double inclination;
  final double roll;
  final double gasPpm;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double chipTemp;
  final bool isZeroCalibrated;
  final VoidCallback onCalibrate;
  final VoidCallback onResetCalibrate;
  final List<double> recentSamples;

  @override
  Widget build(BuildContext context) {
    final isGasAlert = gasPpm > 1000;
    final isGasWarning = gasPpm > 600;
    final gasColor = isGasAlert
        ? Colors.redAccent
        : (isGasWarning ? Colors.amber : AppTheme.green);
    final gasStatus = isGasAlert
        ? 'Peligro'
        : (isGasWarning ? 'Precaución' : 'Seguro');

    final isVibHigh = value >= 2.0;
    final isVibMed = value >= 1.0;
    final vibColor = isVibHigh
        ? Colors.redAccent
        : (isVibMed ? Colors.amber : AppTheme.green);

    return Column(
      children: [
        // 1. TARJETA MPU6050: VIBRACIÓN E INCLINACIÓN
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sensors, color: vibColor, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Vibración Resultante (Geófono)',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          '${value.toStringAsFixed(2)} m/s²',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: vibColor),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: vibColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isVibHigh
                              ? 'Alerta Crítica'
                              : (isVibMed ? 'Precaución' : 'Normal'),
                          style: TextStyle(
                              color: vibColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pitch: ${inclination.toStringAsFixed(1)}° · Roll: ${roll.toStringAsFixed(1)}°',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Osciloscopio en tiempo real
              Container(
                height: 75,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: CustomPaint(
                  painter: _LiveWaveformPainter(
                    samples: recentSamples,
                    lineColor: vibColor,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Desglose de 3 ejes X, Y, Z
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _AxisChip(label: 'X', value: accelX, color: Colors.orangeAccent),
                  _AxisChip(label: 'Y', value: accelY, color: Colors.tealAccent),
                  _AxisChip(label: 'Z', value: accelZ, color: Colors.lightBlueAccent),
                ],
              ),
              const SizedBox(height: 10),

              // Barra de herramientas de calibración y conteo
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: isZeroCalibrated ? onResetCalibrate : onCalibrate,
                    icon: Icon(
                      isZeroCalibrated ? Icons.restart_alt : Icons.filter_alt,
                      size: 15,
                      color: AppTheme.lime,
                    ),
                    label: Text(
                      isZeroCalibrated ? 'Restablecer Tara' : 'Calibrar Cero (Tara)',
                      style: const TextStyle(fontSize: 11, color: AppTheme.lime),
                    ),
                  ),
                  Text(
                    '$sampleCount muestras · ${chipTemp.toStringAsFixed(1)}°C',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 2. TARJETA MQ-135: GAS Y CALIDAD DE AIRE
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.air, color: gasColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Atmósfera / Gas Minero (MQ-135)',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          gasPpm > 0
                              ? '${gasPpm.toStringAsFixed(0)} PPM'
                              : 'Ambiente Seguro',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: gasColor),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: gasColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      gasStatus,
                      style: TextStyle(
                          color: gasColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (gasPpm / 2000.0).clamp(0.05, 1.0),
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(gasColor),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AxisChip extends StatelessWidget {
  const _AxisChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          Text(
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _LiveWaveformPainter extends CustomPainter {
  _LiveWaveformPainter({required this.samples, required this.lineColor});
  final List<double> samples;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.35),
          lineColor.withValues(alpha: 0.0)
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    // Normalizar muestras
    final maxVal = samples.reduce((a, b) => a > b ? a : b).clamp(3.0, 20.0);
    final dx = size.width / (samples.length > 1 ? (samples.length - 1) : 1);

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < samples.length; i++) {
      final x = i * dx;
      final normalized = (samples[i] / maxVal).clamp(0.0, 1.0);
      final y = size.height - (normalized * (size.height - 8) + 4);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LiveWaveformPainter oldDelegate) => true;
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector(
      {required this.value, required this.enabled, required this.onChanged});
  final DemoMode value;
  final bool enabled;
  final ValueChanged<DemoMode> onChanged;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tipo de ensayo para IA',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        Row(children: [
          Expanded(
              child: ChoiceChip(
                  label: const Text('Aislada (Golpe único)'),
                  selected: value == DemoMode.isolated,
                  onSelected:
                      enabled ? (_) => onChanged(DemoMode.isolated) : null)),
          const SizedBox(width: 10),
          Expanded(
              child: ChoiceChip(
                  label: const Text('Sostenida (Maquinaria)'),
                  selected: value == DemoMode.sustained,
                  onSelected:
                      enabled ? (_) => onChanged(DemoMode.sustained) : null))
        ])
      ]);
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
          'Conecta el ESP32 por Wi-Fi o Bluetooth. Los datos de vibración (MPU6050), inclinación y gas (MQ-135) se reciben en tiempo real. Al detener el ensayo, la IA evaluará el patrón y generará el informe explicativo.',
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
          border: Border.all(color: AppTheme.green.withValues(alpha: .5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.psychology_outlined, color: AppTheme.lime),
          const SizedBox(width: 10),
          Expanded(
              child: Text(result.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold))),
          Text('${(result.confidence * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                  color: AppTheme.lime, fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 12),
        Text(
            'Amplitud máxima: ${result.maximumAmplitude.toStringAsFixed(2)} m/s²'),
        Text(
            'Riesgo: ${result.riskLevel} · Repeticiones: ${result.repetitions}'),
        const SizedBox(height: 12),
        const Text('Explicación y Diagnóstico:',
            style:
                TextStyle(color: AppTheme.lime, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...result.reasons.map((reason) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $reason')))
      ]));
}
