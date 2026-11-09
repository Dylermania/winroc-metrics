import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import 'database.dart';

const protectedTables = {
  'attendance_records',
  'payments',
  'member_dues',
  'payment_allocations',
  'fines',
};

class RemoteChange {
  final int cursor;
  final String deviceId;
  final String tableName;
  final String recordId;
  final SyncOp op;
  final Map<String, dynamic>? payload;
  final String changedAt;

  RemoteChange(this.cursor, this.deviceId, this.tableName, this.recordId, this.op,
      this.payload, this.changedAt);

  Map<String, dynamic> toJson() => {
        'cursor': cursor,
        'deviceId': deviceId,
        'table': tableName,
        'recordId': recordId,
        'op': op.name,
        'payload': payload,
        'changedAt': changedAt,
      };

  static RemoteChange fromJson(Map<String, dynamic> j) => RemoteChange(
        (j['cursor'] as num).toInt(),
        j['deviceId'] as String,
        j['table'] as String,
        j['recordId'] as String,
        SyncOp.values.firstWhere((o) => o.name == j['op']),
        j['payload'] == null
            ? null
            : (j['payload'] is String
                ? jsonDecode(j['payload'] as String) as Map<String, dynamic>
                : j['payload'] as Map<String, dynamic>),
        j['changedAt'] as String,
      );
}

class SyncResult {
  final int pulled;
  final int pushed;
  final int conflicts;
  SyncResult(this.pulled, this.pushed, this.conflicts);
}

class SyncService {
  final AppDatabase db;
  HttpServer? _server;
  SyncService(this.db);

  bool get hosting => _server != null;

  Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    return interfaces
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .toList();
  }

  Future<void> startHost() async {
    if (_server != null) return;
    final deviceName = await db.setting('device_name', fallback: Platform.localHostname);
    _server = await HttpServer.bind(InternetAddress.anyIPv4, Defaults.syncPort);
    _server!.listen((req) async {
      try {
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/info') {
          req.response.write(jsonEncode({
            'deviceId': db.deviceId,
            'name': deviceName,
            'app': 'winroc_metrics',
          }));
        } else if (req.uri.path == '/changes' && req.method == 'GET') {
          final after = int.tryParse(req.uri.queryParameters['after'] ?? '0') ?? 0;
          final rows = await db.customSelect(
            'SELECT rowid AS cursor, * FROM change_logs WHERE rowid > ? AND device_id = ? ORDER BY rowid LIMIT 500',
            variables: [Variable.withInt(after), Variable.withString(db.deviceId)],
          ).get();
          final out = rows.map((r) {
            final d = Map<String, Object?>.from(r.data);
            final cursor = d.remove('cursor');
            return {
              'cursor': cursor,
              'deviceId': d['device_id'],
              'table': d['table_name'],
              'recordId': d['record_id'],
              'op': (d['op'] as String),
              'payload': d['payload_json'],
              'changedAt': d['changed_at'],
            };
          }).toList();
          req.response.write(jsonEncode(out));
        } else if (req.uri.path == '/changes' && req.method == 'POST') {
          final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
          final changes = (body['changes'] as List)
              .map((c) => RemoteChange.fromJson(c as Map<String, dynamic>))
              .toList();
          var applied = 0;
          var conflicts = 0;
          for (final c in changes) {
            final r = await applyChange(c);
            if (r == _ApplyResult.conflict) {
              conflicts++;
            } else if (r == _ApplyResult.applied) {
              applied++;
            }
          }
          req.response.write(jsonEncode({'applied': applied, 'conflicts': conflicts}));
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
      } catch (e) {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write(jsonEncode({'error': '$e'}));
      } finally {
        await req.response.close();
      }
    });
  }

  Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<SyncResult> syncWith(String address) async {
    final base = 'http://$address:${Defaults.syncPort}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final infoReq = await client.getUrl(Uri.parse('$base/info'));
      final infoRes = await infoReq.close();
      final info = jsonDecode(await utf8.decoder.bind(infoRes).join()) as Map<String, dynamic>;
      if (info['app'] != 'winroc_metrics') {
        throw const FormatException('The other device is not running Winroc Metrics.');
      }
      final peerId = info['deviceId'] as String;
      if (peerId == db.deviceId) {
        throw const FormatException('Cannot sync a device with itself.');
      }
      final peerName = info['name'] as String? ?? 'Device';

      var peer = await (db.select(db.syncPeers)..where((p) => p.peerDeviceId.equals(peerId))).getSingleOrNull();
      final peerRowId = peer?.id ?? newId();
      await db.into(db.syncPeers).insertOnConflictUpdate(SyncPeersCompanion(
          id: Value(peerRowId),
          peerDeviceId: Value(peerId),
          peerName: Value(peerName),
          address: Value(address),
          lastSentCursor: Value(peer?.lastSentCursor ?? 0),
          lastReceivedCursor: Value(peer?.lastReceivedCursor ?? 0),
          createdAt: Value(peer?.createdAt ?? nowIso()),
          updatedAt: Value(nowIso())));
      peer = await (db.select(db.syncPeers)..where((p) => p.id.equals(peerRowId))).getSingle();

      final pullReq = await client.getUrl(Uri.parse('$base/changes?after=${peer.lastReceivedCursor}'));
      final pullRes = await pullReq.close();
      final pulled = (jsonDecode(await utf8.decoder.bind(pullRes).join()) as List)
          .map((c) => RemoteChange.fromJson(c as Map<String, dynamic>))
          .toList();
      var conflicts = 0;
      var maxCursor = peer.lastReceivedCursor;
      for (final c in pulled) {
        final r = await applyChange(c);
        if (r == _ApplyResult.conflict) conflicts++;
        if (c.cursor > maxCursor) maxCursor = c.cursor;
      }

      final localRows = await db.customSelect(
        'SELECT rowid AS cursor, * FROM change_logs WHERE rowid > ? ORDER BY rowid LIMIT 2000',
        variables: [Variable.withInt(peer.lastSentCursor)],
      ).get();
      final toPush = localRows.map((r) {
        final d = Map<String, Object?>.from(r.data);
        final cursor = d.remove('cursor') as int;
        return RemoteChange(
          cursor,
          d['device_id'] as String,
          d['table_name'] as String,
          d['record_id'] as String,
          SyncOp.values.firstWhere((o) => o.name == d['op']),
          d['payload_json'] == null ? null : jsonDecode(d['payload_json'] as String) as Map<String, dynamic>,
          d['changed_at'] as String,
        ).toJson();
      }).toList();
      final pushReq = await client.postUrl(Uri.parse('$base/changes'));
      pushReq.headers.contentType = ContentType.json;
      pushReq.write(jsonEncode({'deviceId': db.deviceId, 'changes': toPush}));
      final pushRes = await pushReq.close();
      final pushResult = jsonDecode(await utf8.decoder.bind(pushRes).join()) as Map<String, dynamic>;
      conflicts += (pushResult['conflicts'] as num?)?.toInt() ?? 0;
      final maxSent = toPush.isEmpty
          ? peer.lastSentCursor
          : toPush.map((c) => c['cursor'] as int).reduce((a, b) => a > b ? a : b);

      await (db.update(db.syncPeers)..where((p) => p.id.equals(peerRowId))).write(SyncPeersCompanion(
          lastReceivedCursor: Value(maxCursor),
          lastSentCursor: Value(maxSent),
          lastSyncAt: Value(nowIso()),
          updatedAt: Value(nowIso())));
      await db.audit('sync', 'sync_peers', peerRowId,
          after: '${pulled.length} pulled, ${toPush.length} pushed');
      return SyncResult(pulled.length, toPush.length, conflicts);
    } finally {
      client.close(force: true);
    }
  }

  Future<_ApplyResult> applyChange(RemoteChange c) async {
    if (c.deviceId == db.deviceId) return _ApplyResult.skipped;
    if (!db.tableNames.contains(c.tableName)) return _ApplyResult.skipped;
    final local = await db.rawRow(c.tableName, c.recordId);

    if (c.op == SyncOp.delete) {
      if (local == null) return _ApplyResult.skipped;
      final localUpdated = (local['updated_at'] as String?) ?? '';
      if (localUpdated.compareTo(c.changedAt) > 0) {
        if (protectedTables.contains(c.tableName)) {
          await _addConflict(c, local);
          return _ApplyResult.conflict;
        }
        return _ApplyResult.skipped;
      }
      await _rawDelete(c.tableName, c.recordId);
      return _ApplyResult.applied;
    }

    final payload = c.payload;
    if (payload == null || payload['id'] != c.recordId) return _ApplyResult.skipped;
    if (local != null) {
      final localUpdated = (local['updated_at'] as String?) ?? '';
      final remoteUpdated = (payload['updated_at'] as String?) ?? c.changedAt;
      if (localUpdated == remoteUpdated) return _ApplyResult.skipped;
      if (localUpdated.compareTo(remoteUpdated) > 0) {
        if (protectedTables.contains(c.tableName)) {
          await _addConflict(c, local);
          return _ApplyResult.conflict;
        }
        return _ApplyResult.skipped;
      }
    }
    await _rawUpsert(c.tableName, payload);
    return _ApplyResult.applied;
  }

  Future<void> _addConflict(RemoteChange c, Map<String, Object?> local) async {
    final existing = await (db.select(db.syncConflicts)
          ..where((x) =>
              x.targetTable.equals(c.tableName) &
              x.recordId.equals(c.recordId) &
              x.resolution.equalsValue(ConflictResolution.pending)))
        .getSingleOrNull();
    if (existing != null) return;
    await db.into(db.syncConflicts).insert(SyncConflictsCompanion.insert(
        id: newId(),
        targetTable: c.tableName,
        recordId: c.recordId,
        localJson: jsonEncode(local),
        remoteJson: jsonEncode(c.payload),
        createdAt: nowIso(),
        updatedAt: nowIso()));
  }

  Set<String> _columns(String table) {
    final info = db.allTables.firstWhere((t) => t.actualTableName == table);
    return info.$columns.map((c) => c.name).toSet();
  }

  Future<void> _rawUpsert(String table, Map<String, dynamic> payload) async {
    final cols = _columns(table);
    final entries = payload.entries.where((e) => cols.contains(e.key)).toList();
    if (entries.isEmpty) return;
    final names = entries.map((e) => '"${e.key}"').join(', ');
    final placeholders = List.filled(entries.length, '?').join(', ');
    final updates = entries.map((e) => '"${e.key}" = excluded."${e.key}"').join(', ');
    await db.customStatement(
      'INSERT INTO "$table" ($names) VALUES ($placeholders) ON CONFLICT(id) DO UPDATE SET $updates',
      entries.map((e) => e.value).toList(),
    );
  }

  Future<void> _rawDelete(String table, String id) async {
    final cols = _columns(table);
    if (cols.contains('deleted_at')) {
      await db.customStatement(
        'UPDATE "$table" SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [nowIso(), nowIso(), id],
      );
    } else {
      await db.customStatement('DELETE FROM "$table" WHERE id = ?', [id]);
    }
  }

  Stream<List<SyncConflict>> watchConflicts() =>
      (db.select(db.syncConflicts)
            ..where((c) => c.resolution.equalsValue(ConflictResolution.pending))
            ..orderBy([(c) => OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)]))
          .watch();

  Future<void> resolveConflict(String id, bool useRemote) async {
    final conflict = await (db.select(db.syncConflicts)..where((c) => c.id.equals(id))).getSingle();
    if (useRemote) {
      final payload = jsonDecode(conflict.remoteJson) as Map<String, dynamic>;
      await _rawUpsert(conflict.targetTable, payload);
    }
    await (db.update(db.syncConflicts)..where((c) => c.id.equals(id))).write(SyncConflictsCompanion(
        resolution: Value(useRemote ? ConflictResolution.remote : ConflictResolution.local),
        resolvedBy: Value(db.currentUserId),
        resolvedAt: Value(nowIso()),
        updatedAt: Value(nowIso())));
    await db.audit('resolve_conflict', 'sync_conflicts', id,
        after: useRemote ? 'remote' : 'local');
  }

  Stream<List<SyncPeer>> watchPeers() =>
      (db.select(db.syncPeers)..where((p) => p.deletedAt.isNull())).watch();
}

enum _ApplyResult { applied, skipped, conflict }