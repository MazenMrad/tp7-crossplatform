import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:tp7/models/client.dart';
import 'package:tp7/providers/connectivity_provider.dart';
import 'package:tp7/providers/queue_provider.dart';
import 'package:tp7/repositories/queue_repository.dart';
import 'package:tp7/screens/queue_screen.dart';
import 'package:tp7/services/connectivity_service.dart';
import 'package:tp7/services/geolocation_service.dart';
import 'package:tp7/services/sync_service.dart';
import 'package:tp7/storage/local_queue_storage.dart';
import 'package:tp7/widgets/loading_widget.dart';
import 'package:tp7/widgets/queue_empty_widget.dart';

class MockQueueRepository extends Mock implements QueueRepository {}

class MockGeolocationService extends Mock implements GeolocationService {}

class MockLocalQueueStorage extends Mock implements LocalQueueStorage {}

class MockSyncService extends Mock implements SyncService {}

class MockConnectivityService extends Mock implements ConnectivityService {}

void main() {
  late MockQueueRepository repository;
  late MockGeolocationService geolocation;
  late MockLocalQueueStorage storage;
  late MockSyncService syncService;
  late MockConnectivityService connectivityService;
  late ConnectivityProvider connectivityProvider;
  late QueueProvider queueProvider;

  setUpAll(() {
    registerFallbackValue(
      Client(id: 'fallback', name: 'fallback', createdAt: DateTime(2026)),
    );
  });

  setUp(() {
    repository = MockQueueRepository();
    geolocation = MockGeolocationService();
    storage = MockLocalQueueStorage();
    syncService = MockSyncService();
    connectivityService = MockConnectivityService();

    when(() => repository.insertEvents())
        .thenAnswer((_) => const Stream<Client>.empty());
    when(() => geolocation.getCurrentPosition()).thenAnswer((_) async => null);
    when(() => storage.saveClient(any())).thenAnswer((_) async {});
    when(() => syncService.synchronize()).thenAnswer((_) async {});
    when(() => connectivityService.networkChanges)
        .thenAnswer((_) => const Stream<bool>.empty());
    when(() => connectivityService.hasNetwork()).thenAnswer((_) async => true);
    when(() => connectivityService.isSupabaseAvailable())
        .thenAnswer((_) async => true);

    connectivityProvider = ConnectivityProvider(
      connectivityService,
      debounceDuration: const Duration(milliseconds: 20),
    );
    queueProvider = QueueProvider(
      repository,
      geolocation,
      storage,
      syncService,
    );
  });

  Widget buildTestApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectivityProvider>.value(
          value: connectivityProvider,
        ),
        ChangeNotifierProvider<QueueProvider>.value(value: queueProvider),
      ],
      child: const MaterialApp(home: QueueScreen()),
    );
  }

  testWidgets('shows the loading state before the queue is fetched',
      (tester) async {
    when(() => repository.fetchPage(offset: 0, limit: 20))
        .thenAnswer((_) => Completer<List<Client>>().future);

    await tester.pumpWidget(buildTestApp());

    expect(find.byType(LoadingWidget), findsOneWidget);
    expect(find.text('Loading the waiting queue...'), findsOneWidget);
  });

  testWidgets('shows the empty state when no clients are registered',
      (tester) async {
    when(() => repository.fetchPage(offset: 0, limit: 20))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byType(QueueEmptyWidget), findsOneWidget);
    expect(find.text('The waiting queue is empty'), findsOneWidget);
  });

  testWidgets('shows the connectivity banner while checking', (tester) async {
    when(() => repository.fetchPage(offset: 0, limit: 20))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.text('Checking connection...'), findsOneWidget);
  });

  testWidgets('shows the error state and recovers with Retry', (tester) async {
    var fail = true;
    when(() => repository.fetchPage(offset: 0, limit: 20))
        .thenAnswer((_) async {
      if (fail) throw Exception('boom');
      return [];
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.text('Failed to load queue'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(QueueEmptyWidget), findsOneWidget);
  });

  testWidgets('registering a client adds it to the queue', (tester) async {
    when(() => repository.fetchPage(offset: 0, limit: 20))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.person_add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Alice');
    await tester.tap(find.text('Join queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Location not captured'), findsOneWidget);
    verify(() => storage.saveClient(any())).called(1);
    verify(() => syncService.synchronize()).called(1);
  });

  testWidgets('does not register when the name is empty', (tester) async {
    when(() => repository.fetchPage(offset: 0, limit: 20))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.person_add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join queue'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your name'), findsOneWidget);
    verifyNever(() => storage.saveClient(any()));
    verifyNever(() => syncService.synchronize());
  });
}
