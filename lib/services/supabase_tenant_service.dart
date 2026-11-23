import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tenant.dart';
import 'tenant_service.dart';

class SupabaseTenantService implements TenantService {
  final SupabaseClient _client;

  SupabaseTenantService(this._client);

  @override
  Future<List<Tenant>> fetchTenants() async {
    final rows = await _client.rpc('list_my_tenants');
    return (rows as List)
        .map(
          (row) => Tenant.fromSupabaseMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<String> createTenant(String name) async {
    final id = await _client.rpc(
      'create_tenant',
      params: {'p_name': name},
    );
    return id.toString();
  }
}
