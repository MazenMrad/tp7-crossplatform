import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tp7/models/client.dart';
import 'package:tp7/models/queue_state.dart';
import 'package:tp7/models/sync_status.dart';
import 'package:tp7/providers/queue_provider.dart';
import 'package:tp7/repositories/queue_repository.dart';
import 'package:tp7/services/geolocation_service.dart';
import 'package:tp7/services/sync_service.dart';
import 'package:tp7/storage/local_queue_storage.dart';

class MockQueueRepository extends Mock implements QueueRepository {}

class MockGeolocationService extends Mock implements GeolocationService {}

class MockLocalQueueStorage extends Mock implements LocalQueueStorage {}

class MockSyncService extends Mock implements SyncService {}

Client client(String id) => Client(
      id: id,
      name: 'Client $id',
      createdAt: DateTime(2026, 1, 1).subtract(
        Duration(minutes: int.parse(id.substring(1))),
      ),
    );

List<Client> generateClients(int start, int count) =>
    List.generate(count, (i) => client('c${start + i}'));

void main() {
  late MockQueueRepository repository;
  late MockGeolocationService geolocation;
  late MockLocalQueueStorage storage;
  late MockSyncService syncService;
  late QueueProvider provider;

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

    when(() => repository.insertEvents())
        .thenAnswer((_) => const Stream<Client>.empty());
    when(() => geolocation.getCurrentPosition()).thenAnswer((_) async => null);
    when(() => storage.saveClient(any())).thenAnswer((_) async {});
    when(() => syncService.synchronize()).thenAnswer((_) async {});

    provider = QueueProvider(repository, geolocation, storage, syncService);
    addTearDown(provider.dispose);
  });

  group('fetchInitialQueue', () {
    test('loads clients and reaches loaded state', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenAnswer((_) async => generateClients(0, 2));

      await provider.fetchInitialQueue();

      expect(provider.state, equals(QueueState.loaded));
      expect(provider.clients.length, equals(2));
      expect(provider.hasMore, isFalse);
    });

    test('reaches empty state when the queue is empty', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenAnswer((_) async => []);

      await provider.fetchInitialQueue();

      expect(provider.state, equals(QueueState.empty));
      expect(provider.clients, isEmpty);
    });

    test('reaches error state when the repository fails', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenThrow(Exception('boom'));

      await provider.fetchInitialQueue();

      expect(provider.state, equals(QueueState.error));
      expect(provider.errorMessage, equals('Failed to load queue'));
    });

    test('keeps hasMore true when a full page is returned', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenAnswer((_) async => generateClients(0, 20));

      await provider.fetchInitialQueue();

      expect(provider.clients.length, equals(20));
      expect(provider.hasMore, isTrue);
    });
  });

  group('loadMore', () {
    test('appends only clients that are not already displayed', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenAnswer((_) async => generateClients(0, 20));
      await provider.fetchInitialQueue();

      when(() => repository.fetchPage(offset: 20, limit: 20))
          .thenAnswer((_) async => [client('c19'), client('c20')]);

      await provider.loadMore();

      expect(provider.clients.length, equals(21));
      expect(provider.clients.map((c) => c.id), contains('c20'));
      expect(provider.hasMore, isFalse);
      verify(() => repository.fetchPage(offset: 20, limit: 20)).called(1);
    });

    test('does nothing when there is nothing left to load', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenAnswer((_) async => []);
      await provider.fetchInitialQueue();

      await provider.loadMore();

      verifyNever(() => repository.fetchPage(offset: 20, limit: 20));
    });
  });

  group('realtime inserts', () {
    test('inserts a new client at the top and recovers from empty state',
        () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenAnswer((_) async => []);
      await provider.fetchInitialQueue();
      expect(provider.state, equals(QueueState.empty));

      provider.handleRealtimeInsert(client('c1'));

      expect(provider.state, equals(QueueState.loaded));
      expect(provider.clients.first.id, equals('c1'));
    });

    test('ignores duplicate realtime inserts', () {
      final sameClient = client('c1');
      provider.handleRealtimeInsert(sameClient);
      provider.handleRealtimeInsert(sameClient);

      expect(provider.clients.length, equals(1));
    });

    test('subscribeToRealtime forwards repository inserts', () async {
      final controller = StreamController<Client>.broadcast();
      when(() => repository.insertEvents())
          .thenAnswer((_) => controller.stream);

      provider.subscribeToRealtime();
      controller.add(client('c9'));
      await Future<void>.delayed(Duration.zero);

      expect(provider.clients.first.id, equals('c9'));
      await controller.close();
    });
  });

  group('registerClient', () {
    test('saves locally as pending then triggers synchronization', () async {
      await provider.registerClient('Alice');

      final captured =
          verify(() => storage.saveClient(captureAny<Map<String, dynamic>>()))
              .captured
              .single;
      expect(captured['name'], equals('Alice'));
      expect(captured['sync_status'], equals('pending'));

      expect(provider.state, equals(QueueState.loaded));
      expect(provider.clients.first.name, equals('Alice'));
      expect(provider.clients.first.syncStatus, equals(SyncStatus.pending));
      expect(provider.clients.first.hasLocation, isFalse);

      verify(() => syncService.synchronize()).called(1);
    });

    test('keeps registration working when geolocation fails', () async {
      when(() => geolocation.getCurrentPosition()).thenThrow(Exception('gps'));

      await provider.registerClient('Bob');

      expect(provider.clients.first.name, equals('Bob'));
      expect(provider.clients.first.hasLocation, isFalse);
      verify(() => storage.saveClient(any())).called(1);
    });

    test('recovers the queue from error state after registration', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenThrow(Exception('boom'));
      await provider.fetchInitialQueue();
      expect(provider.state, equals(QueueState.error));

      await provider.registerClient('Alice');

      expect(provider.state, equals(QueueState.loaded));
    });
  });

  group('tenant context', () {
    test('scopes fetch, realtime, local records and sync to the workspace',
        () async {
      when(
        () => repository.fetchPage(offset: 0, limit: 20, tenantId: 't1'),
      ).thenAnswer((_) async => []);
      when(
        () => repository.insertEvents(tenantId: 't1'),
      ).thenAnswer((_) => const Stream<Client>.empty());
      when(
        () => syncService.synchronize(ownerId: 'u1', tenantId: 't1'),
      ).thenAnswer((_) async {});

      provider.setContext(ownerId: 'u1', tenantId: 't1');
      await provider.fetchInitialQueue();
      provider.subscribeToRealtime();
      await provider.registerClient('Alice');

      final saved =
          verify(() => storage.saveClient(captureAny<Map<String, dynamic>>()))
              .captured
              .single;
      expect(saved['owner_id'], equals('u1'));
      expect(saved['tenant_id'], equals('t1'));
      expect(provider.clients.first.ownerId, equals('u1'));
      expect(provider.clients.first.tenantId, equals('t1'));
      verify(
        () => repository.fetchPage(offset: 0, limit: 20, tenantId: 't1'),
      ).called(1);
      verify(() => repository.insertEvents(tenantId: 't1')).called(1);
      verify(
        () => syncService.synchronize(ownerId: 'u1', tenantId: 't1'),
      ).called(1);
    });

    test('switching workspace clears the previous queue', () {
      provider.handleRealtimeInsert(client('c1'));

      provider.setContext(ownerId: 'u1', tenantId: 't2');

      expect(provider.clients, isEmpty);
      expect(provider.state, equals(QueueState.initial));
      expect(provider.tenantId, equals('t2'));
    });
  });

  group('syncPending', () {
    test('synchronizes then refreshes the authoritative queue', () async {
      when(() => repository.fetchPage(offset: 0, limit: 20))
          .thenAnswer((_) async => generateClients(0, 1));

      await provider.syncPending();

      verifyInOrder([
        () => syncService.synchronize(),
        () => repository.fetchPage(offset: 0, limit: 20),
      ]);
      expect(provider.state, equals(QueueState.loaded));
    });
  });
}
