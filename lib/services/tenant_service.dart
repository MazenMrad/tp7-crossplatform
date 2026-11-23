import '../models/tenant.dart';

/// Testable abstraction over tenant membership operations.
abstract class TenantService {
  Future<List<Tenant>> fetchTenants();
  Future<String> createTenant(String name);
}
