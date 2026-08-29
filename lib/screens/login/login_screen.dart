import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../models/user_session.dart';
import '../../services/auth_service.dart';
import '../../services/verification_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final nameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool isRegistering = false;
  bool obscurePassword = true;
  bool obscureConfirmation = true;
  bool acceptedTerms = false;
  bool isLoading = false;
  final verificationService = createVerificationService();
  final authService = AuthService.fromEnvironment();

  @override
  void dispose() {
    emailController.dispose();
    nameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Ingresa tu correo electrónico';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Ingresa un correo válido';
    }
    return null;
  }

  String? validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Ingresa tu nombre completo';
    if (name.length < 3) return 'El nombre es demasiado corto';
    return null;
  }

  String? validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Ingresa una contraseña';
    if (password.length < 8) return 'Debe tener mínimo 8 caracteres';
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Incluye una letra mayúscula';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Incluye una letra minúscula';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) return 'Incluye un número';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Incluye un símbolo';
    }
    return null;
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (isRegistering && !acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Acepta los términos para crear tu cuenta')));
      return;
    }
    if (isRegistering &&
        !await requestVerification(VerificationPurpose.registration)) {
      return;
    }
    setState(() => isLoading = true);
    try {
      if (isRegistering) {
        await authService.register(
          email: emailController.text,
          password: passwordController.text,
          displayName: nameController.text,
          verificationToken: verificationService.verificationToken,
        );
      }
      var session = await authService.signIn(
          email: emailController.text, password: passwordController.text);
      if (isRegistering && !authService.isRemote) {
        session = UserSession(
            email: emailController.text, displayName: nameController.text);
      }
      if (!mounted) return;
      openDashboard(context, session);
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<bool> requestVerification(VerificationPurpose purpose) async {
    try {
      await verificationService.sendCode(
        email: emailController.text,
        purpose: purpose,
      );
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return false;
    }

    if (!mounted) return false;
    final codeController = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verifica tu correo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enviamos un código a ${emailController.text.trim()}.'),
            if (verificationService.demoCode != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Modo demo: el código aparece debajo para poder probar el flujo.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                verificationService.demoCode!,
                style: const TextStyle(
                  color: AppTheme.lime,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Código de 6 dígitos',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final valid = await verificationService.verifyCode(
                email: emailController.text,
                code: codeController.text,
                purpose: purpose,
              );
              if (!valid) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código incorrecto o vencido')),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Verificar'),
          ),
        ],
      ),
    );
    codeController.dispose();
    return verified ?? false;
  }

  Future<void> recoverAccount() async {
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: emailController.text);
        return AlertDialog(
          title: const Text('Recuperar cuenta'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Enviar código'),
            ),
          ],
        );
      },
    );
    if (email == null ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return;
    }
    emailController.text = email;
    if (!await requestVerification(VerificationPurpose.passwordRecovery) ||
        !mounted) {
      return;
    }
    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Nueva contraseña'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña segura',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text('Guardar')),
          ],
        );
      },
    );
    if (newPassword == null) return;
    final error = validatePassword(newPassword);
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }

    try {
      await authService.resetPassword(
        email: email,
        password: newPassword,
        verificationToken: verificationService.verificationToken,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contraseña actualizada correctamente. Ya puedes iniciar sesión.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo restablecer la contraseña.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void toggleMode() {
    formKey.currentState?.reset();
    setState(() {
      isRegistering = !isRegistering;
      acceptedTerms = false;
    });
  }

  void googleSignIn() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Google Sign-In quedará conectado al configurar Firebase')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppLogo(),
                    const SizedBox(height: 20),
                    Text(
                        isRegistering
                            ? 'Crea tu cuenta'
                            : 'Bienvenido de nuevo',
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 7),
                    Text(
                        isRegistering
                            ? 'Registra tu acceso para monitorear tu operación'
                            : 'Inicia sesión para monitorear tu operación',
                        style: const TextStyle(color: Color(0xFF9AA3A6))),
                    const SizedBox(height: 25),
                    if (isRegistering) ...[
                      const Text('Nombre completo',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: nameController,
                          validator: validateName,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              hintText: 'Ej. Ferney Pérez',
                              prefixIcon: Icon(Icons.person_outline))),
                      const SizedBox(height: 17),
                    ],
                    const Text('Correo electrónico',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                        controller: emailController,
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            hintText: 'operador@empresa.com',
                            prefixIcon: Icon(Icons.mail_outline))),
                    const SizedBox(height: 17),
                    const Text('Contraseña',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                        controller: passwordController,
                        validator: validatePassword,
                        obscureText: obscurePassword,
                        textInputAction: isRegistering
                            ? TextInputAction.next
                            : TextInputAction.done,
                        decoration: InputDecoration(
                            hintText: 'Mínimo 8 caracteres',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                                onPressed: () => setState(
                                    () => obscurePassword = !obscurePassword),
                                icon: Icon(obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined)))),
                    if (isRegistering) ...[
                      const SizedBox(height: 7),
                      const Text('Usa mayúscula, minúscula, número y símbolo',
                          style: TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 17),
                      const Text('Confirmar contraseña',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: confirmPasswordController,
                          validator: (value) => value != passwordController.text
                              ? 'Las contraseñas no coinciden'
                              : null,
                          obscureText: obscureConfirmation,
                          decoration: InputDecoration(
                              hintText: 'Repite tu contraseña',
                              prefixIcon: const Icon(Icons.lock_reset_outlined),
                              suffixIcon: IconButton(
                                  onPressed: () => setState(() =>
                                      obscureConfirmation =
                                          !obscureConfirmation),
                                  icon: Icon(obscureConfirmation
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined)))),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                          value: acceptedTerms,
                          onChanged: (value) =>
                              setState(() => acceptedTerms = value ?? false),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppTheme.green,
                          title: const Text('Acepto los términos y condiciones',
                              style: TextStyle(fontSize: 12))),
                    ] else
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: recoverAccount,
                              child: const Text('¿Olvidaste tu contraseña?',
                                  style: TextStyle(color: AppTheme.green)))),
                    const SizedBox(height: 10),
                    FilledButton(
                        onPressed: isLoading ? null : submit,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.green,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : Text(
                                isRegistering
                                    ? 'Crear cuenta'
                                    : 'Iniciar sesión',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                    const SizedBox(height: 19),
                    const Row(children: [
                      Expanded(child: Divider(color: AppTheme.border)),
                      Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('o continúa con',
                              style: TextStyle(color: Colors.grey))),
                      Expanded(child: Divider(color: AppTheme.border))
                    ]),
                    const SizedBox(height: 15),
                    OutlinedButton.icon(
                        onPressed: googleSignIn,
                        icon: const Icon(Icons.g_mobiledata,
                            color: Colors.redAccent, size: 25),
                        label: const Text('Continuar con Google'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppTheme.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 17),
                    Center(
                        child: TextButton(
                            onPressed: toggleMode,
                            child: Text(
                                isRegistering
                                    ? '¿Ya tienes una cuenta?  Iniciar sesión'
                                    : '¿No tienes una cuenta?  Crear cuenta',
                                style:
                                    const TextStyle(color: AppTheme.green)))),
                    const SizedBox(height: 16),
                    const Center(
                        child: Text('PulsoMinero v1.0.0',
                            style: TextStyle(
                                color: Color(0xFF596164), fontSize: 12))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
