import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tp7/models/app_connectivity.dart';
import 'package:tp7/providers/connectivity_provider.dart';
import 'package:tp7/services/connectivity_service.dart';

class MockConnectivityService extends Mock implements ConnectivityService {}

void main() {
  late MockConnectivityService service;

  setUp(() {
    service = MockConnectivityService();
    when(() => service.networkChanges)
        .thenAnswer((_) => const Stream<bool>.empty());
  });

  ConnectivityProvider buildProvider() {
    final provider = ConnectivityProvider(
      service,
      debounceDuration: const Duration(milliseconds: 20),
    );
    addTearDown(provider.dispose);
    return provider;
  }

  test('starts offline when there is no network', () async {
    when(() => service.hasNetwork()).thenAnswer((_) async => false);
    final provider = buildProvider();

    await provider.initialize();

    expect(provider.status, equals(AppConnectivity.offline));
    expect(provider.isOnline, isFalse);
    verifyNever(() => service.isSupabaseAvailable());
  });

  test('becomes online after debounce when backend is reachable', () async {
    when(() => service.hasNetwork()).thenAnswer((_) async => true);
    when(() => service.isSupabaseAvailable()).thenAnswer((_) async => true);
    final provider = buildProvider();

    await provider.initialize();
    expect(provider.status, equals(AppConnectivity.checking));

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(provider.status, equals(AppConnectivity.online));
  });

  test('reports backendUnavailable when Supabase is unreachable', () async {
    when(() => service.hasNetwork()).thenAnswer((_) async => true);
    when(() => service.isSupabaseAvailable()).thenAnswer((_) async => false);
    final provider = buildProvider();

    await provider.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(provider.status, equals(AppConnectivity.backendUnavailable));
  });

  test('debounces rapid network changes into a single backend check',
      () async {
    final controller = StreamController<bool>.broadcast();
    when(() => service.networkChanges)
        .thenAnswer((_) => controller.stream);
    when(() => service.hasNetwork()).thenAnswer((_) async => true);
    when(() => service.isSupabaseAvailable()).thenAnswer((_) async => true);
    final provider = buildProvider();

    await provider.initialize();
    controller.add(true);
    controller.add(true);
    controller.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(provider.status, equals(AppConnectivity.online));
    verify(() => service.isSupabaseAvailable()).called(1);
    await controller.close();
  });

  test('transitions offline then back online when network returns', () async {
    final controller = StreamController<bool>.broadcast();
    when(() => service.networkChanges)
        .thenAnswer((_) => controller.stream);
    when(() => service.hasNetwork()).thenAnswer((_) async => true);
    when(() => service.isSupabaseAvailable()).thenAnswer((_) async => true);
    final provider = buildProvider();
    await provider.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(provider.status, equals(AppConnectivity.online));

    final transitions = <AppConnectivity>[];
    provider.addListener(() => transitions.add(provider.status));

    controller.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(provider.status, equals(AppConnectivity.offline));

    controller.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(provider.status, equals(AppConnectivity.online));
    expect(transitions, contains(AppConnectivity.offline));
    await controller.close();
  });
}
