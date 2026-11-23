import '../storage/local_queue_storage.dart';
import '../repositories/queue_repository.dart';
import '../models/client.dart';
import '../models/sync_status.dart';

class SyncService {
  final LocalQueueStorage _storage;
  final QueueRepository _repository;

  bool _isSyncing = false;

  SyncService(this._storage, this._repository);

  Future<void> synchronize({String? ownerId, String? tenantId}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final pendingRecords = ownerId == null && tenantId == null
          ? await _storage.getPendingClients()
          : await _storage.getPendingClients(
              ownerId: ownerId,
              tenantId: tenantId,
            );
      for (final record in pendingRecords) {
        final id = record['id'] as String;
        try {
          await _storage.updateSyncStatus(id, SyncStatus.syncing);
          final client = Client.fromLocalMap(record);
          // Calls backend RPC / Upsert via Repository
          await _repository.registerOnServer(client);
          await _storage.updateSyncStatus(id, SyncStatus.synced);
        } catch (_) {
          await _storage.updateSyncStatus(id, SyncStatus.failed);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
