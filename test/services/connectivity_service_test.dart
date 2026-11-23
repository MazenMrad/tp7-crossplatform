import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tp7/services/connectivity_service.dart';

class MockConnectivity extends Mock implements Connectivity {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late MockConnectivity connectivity;
  late MockSupabaseClient supabase;
  late ConnectivityService service;

  setUp(() {
    connectivity = MockConnectivity();
    supabase = MockSupabaseClient();
    service = ConnectivityService(supabase, connectivity: connectivity);
  });

  test('hasNetwork returns true when a network is available', () async {
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);

    expect(await service.hasNetwork(), isTrue);
  });

  test('hasNetwork returns false when there is no connection', () async {
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.none]);

    expect(await service.hasNetwork(), isFalse);
  });

  test('networkChanges maps results to a single boolean', () async {
    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => controller.stream);

    expectLater(
      service.networkChanges,
      emitsInOrder([isTrue, isFalse, isTrue]),
    );

    controller.add([ConnectivityResult.wifi]);
    controller.add([ConnectivityResult.none]);
    controller.add([ConnectivityResult.mobile]);
    await controller.close();
  });

  test('isSupabaseAvailable returns false when the request fails', () async {
    when(() => supabase.from(any())).thenThrow(Exception('backend down'));

    expect(await service.isSupabaseAvailable(), isFalse);
  });
}
