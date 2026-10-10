import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:miaoban/features/notifications/notification_service.dart';
import 'package:miaoban/features/settings/settings_screen.dart';
import 'package:miaoban/main.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store extends LocalStore {
  _Store() : super(_UnusedDatabase());
  @override
  Future<void> logout(String account, {required bool keepQueue}) async {}
}

class _Api extends Api {
  @override
  Future<dynamic> post(String path, [dynamic data, String? key]) async => {};
  @override
  Future<void> clear() async {
    tokens = null;
  }
}

class _Notifications extends NotificationService {
  @override
  Future<void> register(AppController app) async {}
  @override
  Future<void> schedule(AppController app) async {}
  @override
  Future<void> cancel() async {}
}

void main() {
  testWidgets(
    'logout from settings replaces protected routes without a null-state crash',
    (tester) async {
      final app = AppController(_Api(), _Store())
        ..user = {
          'id': 'alice',
          'nickname': 'Alice',
          'avatar': 'ginger',
          'preferences': {'reduce_motion': true},
        }
        ..sid = 'room'
        ..snapshot = {
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
      await tester.pumpWidget(MiaobanApp(app, _Notifications()));
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('登录'), findsOneWidget);
      expect(app.user, isNull);
      expect(app.snapshot, isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
