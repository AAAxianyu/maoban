import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:miaoban/features/notifications/notification_service.dart';
import 'package:miaoban/main.dart';
import 'package:sqflite/sqflite.dart';

class _Database implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends Api {
  final reads = <String>[], writes = <String>[];
  @override
  Future<dynamic> get(String path) async {
    reads.add(path);
    if (path == '/notifications/n') {
      return {
        'space_id': 'room',
        'event': {'type': 'checkin.completed'},
      };
    }
    if (path.endsWith('/events?after_seq=0')) return [];
    throw StateError('Unexpected $path');
  }

  @override
  Future<dynamic> post(String path, [dynamic body, String? key]) async {
    writes.add(path);
    return {};
  }

  @override
  Future<List<dynamic>> all(String path) async => [];
}

class _App extends AppController {
  _App(_Api api) : super(api, LocalStore(_Database()));
  @override
  Future<void> sync() async {}
}

class _Notifications extends NotificationService {
  @override
  Future<void> register(AppController app) async {}
  @override
  Future<void> schedule(AppController app) async {}
}

Map<String, dynamic> snapshot() => {
  'snapshot_seq': 0,
  'space': {
    'today': '2026-10-08',
    'space': {'name': 'Test'},
    'members': [
      {'id': 'alice', 'nickname': 'Alice'},
      {'id': 'bob', 'nickname': 'Bob'},
    ],
  },
  'wallet': {'available': 0},
  'daily': {'plans': <dynamic>[], 'instances': <dynamic>[]},
  'rewards': <dynamic>[],
  'growth': {
    'level': 1,
    'permanent_xp': 0,
    'decorations': <dynamic>[],
    'stats': <String, dynamic>{},
    'calendar': <dynamic>[],
    'achievements': <dynamic>[],
    'achievement_definitions': <String, dynamic>{},
  },
};
void main() {
  late _Api api;
  late _App app;
  late _Notifications notifications;
  setUp(() {
    api = _Api();
    app = _App(api)
      ..user = {
        'id': 'alice',
        'nickname': 'Alice',
        'preferences': {'reduce_motion': true},
      }
      ..sid = 'room'
      ..snapshot = snapshot();
    notifications = _Notifications();
  });
  tearDown(() {
    app.dispose();
  });
  testWidgets(
    'cold remote tap checks the authorized inbox ID before marking read and routing',
    (tester) async {
      notifications.initialTaps.add({
        'space_id': 'room',
        'notification_id': 'n',
      });
      await tester.pumpWidget(MiaobanApp(app, notifications));
      app.changed();
      await tester.pumpAndSettle();
      expect(api.reads.first, '/notifications/n');
      expect(api.writes, ['/notifications/n/read']);
      expect(find.text('彼此的动态'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'local tap for an earlier account is ignored even in the same space',
    (tester) async {
      notifications.initialTaps.add({
        'space_id': 'room',
        'account_id': 'bob',
        'task_id': 'task',
      });
      await tester.pumpWidget(MiaobanApp(app, notifications));
      app.changed();
      await tester.pumpAndSettle();
      expect(api.reads, isEmpty);
      expect(api.writes, isEmpty);
      expect(find.text('喵伴 · 今日'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('a current local reminder opens today from another tab', (
    tester,
  ) async {
    await tester.pumpWidget(MiaobanApp(app, notifications));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小屋'));
    await tester.pumpAndSettle();
    expect(find.text('我们的小屋'), findsOneWidget);
    notifications.taps.add({
      'space_id': 'room',
      'account_id': 'alice',
      'task_id': 'task',
    });
    await tester.pumpAndSettle();
    expect(find.text('喵伴 · 今日'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
