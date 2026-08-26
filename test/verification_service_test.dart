import 'package:flutter_test/flutter_test.dart';
import 'package:pulso_minero/services/verification_service.dart';

void main() {
  test('genera un código de seis dígitos y valida el código correcto',
      () async {
    final service = DemoVerificationService();
    await service.sendCode(
        email: 'minero@empresa.com', purpose: VerificationPurpose.registration);

    final code = service.lastDemoCode!;
    expect(code, hasLength(6));
    expect(
        await service.verifyCode(
            email: 'minero@empresa.com',
            code: code,
            purpose: VerificationPurpose.registration),
        isTrue);
    expect(
        await service.verifyCode(
            email: 'minero@empresa.com',
            code: code,
            purpose: VerificationPurpose.registration),
        isFalse);
  });

  test('rechaza un código incorrecto', () async {
    final service = DemoVerificationService();
    await service.sendCode(
        email: 'minero@empresa.com',
        purpose: VerificationPurpose.passwordRecovery);

    expect(
        await service.verifyCode(
            email: 'minero@empresa.com',
            code: '000000',
            purpose: VerificationPurpose.passwordRecovery),
        isFalse);
  });

  test('rechaza un código vencido', () async {
    var now = DateTime(2026, 8, 25, 10);
    final service = DemoVerificationService(clock: () => now);
    await service.sendCode(
        email: 'minero@empresa.com', purpose: VerificationPurpose.registration);
    final code = service.lastDemoCode!;
    now = now.add(const Duration(minutes: 11));

    expect(
        await service.verifyCode(
            email: 'minero@empresa.com',
            code: code,
            purpose: VerificationPurpose.registration),
        isFalse);
  });
}
