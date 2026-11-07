import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/analysis_result.dart';
import '../../models/sensor_data.dart';
import '../../models/vibration_record.dart';
import '../../services/ai_service.dart';
import '../../services/alert_sound_service.dart';
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

enum ConnectionType { none, ble, wifi }

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  final ai = AiService();
  final _alertSoundService = AlertSoundService();
  final samples = <SensorData>[];
  SensorService? sensor;
  StreamSubscription<SensorData>? subscription;
  AnalysisResult? result;
  bool isCapturing = false;
  bool isPaused = false;
  ConnectionType activeConnection = ConnectionType.none;
  String wifiIp = '192.168.4.1';

  // Filtro de Suavizado EMA (Anti-ruido y estabilidad de señal)
  bool isFilterEnabled = true;
  static const double _smoothAlpha = 0.28; // Factor de suavizado (reactivo y estable)
  double? _emaMagnitude;
  double? _emaX;
  double? _emaY;
  double? _emaZ;
  double? _emaGas;
  double? _emaPitch;
  double? _emaRoll;

  void _resetEma() {
    _emaMagnitude = null;
    _emaX = null;
    _emaY = null;
    _emaZ = null;
    _emaGas = null;
    _emaPitch = null;
    _emaRoll = null;
  }

  void _updateEma(SensorData reading) {
    final currentMag = reading.dynamicVibration;
    final adjX = reading.accelerationX;
    final adjY = reading.accelerationY;
    final adjZ = reading.accelerationZ;

    if (_emaMagnitude == null) {
      _emaMagnitude = currentMag;
      _emaX = adjX;
      _emaY = adjY;
      _emaZ = adjZ;
      _emaGas = reading.gasPpm;
      _emaPitch = reading.inclination;
      _emaRoll = reading.roll;
    } else {
      _emaMagnitude = (_smoothAlpha * currentMag) + ((1.0 - _smoothAlpha) * _emaMagnitude!);
      _emaX = (_smoothAlpha * adjX) + ((1.0 - _smoothAlpha) * _emaX!);
      _emaY = (_smoothAlpha * adjY) + ((1.0 - _smoothAlpha) * _emaY!);
      _emaZ = (_smoothAlpha * adjZ) + ((1.0 - _smoothAlpha) * _emaZ!);
      _emaGas = (_smoothAlpha * reading.gasPpm) + ((1.0 - _smoothAlpha) * _emaGas!);
      _emaPitch = (_smoothAlpha * reading.inclination) + ((1.0 - _smoothAlpha) * _emaPitch!);
      _emaRoll = (_smoothAlpha * reading.roll) + ((1.0 - _smoothAlpha) * _emaRoll!);
    }
  }

  void toggleFilter() {
    setState(() {
      isFilterEnabled = !isFilterEnabled;
      if (isFilterEnabled) _resetEma();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isFilterEnabled
            ? '✨ Filtro EMA activado: Señal suavizada y anti-ruido'
            : '⚡ Filtro desactivado: Mostrando señal cruda instantánea'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  List<double> _getDisplayWaveformSamples() {
    if (samples.isEmpty) return [0.0];
    final window = samples.sublist(samples.length > 35 ? samples.length - 35 : 0);
    final rawList = window.map((s) => s.dynamicVibration).toList();

    if (!isFilterEnabled || rawList.length < 3) return rawList;

    // Suavizado EMA progresivo sobre la ventana reciente para curva continua
    final smoothed = <double>[];
    double current = rawList.first;
    for (final val in rawList) {
      current = (_smoothAlpha * val) + ((1.0 - _smoothAlpha) * current);
      smoothed.add(current);
    }
    return smoothed;
  }

  void _listenToSensor() {
    subscription = sensor?.readings.listen((reading) {
      if (mounted && !isPaused) {
        setState(() {
          samples.add(reading);
          _updateEma(reading);
        });

        final currentVib = isFilterEnabled && _emaMagnitude != null
            ? _emaMagnitude!
            : reading.dynamicVibration;
        final currentGas = isFilterEnabled && _emaGas != null
            ? _emaGas!
            : reading.gasPpm;

        _alertSoundService.checkAndAlert(
          vibration: currentVib,
          gasPpm: currentGas,
        );
      }
    });
  }

  void togglePause() {
    setState(() {
      isPaused = !isPaused;
    });
    if (isPaused) {
      _alertSoundService.stop();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isPaused
            ? '⏸️ Proceso en pausa (datos congelados)'
            : '▶️ Proceso reanudado (monitoreo en vivo)'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _alertSoundService.dispose();
    subscription?.cancel();
    sensor?.dispose();
    super.dispose();
  }

  Future<void> connectEsp32Ble() async {
    if (isCapturing) return;
    await _alertSoundService.stop();
    samples.clear();
    _resetEma();
    result = null;
    await subscription?.cancel();
    await sensor?.dispose();
    sensor = BleSensorService();
    _listenToSensor();
    try {
      await sensor!.connect();
      if (mounted) {
        setState(() {
          activeConnection = ConnectionType.ble;
          isCapturing = true;
          isPaused = false;
        });
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        await sensor?.disconnect();
        setState(() => activeConnection = ConnectionType.none);
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
    await _alertSoundService.stop();
    samples.clear();
    _resetEma();
    result = null;
    await subscription?.cancel();
    await sensor?.dispose();
    sensor = WifiSensorService(host: ip, port: 81);
    _listenToSensor();
    try {
      await sensor!.connect();
      if (mounted) {
        setState(() {
          activeConnection = ConnectionType.wifi;
          isCapturing = true;
          isPaused = false;
        });
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        await sensor?.disconnect();
        setState(() => activeConnection = ConnectionType.none);
      }
    }
  }

  Future<void> stopAndAnalyze() async {
    await _alertSoundService.stop();
    await sensor?.disconnect();
    final analysis = ai.analyze(samples);
    final newRecord = VibrationRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      startedAt: samples.isEmpty ? DateTime.now() : samples.first.timestamp,
      samples: List.unmodifiable(samples),
      analysis: analysis,
    );
    final isSynced = await widget.storage.saveRecord(newRecord);
    if (mounted) {
      setState(() {
        isCapturing = false;
        isPaused = false;
        result = analysis;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surface,
          content: Row(
            children: [
              Icon(
                isSynced ? Icons.cloud_done : Icons.save,
                color: isSynced ? AppTheme.green : Colors.amber,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isSynced
                      ? '☁️ Ensayo guardado y sincronizado en Firebase Firestore'
                      : '💾 Ensayo guardado localmente (se sincronizará al conectar internet)',
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
      return 'Listo para conectar al ESP32 por Wi-Fi o Bluetooth';
    }
    if (isPaused) {
      return '⏸️ PROCESO PAUSADO · Pantalla congelada (toca Reanudar)';
    }
    switch (activeConnection) {
      case ConnectionType.ble:
        return 'ESP32 conectado · Transmitiendo por Bluetooth BLE';
      case ConnectionType.wifi:
        return 'ESP32 conectado · Transmitiendo por Wi-Fi ($wifiIp:81)';
      case ConnectionType.none:
        return 'Sin conexión activa';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastSample = samples.isEmpty ? null : samples.last;
    final currentMagnitude = lastSample?.dynamicVibration ?? 0.0;
    final adjX = lastSample?.accelerationX ?? 0.0;
    final adjY = lastSample?.accelerationY ?? 0.0;
    final adjZ = lastSample?.accelerationZ ?? 0.0;

    // Valores para visualización (suavizados si isFilterEnabled es true)
    final displayMagnitude = isFilterEnabled ? (_emaMagnitude ?? currentMagnitude) : currentMagnitude;
    final displayX = isFilterEnabled ? (_emaX ?? adjX) : adjX;
    final displayY = isFilterEnabled ? (_emaY ?? adjY) : adjY;
    final displayZ = isFilterEnabled ? (_emaZ ?? adjZ) : adjZ;
    final displayGas = isFilterEnabled ? (_emaGas ?? (lastSample?.gasPpm ?? 0.0)) : (lastSample?.gasPpm ?? 0.0);
    final displayPitch = isFilterEnabled ? (_emaPitch ?? (lastSample?.inclination ?? 0.0)) : (lastSample?.inclination ?? 0.0);
    final displayRoll = isFilterEnabled ? (_emaRoll ?? (lastSample?.roll ?? 0.0)) : (lastSample?.roll ?? 0.0);

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

        // 2. TARJETA PRINCIPAL DE LECTURAS Y OSCILOSCOPIO
        _ReadingCard(
          value: displayMagnitude,
          sampleCount: samples.length,
          inclination: displayPitch,
          roll: displayRoll,
          gasPpm: displayGas,
          accelX: displayX,
          accelY: displayY,
          accelZ: displayZ,
          chipTemp: lastSample?.temperature ?? 25.0,
          isFilterEnabled: isFilterEnabled,
          onToggleFilter: toggleFilter,
          recentSamples: _getDisplayWaveformSamples(),
        ),
        const SizedBox(height: 14),

        // 3. BOTONES DE CONEXIÓN Y ACCIÓN
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

        if (isCapturing) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: togglePause,
                  icon: Icon(
                    isPaused ? Icons.play_arrow : Icons.pause,
                    color: isPaused ? AppTheme.green : Colors.amber,
                    size: 20,
                  ),
                  label: Text(
                    isPaused ? 'Reanudar' : 'Pausar',
                    style: TextStyle(
                      color: isPaused ? AppTheme.green : Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isPaused ? AppTheme.green : Colors.amber,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: stopAndAnalyze,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Detener y Analizar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),

        // 4. RESULTADOS DE IA O INSTRUCCIONES
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
                ? (activeConn == ConnectionType.wifi ? 'Wi-Fi 81' : 'BLE')
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
    required this.isFilterEnabled,
    required this.onToggleFilter,
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
  final bool isFilterEnabled;
  final VoidCallback onToggleFilter;
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
                        Row(
                          children: [
                            Text(
                              '${value.toStringAsFixed(2)} m/s²',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: vibColor),
                            ),
                            if (isFilterEnabled) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.lime.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: AppTheme.lime.withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  'EMA SUAVE',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.lime),
                                ),
                              ),
                            ],
                          ],
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
                    isSmooth: isFilterEnabled,
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

              // Barra de herramientas de calibración, filtro anti-ruido y conteo
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      InkWell(
                        onTap: onToggleFilter,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isFilterEnabled
                                ? AppTheme.green.withValues(alpha: 0.18)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isFilterEnabled
                                  ? AppTheme.green.withValues(alpha: 0.5)
                                  : Colors.white24,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 12,
                                color: isFilterEnabled
                                    ? AppTheme.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isFilterEnabled ? 'Filtro ON' : 'Filtro OFF',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isFilterEnabled
                                      ? AppTheme.green
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$sampleCount pts · ${chipTemp.toStringAsFixed(1)}°C',
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
  _LiveWaveformPainter({
    required this.samples,
    required this.lineColor,
    this.isSmooth = true,
  });

  final List<double> samples;
  final Color lineColor;
  final bool isSmooth;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

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

    final points = <Offset>[];
    for (var i = 0; i < samples.length; i++) {
      final x = i * dx;
      final normalized = (samples[i] / maxVal).clamp(0.0, 1.0);
      final y = size.height - (normalized * (size.height - 10) + 5);
      points.add(Offset(x, y));
    }

    final path = Path();
    final fillPath = Path();

    if (points.isNotEmpty) {
      path.moveTo(points.first.dx, points.first.dy);
      fillPath.moveTo(points.first.dx, size.height);
      fillPath.lineTo(points.first.dx, points.first.dy);

      if (isSmooth && points.length > 2) {
        for (var i = 1; i < points.length; i++) {
          final p0 = points[i - 1];
          final p1 = points[i];
          final midX = (p0.dx + p1.dx) / 2;
          path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
          fillPath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
        }
      } else {
        for (var i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
          fillPath.lineTo(points[i].dx, points[i].dy);
        }
      }

      fillPath.lineTo(points.last.dx, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWaveformPainter oldDelegate) => true;
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
