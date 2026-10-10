import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

class _Store extends LocalStore {
  _Store() : super(_Database());
  @override
  Future<void> logout(String account, {required bool keepQueue}) async {}
}

class _SlowApi extends Api {
  final gate = Completer<void>();
  int logouts = 0;
  @override
  Future<void> restore() async {
    await gate.future;
    tokens = null;
  }

  @override
  Future<dynamic> post(String path, [dynamic data, String? key]) async {
    logouts++;
    return {};
  }
}

class _Notifications extends NotificationService {
  @override
  Future<void> register(AppController app) async {}
  @override
  Future<void> schedule(AppController app) async {}
}

class _LoginApi extends Api {
  int account = 0;
  @override
  Future<dynamic> post(String path, [dynamic data, String? key]) async {
    if (path == '/auth/login') {
      account++;
      return {
        'access_token': 'account-$account',
        'refresh_token': 'refresh-$account',
      };
    }
    return {};
  }

  @override
  Future<dynamic> get(String path) async => {
    'id': 'user-$account',
    'nickname': 'Account $account',
    'spaces': <dynamic>[],
  };
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'cold startup holds the login form until local restoration completes',
    (tester) async {
      final api = _SlowApi();
      final app = AppController(api, _Store());
      final restoring = app.init();
      await tester.pumpWidget(MiaobanApp(app, _Notifications()));
      await tester.pump();
      expect(find.text('正在恢复账号与小屋…'), findsOneWidget);
      expect(find.text('登录'), findsNothing);
      api.gate.complete();
      await restoring;
      await tester.pumpAndSettle();
      expect(app.initializing, isFalse);
      expect(find.text('登录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  test(
    'programmatic logout waits for initialization before changing the session',
    () async {
      final api = _SlowApi();
      final app = AppController(api, _Store());
      final restoring = app.init();
      final logout = app.logout(keepQueue: true);
      await Future<void>.delayed(Duration.zero);
      expect(api.logouts, 0);
      api.gate.complete();
      await restoring;
      await logout;
      expect(api.logouts, 1);
      expect(app.user, isNull);
      app.dispose();
    },
  );
  test('corrupted local session exits startup with a recoverable, sanitized login error', () async {
    FlutterSecureStorage.setMockInitialValues({
      'session': 'broken fixture-private-token',
    });
    final api = Api();
    final app = AppController(api, _Store());
    await app.init();
    expect(app.initializing, isFalse);
    expect(app.needsLogin, isTrue);
    expect(api.tokens, isNull);
    expect(app.error, '本机会话恢复失败，请重新登录。');
    expect(app.error, isNot(contains('fixture-private-token')));
    app.dispose();
  });

  test(
    'login restores each new account after the one-time cold initialization',
    () async {
      final api = _LoginApi();
      final app = AppController(api, _Store());
      await app.init();
      expect(app.user, isNull);
      await app.login('first', 'fixture-password');
      expect(app.uid, 'user-1');
      await app.logout(keepQueue: true);
      expect(app.user, isNull);
      await app.login('second', 'fixture-password');
      expect(app.uid, 'user-2');
      expect(app.needsLogin, isFalse);
      app.dispose();
    },
  );
}
