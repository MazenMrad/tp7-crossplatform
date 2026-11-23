import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/sync_status.dart';

class LocalQueueStorage {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final path = join(await getDatabasesPath(), 'waiting_queue.db');
    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clients (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL,
            lng REAL,
            location_accuracy_m REAL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL,
            owner_id TEXT,
            tenant_id TEXT
          )
          ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE clients ADD COLUMN owner_id TEXT');
          await db.execute('ALTER TABLE clients ADD COLUMN tenant_id TEXT');
        }
      },
    );
    return _database!;
  }

  Future<void> saveClient(Map<String, dynamic> client) async {
    final db = await database;
    await db.insert(
      'clients',
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getClients({
    String? ownerId,
    String? tenantId,
  }) async {
    final db = await database;
    final where = _scopeWhere(ownerId: ownerId, tenantId: tenantId);
    return db.query(
      'clients',
      where: where['clause'],
      whereArgs: where['args'],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  /// Fetches both 'pending' and 'failed' records for retry logic
  Future<List<Map<String, dynamic>>> getPendingClients({
    String? ownerId,
    String? tenantId,
  }) async {
    final db = await database;
    final scope = _scopeWhere(ownerId: ownerId, tenantId: tenantId);
    final conditions = <String>['(sync_status = ? OR sync_status = ?)'];
    final args = <Object?>['pending', 'failed'];
    final clause = scope['clause'] as String?;
    if (clause != null && clause.isNotEmpty) {
      conditions.add(clause);
      args.addAll(scope['args'] as List<Object?>);
    }
    return db.query(
      'clients',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Map<String, dynamic> _scopeWhere({String? ownerId, String? tenantId}) {
    final conditions = <String>[];
    final args = <Object?>[];
    if (ownerId != null) {
      conditions.add('owner_id = ?');
      args.add(ownerId);
    }
    if (tenantId != null) {
      conditions.add('tenant_id = ?');
      args.add(tenantId);
    }
    return {
      'clause': conditions.join(' AND '),
      'args': args,
    };
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    await db.update(
      'clients',
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
