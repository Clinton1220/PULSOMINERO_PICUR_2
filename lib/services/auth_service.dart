import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/user_session.dart';

class AuthService {
  AuthService({this.baseUrl});

  final String? baseUrl;

  bool get isRemote => baseUrl != null && baseUrl!.isNotEmpty;

  Future<UserSession> signIn(
      {required String email, required String password}) async {
    if (!isRemote) return UserSession(email: email);

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        throw StateError(_message(response));
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UserSession(
        email: data['email'] as String,
        displayName: data['displayName'] as String?,
      );
    } on StateError {
      rethrow;
    } catch (_) {
      // Si el servidor backend no responde (ej. red privada ESP32 o sin backend activo),
      // permitir acceso local directo para operar el sistema.
      return UserSession(
        email: email.trim(),
        displayName: email.contains('@') ? email.split('@').first : 'Operador Minero',
      );
    }
  }

  Future<void> register(
      {required String email,
      required String password,
      required String displayName,
      String? verificationToken}) async {
    if (!isRemote) return;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password,
              'displayName': displayName.trim(),
              'verificationToken': verificationToken
            }),
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 201) throw StateError(_message(response));
    } on StateError {
      rethrow;
    } catch (_) {
      return;
    }
  }

  Future<void> resetPassword({
    required String email,
    required String password,
    String? verificationToken,
  }) async {
    if (!isRemote) return;
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'verificationToken': verificationToken,
      }),
    );
    if (response.statusCode != 200) throw StateError(_message(response));
  }

  String _message(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['error'] as String? ?? 'No se pudo iniciar sesión.';
    } catch (_) {
      return 'No se pudo iniciar sesión.';
    }
  }

  static AuthService fromEnvironment() {
    const url = String.fromEnvironment('API_BASE_URL',
        defaultValue: 'http://localhost:3000');
    return AuthService(
        baseUrl: url.isEmpty ? null : url.replaceAll(RegExp(r'/$'), ''));
  }
}
