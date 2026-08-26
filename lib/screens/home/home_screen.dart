import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../models/user_session.dart';
import '../alerts/alerts_screen.dart';
import '../history/history_screen.dart';
import '../monitoring/live_monitoring_screen.dart';
import '../login/login_screen.dart';
import '../../services/storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final UserSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  final storage = StorageService();

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardContent(session: widget.session),
      LiveMonitoringScreen(storage: storage),
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
              icon: const Icon(Icons.notifications_none_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body:
          SafeArea(child: IndexedStack(index: selectedIndex, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        backgroundColor: const Color(0xFF111618),
        indicatorColor: AppTheme.green.withOpacity(.2),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: AppTheme.green),
              label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar, color: AppTheme.green),
              label: 'Monitoreo'),
          NavigationDestination(
              icon: Icon(Icons.history),
              selectedIcon: Icon(Icons.history, color: AppTheme.green),
              label: 'Historial'),
          NavigationDestination(
              icon: Icon(Icons.notifications_none),
              selectedIcon: Icon(Icons.notifications, color: AppTheme.green),
              label: 'Alertas'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: AppTheme.green),
              label: 'Ajustes'),
        ],
      ),
    );
  }
}

class DashboardContent extends StatelessWidget {
  const DashboardContent({super.key, required this.session});
  final UserSession session;

  @override
  Widget build(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          Text('¡Hola, ${session.name}!',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(session.email, style: const TextStyle(color: Color(0xFF8A9699))),
          const SizedBox(height: 18),
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: const Color(0xFF145D2D),
                  borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Estado general',
                          style: TextStyle(color: Color(0xFFA4D3AA))),
                      SizedBox(height: 4),
                      Text('Todo Normal',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('No se detectan vibraciones peligrosas',
                          style:
                              TextStyle(color: Color(0xFFA4D3AA), fontSize: 11))
                    ])),
                Icon(Icons.verified_user_outlined,
                    color: AppTheme.lime, size: 43)
              ])),
          const SizedBox(height: 18),
          const Row(children: [
            Expanded(
                child: MetricCard(
                    title: 'Vibración actual',
                    value: '0.28',
                    unit: 'mm/s',
                    status: 'Baja',
                    icon: Icons.graphic_eq)),
            SizedBox(width: 12),
            Expanded(
                child: MetricCard(
                    title: 'Inclinación',
                    value: '1.2',
                    unit: '°',
                    status: 'Estable',
                    icon: Icons.south_east))
          ]),
          const SizedBox(height: 12),
          const Row(children: [
            Expanded(
                child: MetricCard(
                    title: 'Nivel de riesgo',
                    value: 'BAJO',
                    unit: '',
                    status: 'Sin amenazas',
                    icon: Icons.shield_outlined)),
            SizedBox(width: 12),
            Expanded(
                child: MetricCard(
                    title: 'Temperatura',
                    value: '24.6',
                    unit: '°C',
                    status: 'Normal',
                    icon: Icons.thermostat))
          ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Actividad reciente',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            TextButton(
                onPressed: () {},
                child: const Text('Ver todo',
                    style: TextStyle(color: AppTheme.green)))
          ]),
          const ActivityTile(
              time: '09:35 AM',
              title: 'Vibración aislada detectada',
              detail: 'No requiere acción',
              color: AppTheme.green),
          const ActivityTile(
              time: '09:28 AM',
              title: 'Monitoreo iniciado',
              detail: 'Sistema activo',
              color: AppTheme.green),
        ]);
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard(
      {super.key,
      required this.title,
      required this.value,
      required this.unit,
      required this.status,
      required this.icon});
  final String title, value, unit, status;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border)),
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
                    style: const TextStyle(fontSize: 11, color: Colors.grey))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(icon, color: AppTheme.green, size: 15),
          const SizedBox(width: 4),
          Text(status,
              style: const TextStyle(color: AppTheme.green, fontSize: 11))
        ]),
      ]),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile(
      {super.key,
      required this.time,
      required this.title,
      required this.detail,
      required this.color});
  final String time, title, detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(9)),
      child: Row(children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 12),
        SizedBox(
            width: 62,
            child: Text(time,
                style: const TextStyle(fontSize: 11, color: Colors.grey))),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Text(detail, style: const TextStyle(fontSize: 11, color: Colors.grey))
        ]))
      ]));
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
                child: Icon(Icons.person, color: Colors.black)),
            title: Text(session.name),
            subtitle: Text(session.email),
            contentPadding: EdgeInsets.zero),
        const Divider(height: 30),
        ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Cerrar sesión'),
            onTap: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false))
      ]);
}
