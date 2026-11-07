import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../models/analysis_result.dart';
import '../../models/user_session.dart';
import '../../services/sensor_controller.dart';
import '../../services/storage_service.dart';
import '../alerts/alerts_screen.dart';
import '../history/history_screen.dart';
import '../login/login_screen.dart';
import '../monitoring/live_monitoring_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final UserSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  final storage = StorageService();
  late final sensorController = SensorController(storage: storage);

  @override
  void initState() {
    super.initState();
    storage.load();
  }

  @override
  void dispose() {
    sensorController.dispose();
    storage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardContent(
        session: widget.session,
        storage: storage,
        sensorController: sensorController,
        onNavigate: (index) => setState(() => selectedIndex = index),
      ),
      LiveMonitoringScreen(
        storage: storage,
        sensorController: sensorController,
      ),
      HistoryScreen(storage: storage),
      AlertsScreen(storage: storage),
      SettingsPage(session: widget.session),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const AppLogo(compact: true),
        actions: [
          IconButton(
            onPressed: () => setState(() => selectedIndex = 3),
            icon: const Icon(Icons.notifications_none_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        backgroundColor: const Color(0xFF111618),
        indicatorColor: AppTheme.green.withValues(alpha: .2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppTheme.green),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar, color: AppTheme.green),
            label: 'Monitoreo',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history, color: AppTheme.green),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications, color: AppTheme.green),
            label: 'Alertas',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: AppTheme.green),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    required this.session,
    required this.storage,
    required this.sensorController,
    required this.onNavigate,
  });

  final UserSession session;
  final StorageService storage;
  final SensorController sensorController;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([storage, sensorController]),
      builder: (context, _) {
        final isConnected = sensorController.isConnected;
        final latestRecord =
            storage.records.isNotEmpty ? storage.records.first : null;

        // Color y texto del Estado General
        final Color statusColor;
        final IconData statusIcon;
        final String statusTitle;
        final String statusDesc;

        if (!isConnected) {
          statusColor = const Color(0xFF192226);
          statusIcon = Icons.sensors_off_outlined;
          statusTitle = 'Sensor Desconectado';
          statusDesc =
              'Conéctate al ESP32 por Wi-Fi o Bluetooth para recibir telemetría en vivo';
        } else if (sensorController.isCritical) {
          statusColor = const Color(0xFF7A1C1C);
          statusIcon = Icons.warning_amber_rounded;
          statusTitle = '¡Alerta Crítica!';
          statusDesc =
              'Vibración o gas por encima del umbral de seguridad';
        } else if (sensorController.isWarning) {
          statusColor = const Color(0xFF7A5814);
          statusIcon = Icons.info_outline;
          statusTitle = 'Precaución';
          statusDesc =
              'Niveles de advertencia detectados en la galería';
        } else {
          statusColor = const Color(0xFF145D2D);
          statusIcon = Icons.verified_user_outlined;
          statusTitle = 'Todo Normal';
          statusDesc =
              'Conectado a ${sensorController.connectionLabel} · Sin anomalías';
        }

        // Métricas dinámicas en tiempo real
        final String vibVal;
        final String vibStatus;
        final Color vibColor;

        if (isConnected) {
          vibVal = sensorController.currentVibration.toStringAsFixed(2);
          vibStatus = sensorController.currentVibration >= 2.0
              ? 'Crítica'
              : (sensorController.currentVibration >= 1.0
                  ? 'Precaución'
                  : 'Normal');
          vibColor = sensorController.currentVibration >= 2.0
              ? Colors.redAccent
              : (sensorController.currentVibration >= 1.0
                  ? Colors.amber
                  : AppTheme.green);
        } else if (latestRecord != null) {
          vibVal = latestRecord.analysis.maximumAmplitude.toStringAsFixed(2);
          vibStatus = 'Último guardado';
          vibColor = Colors.grey;
        } else {
          vibVal = '0.00';
          vibStatus = 'Sin datos';
          vibColor = Colors.grey;
        }

        // Gas MQ-135
        final String gasVal;
        final String gasStatus;
        final Color gasColor;

        if (isConnected) {
          gasVal = sensorController.currentGas.toStringAsFixed(0);
          gasStatus = sensorController.currentGas > 1000
              ? 'Peligro'
              : (sensorController.currentGas > 600 ? 'Precaución' : 'Seguro');
          gasColor = sensorController.currentGas > 1000
              ? Colors.redAccent
              : (sensorController.currentGas > 600
                  ? Colors.amber
                  : AppTheme.green);
        } else {
          gasVal = '--';
          gasStatus = 'Desconectado';
          gasColor = Colors.grey;
        }

        // Inclinación Pitch
        final String incVal = isConnected
            ? '${sensorController.currentPitch.toStringAsFixed(1)}°'
            : (latestRecord != null && latestRecord.samples.isNotEmpty
                ? '${latestRecord.samples.last.inclination.toStringAsFixed(1)}°'
                : '--°');

        // Riesgo general
        final String riskVal = isConnected
            ? sensorController.riskLabel
            : (latestRecord != null
                ? latestRecord.analysis.riskLevel
                : 'DESCONECTADO');
        final Color riskColor = isConnected
            ? (sensorController.isCritical
                ? Colors.redAccent
                : (sensorController.isWarning
                    ? Colors.amber
                    : AppTheme.green))
            : Colors.grey;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            Text('¡Hola, ${session.name}!',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(session.email,
                style: const TextStyle(color: Color(0xFF8A9699))),
            const SizedBox(height: 18),

            // Tarjeta de Estado
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isConnected
                      ? (sensorController.isCritical
                          ? Colors.redAccent
                          : AppTheme.green.withValues(alpha: 0.3))
                      : AppTheme.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isConnected ? 'ESTADO EN VIVO' : 'ESTADO GENERAL',
                              style: TextStyle(
                                color:
                                    isConnected ? Colors.white70 : Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusTitle,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusDesc,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        statusIcon,
                        color: isConnected
                            ? (sensorController.isCritical
                                ? Colors.redAccent
                                : AppTheme.lime)
                            : Colors.grey,
                        size: 40,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!isConnected)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.green,
                              side: const BorderSide(color: AppTheme.green),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () => onNavigate(1),
                            icon: const Icon(Icons.sensors, size: 18),
                            label: const Text('Conectar Sensor en Monitoreo',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.green,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () => onNavigate(1),
                            icon: const Icon(Icons.show_chart, size: 18),
                            label: const Text(
                              'Ver Gráficas y Monitoreo Completo',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Tarjetas de Métricas Dinámicas
            Row(children: [
              Expanded(
                child: MetricCard(
                  title: 'Vibración Resultante',
                  value: vibVal,
                  unit: 'm/s²',
                  status: vibStatus,
                  statusColor: vibColor,
                  icon: Icons.graphic_eq,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  title: 'Gas MQ-135',
                  value: gasVal,
                  unit: 'PPM',
                  status: gasStatus,
                  statusColor: gasColor,
                  icon: Icons.air,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: MetricCard(
                  title: 'Inclinación (Pitch)',
                  value: incVal,
                  unit: '',
                  status: isConnected ? 'Estable' : 'Última ref.',
                  statusColor: AppTheme.green,
                  icon: Icons.south_east,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  title: 'Nivel de riesgo',
                  value: riskVal,
                  unit: '',
                  status: isConnected ? 'En vivo' : 'Sin señal',
                  statusColor: riskColor,
                  icon: Icons.shield_outlined,
                ),
              ),
            ]),

            const SizedBox(height: 24),

            // Actividad Reciente Real
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Actividad reciente',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => onNavigate(2),
                  child: const Text('Ver historial',
                      style: TextStyle(color: AppTheme.green)),
                ),
              ],
            ),

            if (storage.records.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aún no hay ensayos guardados. Conecta tu ESP32 en Monitoreo para iniciar.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...storage.records.take(3).map((record) {
                final isCrit = record.analysis.classification ==
                    VibrationClassification.highRiskVibration;
                final isMach = record.analysis.classification ==
                    VibrationClassification.machineryVibration;
                final color = isCrit
                    ? Colors.redAccent
                    : (isMach ? Colors.amber : AppTheme.green);
                final dateStr =
                    record.startedAt.toLocal().toString().substring(0, 16);

                return ActivityTile(
                  time: dateStr,
                  title: record.analysis.title,
                  detail:
                      'Amplitud: ${record.analysis.maximumAmplitude.toStringAsFixed(2)} m/s² · Duración: ${record.analysis.duration.inSeconds}s',
                  color: color,
                );
              }),
          ],
        );
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    required this.icon,
    this.statusColor,
  });

  final String title, value, unit, status;
  final IconData icon;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final color = statusColor ?? AppTheme.green;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(color: Color(0xFFAAB2B5), fontSize: 12)),
        const SizedBox(height: 9),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          if (unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 3),
              child: Text(unit,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              status,
              style: TextStyle(color: color, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ]),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({
    super.key,
    required this.time,
    required this.title,
    required this.detail,
    required this.color,
  });

  final String time, title, detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, color: color, size: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(time,
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(detail,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session});
  final UserSession session;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Ajustes',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: AppTheme.green,
            child: Icon(Icons.person, color: Colors.black),
          ),
          title: Text(session.name),
          subtitle: Text(session.email),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(height: 30),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Cerrar sesión'),
          onTap: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          ),
        ),
      ]);
}
