import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:miaoban/features/notifications/notification_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_plan_test.dart' as fixture;

class _Database implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends Api {
  int reads = 0;
  bool offline = false;
  Completer<List<dynamic>>? delayed;
  @override
  Future<List<dynamic>> all(String path) async {
    reads++;
    if (delayed != null) return delayed!.future;
    if (offline) throw const ApiFailure('NETWORK', 'offline', null);
    return [fixture.record(), fixture.record(account: 'bob')];
  }
}

class _Plugin implements FlutterLocalNotificationsPlugin {
  final scheduled = <Map<String, dynamic>>[];
  final canceled = <int>[];
  final pending = <PendingNotificationRequest>[
    PendingNotificationRequest(
      1,
      'old',
      '',
      jsonEncode({'task_id': 'task', 'space_id': 'old'}),
    ),
    PendingNotificationRequest(
      999,
      'partner',
      '',
      jsonEncode({'notification_id': 'inbox-id'}),
    ),
  ];
  int cancelAllCount = 0;
  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => pending;
  @override
  Future<void> cancel({required int id, String? tag}) async {
    canceled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    scheduled.clear();
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduled.add({
      'id': id,
      'body': body,
      'at': scheduledDate,
      'payload': jsonDecode(payload!),
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  data.initializeTimeZones();
  late _Api api;
  late _Plugin plugin;
  late AppController app;
  late NotificationService service;
  var now = DateTime.utc(2026, 10, 8, 9);
  setUp(() {
    now = DateTime.utc(2026, 10, 8, 9);
    api = _Api();
    plugin = _Plugin();
    app = AppController(api, LocalStore(_Database()))
      ..user = {'id': 'alice', 'preferences': <String, dynamic>{}}
      ..sid = 'room'
      ..snapshot = fixture.snapshot();
    service = NotificationService(plugin: plugin, clock: () => now)
      ..allowed = true;
  });
  tearDown(() {
    app.dispose();
  });
  test(
    'same sequence still updates after civil midnight or another account',
    () async {
      await service.schedule(app);
      expect(api.reads, 1);
      await service.schedule(app);
      expect(api.reads, 1);
      now = DateTime.utc(2026, 10, 9, 9);
      await service.schedule(app);
      expect(api.reads, 2);
      app.user = {'id': 'bob', 'preferences': <String, dynamic>{}};
      await service.schedule(app);
      expect(api.reads, 3);
      expect(plugin.scheduled.last['payload']['account_id'], 'bob');
      expect(plugin.cancelAllCount, 0);
      expect(
        plugin.canceled,
        everyElement(1),
      ); // Partner notification 999 is untouched.
    },
  );
  test(
    'offline replanning preserves existing alarms and same key can retry',
    () async {
      api.offline = true;
      await expectLater(service.schedule(app), throwsA(isA<ApiFailure>()));
      expect(plugin.canceled, isEmpty);
      api.offline = false;
      await service.schedule(app);
      expect(api.reads, 2);
      expect(plugin.scheduled, isNotEmpty);
    },
  );
  test(
    'logout invalidates an in-flight task read before any alarms are created',
    () async {
      api.delayed = Completer();
      final scheduling = service.schedule(app);
      await Future<void>.delayed(Duration.zero);
      final cancel = service.cancel();
      api.delayed!.complete([fixture.record()]);
      await scheduling;
      await cancel;
      expect(plugin.scheduled, isEmpty);
      expect(plugin.cancelAllCount, 1);
    },
  );
  test('account change discards the older in-flight result; new account is scheduled', () async {
    api.delayed = Completer();
    final old = service.schedule(app);
    await Future<void>.delayed(Duration.zero);
    app.user = {'id': 'bob', 'preferences': <String, dynamic>{}};
    final current = service.schedule(app);
    api.delayed!.complete([fixture.record(account: 'bob')]);
    await old;
    await current;
    expect(plugin.scheduled, isNotEmpty);
    expect(
      plugin.scheduled.map((n) => n['payload']['account_id']),
      everyElement('bob'),
    );
  });
  test(
    'permission denial removes only reminders; details require explicit opt in',
    () async {
      await service.schedule(app);
      expect(plugin.scheduled.first['body'], '留一点时间，完成和 TA 的小约定。');
      app.user!['preferences'] = {'lock_screen_details': true};
      await service.schedule(app);
      expect(plugin.scheduled.last['body'], '约定2');
      final count = plugin.scheduled.length;
      service.allowed = false;
      await service.schedule(app);
      expect(plugin.scheduled.length, count);
      expect(plugin.canceled, everyElement(1));
      expect(plugin.cancelAllCount, 0);
    },
  );
}
