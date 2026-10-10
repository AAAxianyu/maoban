import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:miaoban/features/notifications/notification_service.dart';
import 'package:miaoban/features/settings/settings_screen.dart';
import 'package:miaoban/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two accounts complete a real API flow, then log out and restore the same records',
    (tester) async {
      const url = String.fromEnvironment('API_BASE_URL');
      expect(
        url,
        isNotEmpty,
        reason: 'Explicit isolated development API is required',
      );
      final a = Api(client: Dio(BaseOptions(baseUrl: url))),
          b = Api(client: Dio(BaseOptions(baseUrl: url)));
      for (final pair in [(a, 'demo_a'), (b, 'demo_b')]) {
        final tokens = await pair.$1.post('/auth/login', {
          'username': pair.$2,
          'password': 'Demo-only-password-123',
        });
        pair.$1.tokens = Map<String, dynamic>.from(tokens as Map);
      }
      final userA = await a.get('/auth/me');
      final userB = await b.get('/auth/me');
      final sid = (await a.post('/spaces', {
        'name': '设备集成验收 ${DateTime.now().millisecondsSinceEpoch}',
        'timezone': 'UTC',
      }))['id'];
      final invite = await a.post('/spaces/$sid/invitations');
      await b.post('/invitations/claim', {'token': invite['token']});
      final today = (await a.get('/spaces/$sid'))['today'];
      final task = await a.post('/spaces/$sid/tasks', {
        'executor_id': userB['id'],
        'title': '真实后端一键练习',
        'standard': '完成一次集成验收',
        'points': 15,
        'starts_on': today,
        'tag': 'c',
      });
      await b.post(
        '/spaces/$sid/task-versions/${task['proposal']['id']}/decision',
        {'accepted': true},
      );
      final store = await LocalStore.open();
      final app = AppController(b, store);
      await b.vault.write(
        key: 'active_space_${userB['id']}',
        value: sid as String?,
      );
      await b.setTokens(b.tokens!);
      await app.init();
      final notifications = NotificationService();
      await notifications.init();
      const notificationsAllowed = bool.fromEnvironment(
        'NOTIFICATIONS_ALLOWED',
      );
      expect(
        notifications.allowed,
        notificationsAllowed,
        reason: 'Actual emulator OS permission must match the test mode',
      );
      final channels = await notifications.plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!
          .getNotificationChannels();
      expect(
        channels!.map((c) => c.id),
        containsAll(['partner_events', 'task_reminders']),
      );
      await tester.pumpWidget(MiaobanApp(app, notifications));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('真实后端一键练习'), findsOneWidget);
      await tester.tap(find.byTooltip('完成打卡'));
      await tester.pump(const Duration(seconds: 2));
      await app.sync();
      await tester.pump();
      expect((await b.get('/spaces/$sid/wallet'))['balance'], 15);
      final reward = await a.post('/spaces/$sid/rewards', {
        'recipient_id': userB['id'],
        'title': '验收奖品',
        'description': '明确隔离的测试承诺',
        'price': 10,
        'stock': 1,
        'published': true,
      });
      final order = (await b.post(
        '/spaces/$sid/rewards/${reward['id']}/redeem',
        {'confirmed_price': 10},
      ))['order'];
      await a.post('/spaces/$sid/orders/${order['id']}/command', {
        'action': 'fulfill',
        'expected_version': 1,
      });
      await b.post('/spaces/$sid/orders/${order['id']}/command', {
        'action': 'confirm',
        'expected_version': 2,
      });
      expect(
        (await b.get('/spaces/$sid/orders')).single['status'],
        'completed',
      );
      expect((await b.get('/spaces/$sid/wallet'))['balance'], 5);
      expect(userA['id'], isNot(userB['id']));
      final reminderAt = DateTime.now().toUtc().add(const Duration(hours: 1));
      final reminderTask = await b.post('/spaces/$sid/tasks', {
        'executor_id': userB['id'],
        'title': '本地通知权限验收',
        'standard': '只验证系统提醒，不发测试积分',
        'points': 0,
        'starts_on': reminderAt.toIso8601String().substring(0, 10),
        'reminder':
            '${reminderAt.hour.toString().padLeft(2, '0')}:${reminderAt.minute.toString().padLeft(2, '0')}',
      });
      await app.sync();
      await notifications.schedule(app);
      final alarms = await notifications.plugin.pendingNotificationRequests();
      final matching = alarms.where((n) {
        final p = jsonDecode(n.payload ?? '{}');
        return p['task_id'] == reminderTask['task']['id'];
      }).toList();
      expect(matching.isNotEmpty, notificationsAllowed);
      for (final alarm in matching) {
        expect(jsonDecode(alarm.payload!)['account_id'], userB['id']);
        expect(alarm.body, '留一点时间，完成和 TA 的小约定。');
      }
      await tester.tap(find.byTooltip('账号与设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('退出登录'),
        600,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('登录'), findsOneWidget);
      expect(app.user, isNull);
      expect(
        await notifications.plugin.pendingNotificationRequests(),
        isEmpty,
        reason: 'Logout clears native alarms for the old account',
      );
      await app.login('demo_b', 'Demo-only-password-123');
      await tester.pumpAndSettle();
      expect(app.sid, sid);
      expect(app.snapshot!['wallet']['balance'], 5);
      expect(
        (await b.get('/spaces/$sid/orders')).single['status'],
        'completed',
      );
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await store.db.close();
    },
  );
}
