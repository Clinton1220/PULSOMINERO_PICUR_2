class UserSession {
  const UserSession({required this.email, this.displayName});

  final String email;
  final String? displayName;

  String get name {
    final value = displayName?.trim();
    if (value != null && value.isNotEmpty) return value;
    final localPart = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    return localPart
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
