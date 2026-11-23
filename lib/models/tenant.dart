class Tenant {
  final String id;
  final String name;
  final String role;
  final DateTime createdAt;

  const Tenant({
    required this.id,
    required this.name,
    this.role = 'member',
    required this.createdAt,
  });

  bool get canManage => role == 'owner' || role == 'admin';

  factory Tenant.fromSupabaseMap(Map<String, dynamic> map) {
    return Tenant(
      id: map['id'].toString(),
      name: map['name'] as String,
      role: (map['role'] as String?) ?? 'member',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Tenant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
