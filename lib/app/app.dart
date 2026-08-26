import 'package:flutter/material.dart';

import '../models/user_session.dart';
import '../screens/home/home_screen.dart';
import '../screens/login/login_screen.dart';
import 'theme.dart';

class PulsoMineroApp extends StatelessWidget {
  const PulsoMineroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulsoMinero',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const LoginScreen(),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return Image.asset('assets/images/logo.png',
          width: 360,
          height: 230,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    return const Text.rich(TextSpan(children: [
      TextSpan(
          text: 'Pulso',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      TextSpan(
          text: 'Minero',
          style: TextStyle(
              color: AppTheme.green, fontSize: 20, fontWeight: FontWeight.w800))
    ]));
  }
}

void openDashboard(BuildContext context, UserSession session) {
  Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(session: session)));
}
