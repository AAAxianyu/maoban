import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Backend implements HttpClientAdapter {
  bool offline = false, completed = false, tomorrow = false;
  int writes = 0, reviews = 0;
  int serverVersion = 0;
  final checkinKeys = <String?>[];
  Map<String, dynamic> get snapshot => {
    'space': {'today': tomorrow ? '2026-10-09' : '2026-10-08'},
    'snapshot_seq': writes,
    'wallet': {
      'balance': completed ? 10 : 0,
      'available': completed ? 10 : 0,
      'debt': 0,
    },
    'daily': {
      'instances': tomorrow
          ? <dynamic>[]
          : [
              {
                'id': 'instance',
                'date': '2026-10-08',
                'user_id': 'a',
                'completed': completed,
                'version': serverVersion,
                'points': 10,
              },
            ],
    },
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'test offline',
      );
    }
    if (options.path.endsWith('/snapshot')) return response(snapshot);
    if (options.path.endsWith('/checkin')) {
      checkinKeys.add(options.headers['Idempotency-Key'] as String?);
      if (tomorrow) {
        return response({
          'code': 'DATE_REQUIRES_REVIEW',
          'message': '需要补记确认',
        }, 409);
      }
      if (options.data['expected_version'] != serverVersion) {
        return response({
          'code': 'VERSION_CONFLICT',
          'message': '记录已更新，请查看服务器记录',
        }, 409);
      }
      writes++;
      serverVersion++;
      completed = true;
      return response({
        'instance': snapshot['daily']['instances'][0],
        'wallet': snapshot['wallet'],
      });
    }
    if (options.path.endsWith('/corrections')) {
      reviews++;
      return response({'status': 'pending'});
    }
    throw StateError('Unexpected test request ${options.path}');
  }

  ResponseBody response(dynamic body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
  @override
  void close({bool force = false}) {}
}

class DelayedBackend extends Backend {
  final started = Completer<void>();
  final release = Completer<void>();
  bool loggedOut = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/auth/logout')) {
      loggedOut = true;
      return response(<String, dynamic>{});
    }
    if (options.path.endsWith('/snapshot')) {
      started.complete();
      await release.future;
      return response(snapshot);
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  late LocalStore store;
  late Backend backend;
  AppController controller() {
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'))
      ..httpClientAdapter = backend;
    final api = Api(client: dio)..tokens = {'access_token': 'test-token'};
    return AppController(api, store)
      ..user = {'id': 'a'}
      ..sid = 'room'
      ..snapshot = backend.snapshot;
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
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
    backend = Backend();
  });
  tearDown(() async => store.db.close());
  test('a conflicted offline intent can be discarded before a new UUID uses the current server version', () async {
    final app = controller();
    final stale = Map<String, dynamic>.from(app.instances.single);
    backend.serverVersion = 1;
    await app.checkin(stale, true);
    expect(app.pending.single['status'], 'failed');
    expect(backend.writes, 0);
    final oldId = app.pending.single['id'] as String;
    await app.discardFailedOperation(oldId);
    expect(app.pending, isEmpty);
    expect(app.snapshot!['wallet']['available'], 0);
    await app.checkin(Map<String, dynamic>.from(app.instances.single), true);
    expect(app.pending, isEmpty);
    expect(backend.writes, 1);
    expect(backend.checkinKeys, hasLength(2));
    expect(backend.checkinKeys[0], isNot(backend.checkinKeys[1]));
    expect(app.snapshot!['wallet']['available'], 10);
    app.dispose();
  });
  test(
    'logout waits for an in-flight snapshot and discards its old-account state',
    () async {
      final delayed = DelayedBackend();
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'))
        ..httpClientAdapter = delayed;
      final api = Api(client: dio)..tokens = {'access_token': 'test-token'};
      final app = AppController(api, store)
        ..user = {'id': 'a'}
        ..sid = 'room'
        ..snapshot = delayed.snapshot;
      final sync = app.sync();
      await delayed.started.future;
      final logout = app.logout(keepQueue: true);
      await Future<void>.delayed(Duration.zero);
      expect(delayed.loggedOut, false);
      delayed.release.complete();
      await Future.wait([sync, logout]);
      expect(delayed.loggedOut, true);
      expect(app.user, isNull);
      expect(app.snapshot, isNull);
      expect(api.tokens, isNull);
      expect(await store.db.query('cache'), isEmpty);
      app.dispose();
    },
  );
  test('offline intent survives controller restart without optimistic spending and awards once', () async {
    var app = controller();
    backend.offline = true;
    final i = Map<String, dynamic>.from(app.instances.single);
    await app.checkin(i, true);
    expect(app.pending.length, 1);
    expect(app.snapshot!['wallet']['available'], 0);
    expect(backend.writes, 0);
    app.dispose();
    app = controller();
    backend.offline = false;
    await app.sync();
    expect(app.pending, isEmpty);
    expect(app.snapshot!['wallet']['available'], 10);
    expect(backend.writes, 1);
    await app.checkin(i, true);
    expect(backend.writes, 1);
    app.dispose();
  });
  test(
    'cross-day queue submits review and never grants unapproved points',
    () async {
      final app = controller();
      backend.offline = true;
      await app.checkin(Map<String, dynamic>.from(app.instances.single), true);
      backend.offline = false;
      backend.tomorrow = true;
      await app.sync();
      expect(backend.reviews, 1);
      expect(backend.writes, 0);
      expect(app.pending, isEmpty);
      expect(app.snapshot!['wallet']['available'], 0);
      app.dispose();
    },
  );
}
