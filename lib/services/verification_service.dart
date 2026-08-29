import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

enum VerificationPurpose { registration, passwordRecovery }

class VerificationRequest {
  const VerificationRequest(
      {required this.email, required this.purpose, required this.expiresAt});

  final String email;
  final VerificationPurpose purpose;
  final DateTime expiresAt;
}

abstract class VerificationService {
  Future<VerificationRequest> sendCode(
      {required String email, required VerificationPurpose purpose});
  Future<bool> verifyCode(
      {required String email,
      required String code,
      required VerificationPurpose purpose});
  bool canResend({required String email, required VerificationPurpose purpose});
  String? get demoCode;
  String? get verificationToken;
}

class DemoVerificationService implements VerificationService {
  DemoVerificationService({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _random = Random.secure();
  final _requests = <String, _PendingCode>{};
  String? lastDemoCode;

  @override
  String? get demoCode => lastDemoCode;

  @override
  String? get verificationToken => null;

  @override
  Future<VerificationRequest> sendCode(
      {required String email, required VerificationPurpose purpose}) async {
    final key = _key(email, purpose);
    final current = _requests[key];
    if (current != null &&
        _clock().difference(current.sentAt) < const Duration(seconds: 60)) {
      throw StateError('Espera 60 segundos antes de solicitar otro código.');
    }
    final code = (100000 + _random.nextInt(900000)).toString();
    final expiresAt = _clock().add(const Duration(minutes: 10));
    _requests[key] =
        _PendingCode(code: code, sentAt: _clock(), expiresAt: expiresAt);
    lastDemoCode = code;
    return VerificationRequest(
        email: email, purpose: purpose, expiresAt: expiresAt);
  }

  @override
  Future<bool> verifyCode(
      {required String email,
      required String code,
      required VerificationPurpose purpose}) async {
    final key = _key(email, purpose);
    final pending = _requests[key];
    if (pending == null || _clock().isAfter(pending.expiresAt)) {
      _requests.remove(key);
      return false;
    }
    final valid = _constantTimeEquals(pending.code, code.trim());
    if (valid) _requests.remove(key);
    return valid;
  }

  @override
  bool canResend(
      {required String email, required VerificationPurpose purpose}) {
    final pending = _requests[_key(email, purpose)];
    return pending == null ||
        _clock().difference(pending.sentAt) >= const Duration(seconds: 60);
  }

  String _key(String email, VerificationPurpose purpose) =>
      '${purpose.name}:${email.trim().toLowerCase()}';

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}

class HttpVerificationService implements VerificationService {
  HttpVerificationService({required this.baseUrl});

  final String baseUrl;
  String? _verificationToken;

  @override
  String? get demoCode => null;

  @override
  String? get verificationToken => _verificationToken;

  @override
  Future<VerificationRequest> sendCode(
      {required String email, required VerificationPurpose purpose}) async {
    final response = await http.post(Uri.parse('$baseUrl/auth/request-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim(), 'purpose': purpose.name}));
    if (response.statusCode != 202) throw StateError(_errorMessage(response));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return VerificationRequest(
        email: email.trim(),
        purpose: purpose,
        expiresAt: DateTime.parse(data['expiresAt'] as String));
  }

  @override
  Future<bool> verifyCode(
      {required String email,
      required String code,
      required VerificationPurpose purpose}) async {
    final response = await http.post(Uri.parse('$baseUrl/auth/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'code': code.trim(),
          'purpose': purpose.name
        }));
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _verificationToken = data['verificationToken'] as String?;
    return data['verified'] == true;
  }

  @override
  bool canResend(
          {required String email, required VerificationPurpose purpose}) =>
      true;

  String _errorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['error'] as String? ?? 'No se pudo enviar el código.';
    } catch (_) {
      return 'No se pudo enviar el código.';
    }
  }
}

VerificationService createVerificationService() {
  const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://localhost:3000');
  if (apiBaseUrl.isEmpty) return DemoVerificationService();
  return HttpVerificationService(
      baseUrl: apiBaseUrl.replaceAll(RegExp(r'/$'), ''));
}

class _PendingCode {
  const _PendingCode(
      {required this.code, required this.sentAt, required this.expiresAt});

  final String code;
  final DateTime sentAt;
  final DateTime expiresAt;
}
