import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tp7/models/client.dart';
import 'package:tp7/models/sync_status.dart';
import 'package:tp7/repositories/queue_repository.dart';
import 'package:tp7/services/sync_service.dart';
import 'package:tp7/storage/local_queue_storage.dart';

class MockLocalQueueStorage extends Mock implements LocalQueueStorage {}

class MockQueueRepository extends Mock implements QueueRepository {}

void main() {
  late MockLocalQueueStorage storage;
  late MockQueueRepository repository;
  late SyncService service;

  setUpAll(() {
    registerFallbackValue(
      Client(id: 'fallback', name: 'fallback', createdAt: DateTime(2026)),
    );
    registerFallbackValue(SyncStatus.pending);
  });

  setUp(() {
    storage = MockLocalQueueStorage();
    repository = MockQueueRepository();
    service = SyncService(storage, repository);
  });

  Map<String, dynamic> record(String id, String status) {
    return Client(
      id: id,
      name: 'Client $id',
      createdAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.values.byName(status),
    ).toLocalMap();
  }

  Client serverClient(String id) => Client(
        id: id,
        name: 'Client $id',
        createdAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.synced,
      );

  test('does nothing when there are no pending records', () async {
    when(() => storage.getPendingClients()).thenAnswer((_) async => []);

    await service.synchronize();

    verifyNever(() => repository.registerOnServer(any()));
    verifyNever(() => storage.updateSyncStatus(any(), any()));
  });

  test('syncs a pending record and marks it synced', () async {
    when(() => storage.getPendingClients())
        .thenAnswer((_) async => [record('a', 'pending')]);
    when(() => storage.updateSyncStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.registerOnServer(any()))
        .thenAnswer((_) async => serverClient('a'));

    await service.synchronize();

    verifyInOrder([
      () => storage.updateSyncStatus('a', SyncStatus.syncing),
      () => repository.registerOnServer(any()),
      () => storage.updateSyncStatus('a', SyncStatus.synced),
    ]);
  });

  test('marks record as failed when server registration throws', () async {
    when(() => storage.getPendingClients())
        .thenAnswer((_) async => [record('a', 'pending')]);
    when(() => storage.updateSyncStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.registerOnServer(any())).thenThrow(Exception('boom'));

    await service.synchronize();

    verifyInOrder([
      () => storage.updateSyncStatus('a', SyncStatus.syncing),
      () => storage.updateSyncStatus('a', SyncStatus.failed),
    ]);
    verifyNever(() => storage.updateSyncStatus('a', SyncStatus.synced));
  });

  test('continues with remaining records after a failure', () async {
    when(() => storage.getPendingClients()).thenAnswer(
      (_) async => [record('a', 'pending'), record('b', 'pending')],
    );
    when(() => storage.updateSyncStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.registerOnServer(any()))
        .thenAnswer((invocation) async {
      final client = invocation.positionalArguments.first as Client;
      if (client.id == 'a') throw Exception('boom');
      return serverClient('b');
    });

    await service.synchronize();

    verify(() => storage.updateSyncStatus('a', SyncStatus.failed)).called(1);
    verify(() => storage.updateSyncStatus('b', SyncStatus.synced)).called(1);
  });

  test('retries failed records on the next synchronize call', () async {
    var failFirst = true;
    when(() => storage.getPendingClients())
        .thenAnswer((_) async => [record('a', 'failed')]);
    when(() => storage.updateSyncStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.registerOnServer(any())).thenAnswer((_) async {
      if (failFirst) throw Exception('boom');
      return serverClient('a');
    });

    await service.synchronize();
    verify(() => storage.updateSyncStatus('a', SyncStatus.failed)).called(1);

    failFirst = false;
    await service.synchronize();
    verify(() => storage.updateSyncStatus('a', SyncStatus.synced)).called(1);
  });

  test('ignores concurrent synchronize calls', () async {
    final completer = Completer<Client>();
    when(() => storage.getPendingClients())
        .thenAnswer((_) async => [record('a', 'pending')]);
    when(() => storage.updateSyncStatus(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.registerOnServer(any()))
        .thenAnswer((_) => completer.future);

    final first = service.synchronize();
    await service.synchronize();

    verify(() => storage.getPendingClients()).called(1);

    completer.complete(serverClient('a'));
    await first;
  });
}
