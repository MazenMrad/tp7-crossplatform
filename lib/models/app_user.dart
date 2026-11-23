class AppUser {
  final String id;
  final String email;
  final String? displayName;

  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : (email.isNotEmpty ? email : id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}
