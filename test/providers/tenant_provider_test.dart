import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tp7/models/tenant.dart';
import 'package:tp7/providers/tenant_provider.dart';
import 'package:tp7/services/tenant_service.dart';

class MockTenantService extends Mock implements TenantService {}

Tenant tenant(String id, String name) => Tenant(
      id: id,
      name: name,
      role: 'owner',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockTenantService service;
  late TenantProvider provider;
  late List<Tenant> remote;

  setUp(() {
    service = MockTenantService();
    remote = [tenant('t1', 'Alpha'), tenant('t2', 'Beta')];
    when(() => service.fetchTenants()).thenAnswer((_) async => remote);
    when(() => service.createTenant(any())).thenAnswer((_) async => 't3');
    provider = TenantProvider(service);
  });

  tearDown(() => provider.dispose());

  test('loads the workspaces of a user and selects the first one', () async {
    await provider.loadForUser('u1');

    expect(provider.tenants, hasLength(2));
    expect(provider.activeTenant, equals(tenant('t1', 'Alpha')));
    expect(provider.currentUserId, equals('u1'));
    expect(provider.isLoading, isFalse);
  });

  test('does not reload the same user twice', () async {
    await provider.loadForUser('u1');
    await provider.loadForUser('u1');

    verify(() => service.fetchTenants()).called(1);
  });

  test('switches the active workspace', () async {
    await provider.loadForUser('u1');

    provider.selectTenant('t2');

    expect(provider.activeTenant, equals(tenant('t2', 'Beta')));
  });

  test('ignores unknown workspace ids', () async {
    await provider.loadForUser('u1');

    provider.selectTenant('missing');

    expect(provider.activeTenant?.id, equals('t1'));
  });

  test('creates a workspace and makes it active', () async {
    await provider.loadForUser('u1');
    remote = [...remote, tenant('t3', 'Gamma')];

    final created = await provider.createTenant('Gamma');

    expect(created, isTrue);
    expect(provider.activeTenant?.id, equals('t3'));
    expect(provider.tenants, hasLength(3));
    verify(() => service.createTenant('Gamma')).called(1);
  });

  test('handles load failures', () async {
    when(() => service.fetchTenants()).thenThrow(Exception('offline'));

    await provider.loadForUser('u1');

    expect(provider.errorMessage, equals('Could not load workspaces'));
    expect(provider.tenants, isEmpty);
    expect(provider.activeTenant, isNull);
  });

  test('clear removes all user-specific state', () async {
    await provider.loadForUser('u1');

    provider.clear();

    expect(provider.tenants, isEmpty);
    expect(provider.activeTenant, isNull);
    expect(provider.currentUserId, isNull);
  });
}
