import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/client.dart';
import '../models/queue_state.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';
import '../services/geolocation_service.dart';
import '../services/sync_service.dart';
import '../storage/local_queue_storage.dart';

class QueueProvider extends ChangeNotifier {
  final QueueRepository _repository;
  final GeolocationService _geolocationService;
  final LocalQueueStorage _storage;
  final SyncService _syncService;

  final List<Client> _clients = [];
  QueueState _state = QueueState.initial;
  String? _errorMessage;
  int _page = 0;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  StreamSubscription<Client>? _insertSubscription;
  String? _ownerId;
  String? _tenantId;

  QueueProvider(
    this._repository,
    this._geolocationService,
    this._storage,
    this._syncService,
  );

  List<Client> get clients => List.unmodifiable(_clients);
  QueueState get state => _state;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  int get pageSize => _pageSize;
  String? get ownerId => _ownerId;
  String? get tenantId => _tenantId;

  /// Binds the queue to the signed-in user and the selected workspace.
  /// Switching either one discards the previous user's view and subscription.
  void setContext({required String ownerId, required String tenantId}) {
    if (_ownerId == ownerId && _tenantId == tenantId) return;
    _insertSubscription?.cancel();
    _insertSubscription = null;
    _ownerId = ownerId;
    _tenantId = tenantId;
    _clients.clear();
    _state = QueueState.initial;
    _errorMessage = null;
    _page = 0;
    _hasMore = true;
    _isLoadingMore = false;
    notifyListeners();
  }

  Future<List<Client>> _fetchPage({
    required int offset,
    required int limit,
  }) {
    final tenantId = _tenantId;
    return tenantId == null
        ? _repository.fetchPage(offset: offset, limit: limit)
        : _repository.fetchPage(
            offset: offset,
            limit: limit,
            tenantId: tenantId,
          );
  }

  Future<void> fetchInitialQueue() async {
    _state = QueueState.loading;
    _page = 0;
    _hasMore = true;
    notifyListeners();
    try {
      final data = await _fetchPage(offset: 0, limit: _pageSize);
      _clients.clear();
      _clients.addAll(data);
      _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
      if (data.length < _pageSize) _hasMore = false;
    } catch (e) {
      debugPrint('fetchInitialQueue failed: $e');
      _errorMessage = 'Failed to load queue';
      _state = QueueState.error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      _page++;
      final newClients = await _fetchPage(
        offset: _page * _pageSize,
        limit: _pageSize,
      );
      final existingIds = _clients.map((c) => c.id).toSet();
      final uniqueNewClients =
          newClients.where((c) => !existingIds.contains(c.id));
      _clients.addAll(uniqueNewClients);
      if (newClients.length < _pageSize) _hasMore = false;
    } catch (_) {
      _page--;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void handleRealtimeInsert(Client client) {
    final exists = _clients.any((c) => c.id == client.id);
    if (!exists) {
      _clients.insert(0, client);
      if (_state == QueueState.empty) _state = QueueState.loaded;
      notifyListeners();
    }
  }

  /// Registers the client locally first, then attempts to synchronize.
  /// Geolocation is optional: registration never fails because of GPS.
  Future<Client> registerClient(String name) async {
    Position? position;
    try {
      position = await _geolocationService.getCurrentPosition();
    } catch (_) {
      // GPS is optional and must never block a registration.
    }
    final client = Client(
      id: const Uuid().v4(),
      name: name,
      lat: position?.latitude,
      lng: position?.longitude,
      locationAccuracy: position?.accuracy,
      createdAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
      ownerId: _ownerId,
      tenantId: _tenantId,
    );

    await _storage.saveClient(client.toLocalMap());

    _clients.insert(0, client);
    if (_state == QueueState.empty ||
        _state == QueueState.initial ||
        _state == QueueState.error) {
      _state = QueueState.loaded;
    }
    notifyListeners();

    await _synchronize();
    return client;
  }

  Future<void> _synchronize() async {
    final ownerId = _ownerId;
    final tenantId = _tenantId;
    if (ownerId == null || tenantId == null) {
      await _syncService.synchronize();
      return;
    }
    await _syncService.synchronize(ownerId: ownerId, tenantId: tenantId);
  }

  /// Retries pending/failed local registrations then refreshes the
  /// authoritative queue from Supabase.
  Future<void> syncPending() async {
    await _synchronize();
    await fetchInitialQueue();
  }

  void subscribeToRealtime() {
    if (_insertSubscription != null) return;
    final tenantId = _tenantId;
    final stream = tenantId == null
        ? _repository.insertEvents()
        : _repository.insertEvents(tenantId: tenantId);
    _insertSubscription = stream.listen(handleRealtimeInsert);
  }

  @override
  void dispose() {
    _insertSubscription?.cancel();
    super.dispose();
  }
}
