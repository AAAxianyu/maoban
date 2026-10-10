import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';

class LocalStore {
  final Database db;
  LocalStore(this.db);
  static Future<LocalStore> open() async => LocalStore(
    await openDatabase(
      path.join(await getDatabasesPath(), 'miaoban.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE cache(account TEXT, space TEXT, value TEXT, PRIMARY KEY(account,space))',
        );
        await db.execute('''CREATE TABLE queue(id TEXT PRIMARY KEY, account TEXT NOT NULL, space TEXT NOT NULL,
        instance TEXT NOT NULL, desired INTEGER NOT NULL, version INTEGER NOT NULL, created TEXT NOT NULL,
        status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, error TEXT NOT NULL DEFAULT '',
        UNIQUE(account,space,instance))''');
      },
    ),
  );
  Future<void> cache(
    String account,
    String space,
    Map<String, dynamic> value,
  ) => db.insert('cache', {
    'account': account,
    'space': space,
    'value': jsonEncode(value),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<Map<String, dynamic>?> read(String account, String space) async {
    final rows = await db.query(
      'cache',
      where: 'account=? AND space=?',
      whereArgs: [account, space],
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(rows.first['value'] as String) as Map,
          );
  }

  Future<List<Map<String, Object?>>> queue(String account, String space) =>
      db.query(
        'queue',
        where: 'account=? AND space=?',
        whereArgs: [account, space],
        orderBy: 'created',
      );
  Future<void> enqueue(
    String account,
    String space,
    Map<String, dynamic> instance,
    bool desired,
  ) async {
    await db.transaction((tx) async {
      final prior = await tx.query(
        'queue',
        where: 'account=? AND space=? AND instance=?',
        whereArgs: [account, space, instance['id']],
      );
      if (prior.isNotEmpty && (prior.first['attempts'] as int) > 0) {
        throw const UserMessage('该操作可能已提交，请先同步后再更改');
      }
      await tx.insert('queue', {
        'id': prior.isEmpty ? const Uuid().v4() : prior.first['id'],
        'account': account,
        'space': space,
        'instance': instance['id'],
        'desired': desired ? 1 : 0,
        'version': instance['version'],
        'created': DateTime.now().toUtc().toIso8601String(),
        'status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> remove(String id) async =>
      db.delete('queue', where: 'id=?', whereArgs: [id]);
  Future<void> update(String id, Map<String, Object?> values) async =>
      db.update('queue', values, where: 'id=?', whereArgs: [id]);
  Future<void> logout(String account, {required bool keepQueue}) async {
    await db.delete('cache', where: 'account=?', whereArgs: [account]);
    if (!keepQueue) {
      await db.delete('queue', where: 'account=?', whereArgs: [account]);
    }
  }
}
