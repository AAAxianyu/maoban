import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE cache(account TEXT,space TEXT,value TEXT,PRIMARY KEY(account,space))',
    );
    await db.execute(
      '''CREATE TABLE queue(id TEXT PRIMARY KEY,account TEXT,space TEXT,instance TEXT,desired INTEGER,
      version INTEGER,created TEXT,status TEXT,attempts INTEGER DEFAULT 0,error TEXT DEFAULT '',UNIQUE(account,space,instance))''',
    );
    store = LocalStore(db);
  });
  tearDown(() async => store.db.close());
  test('pending intent merges, preserves UUID, and account isolation survives logout', () async {
    const i = {'id': 'instance', 'version': 3};
    await store.enqueue('a', 'room', i, true);
    final id = (await store.queue('a', 'room')).single['id'];
    await store.enqueue('a', 'room', i, false);
    final pending = (await store.queue('a', 'room')).single;
    expect(pending['id'], id);
    expect(pending['desired'], 0);
    expect(await store.queue('b', 'room'), isEmpty);
    await store.cache('a', 'room', {
      'wallet': {'available': 12},
    });
    await store.logout('a', keepQueue: true);
    expect(await store.read('a', 'room'), isNull);
    expect((await store.queue('a', 'room')).length, 1);
    expect(await store.queue('b', 'room'), isEmpty);
    await store.logout('a', keepQueue: false);
    expect(await store.queue('a', 'room'), isEmpty);
  });
  test(
    'an uncertain sent intent cannot mutate its idempotency payload',
    () async {
      const i = {'id': 'instance', 'version': 0};
      await store.enqueue('a', 'room', i, true);
      final id = (await store.queue('a', 'room')).single['id'] as String;
      await store.update(id, {'attempts': 1});
      expect(
        () => store.enqueue('a', 'room', i, false),
        throwsA(isA<UserMessage>()),
      );
      expect((await store.queue('a', 'room')).single['desired'], 1);
    },
  );
}
