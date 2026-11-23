import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client.dart';

/// Thin abstraction over the remote backend so that the repository and the
/// rest of the app remain testable without hitting real Supabase types.
abstract class QueueRemoteDataSource {
  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
    String? tenantId,
  });
  Future<Client> registerOnServer(Client client);
  Stream<Client> insertEvents({String? tenantId});
}

class SupabaseQueueRemoteDataSource implements QueueRemoteDataSource {
  final SupabaseClient _client;

  SupabaseQueueRemoteDataSource(this._client);

  @override
  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
    String? tenantId,
  }) async {
    final query = _client.from('clients').select();
    final filtered = tenantId == null
        ? query
        : query.eq('tenant_id', tenantId);
    final rows = await filtered
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .map(
          (row) => Client.fromSupabaseMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<Client> registerOnServer(Client client) async {
    final params = <String, dynamic>{
      'p_id': client.id,
      'p_name': client.name,
      'p_lat': client.lat,
      'p_lng': client.lng,
      'p_accuracy': client.locationAccuracy,
      'p_created_at': client.createdAt.toIso8601String(),
    };
    if (client.tenantId != null) {
      params['p_tenant_id'] = client.tenantId;
    }
    final result = await _client.rpc(
      'register_queue_client',
      params: params,
    );
    final rows = result as List;
    return Client.fromSupabaseMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Stream<Client> insertEvents({String? tenantId}) {
    final channel = _client.channel('public:clients:${tenantId ?? 'all'}');
    final controller = StreamController<Client>.broadcast(
      onCancel: () async {
        await channel.unsubscribe();
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'clients',
      filter: tenantId == null
          ? null
          : PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
      callback: (payload) {
        final row = payload.newRecord;
        if (row.isNotEmpty) {
          controller.add(
            Client.fromSupabaseMap(Map<String, dynamic>.from(row)),
          );
        }
      },
    ).subscribe();
    return controller.stream;
  }
}

class QueueRepository {
  final QueueRemoteDataSource _remote;

  QueueRepository(this._remote);

  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
    String? tenantId,
  }) {
    return _remote.fetchPage(
      offset: offset,
      limit: limit,
      tenantId: tenantId,
    );
  }

  Future<Client> registerOnServer(Client client) {
    return _remote.registerOnServer(client);
  }

  Stream<Client> insertEvents({String? tenantId}) {
    return _remote.insertEvents(tenantId: tenantId);
  }
}
