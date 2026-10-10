import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:miaoban/features/auth/auth_screen.dart';
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

class _AuthApi extends Api {
  final calls = <(String, Map<String, dynamic>)>[];
  bool failLogin = false;
  ApiFailure? activationFailure;

  @override
  Future<dynamic> post(String path, [dynamic data, String? key]) async {
    calls.add((path, Map<String, dynamic>.from(data as Map)));
    if (path == '/auth/activate') {
      if (activationFailure != null) throw activationFailure!;
      return {'user_id': 'fixture-user'};
    }
    if (failLogin) {
      throw const ApiFailure('NETWORK_ERROR', '连接失败，请重试', null);
    }
    return {
      'access_token': 'fixture-access',
      'refresh_token': 'fixture-refresh',
    };
  }

  @override
  Future<dynamic> get(String path) async => {
    'id': 'fixture-user',
    'nickname': '小猫',
    'spaces': <dynamic>[],
  };
}

Finder field(String name) => find.byKey(ValueKey('auth-$name'));

Future<AppController> _mount(WidgetTester tester, _AuthApi api) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final app = AppController(api, _Store());
  await tester.pumpWidget(MaterialApp(home: AuthScreen(app)));
  addTearDown(app.dispose);
  return app;
}

Future<void> press(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> activateMode(WidgetTester tester) async {
  final button = find.text('首次使用？激活账号');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final username in ['中文账号', 'account name', 'a' * 81]) {
    testWidgets(
      'invalid activation username is explained before networking: $username',
      (tester) async {
        final api = _AuthApi();
        await _mount(tester, api);
        await activateMode(tester);
        await tester.enterText(
          field('token'),
          'fixture-activation-token-12345',
        );
        await tester.enterText(field('nickname'), '小猫');
        await tester.enterText(field('username'), username);
        await tester.enterText(field('password'), 'fixture-password-123');
        await press(tester, '激活并登录');
        expect(api.calls, isEmpty);
        expect(
          find.textContaining('账号须为').evaluate().isNotEmpty ||
              find.textContaining('中文可用作昵称').evaluate().isNotEmpty,
          isTrue,
        );
        expect(
          tester.widget<TextFormField>(field('username')).controller!.text,
          username,
        );
      },
    );
  }

  testWidgets('whitespace cannot make a short password pass local validation', (
    tester,
  ) async {
    final api = _AuthApi();
    await _mount(tester, api);
    await tester.enterText(field('username'), 'fixture-cat');
    await tester.enterText(field('password'), '  short123  ');
    await press(tester, '登录');
    expect(api.calls, isEmpty);
    expect(find.text('密码须为 10–128 个字符，首尾空格不计入长度'), findsOneWidget);
  });

  testWidgets(
    'pasted activation fields are trimmed and a Chinese nickname activates then logs in',
    (tester) async {
      final api = _AuthApi();
      final app = await _mount(tester, api);
      await tester.enterText(field('username'), '  fixture-cat  ');
      await tester.enterText(field('password'), '  fixture-password-123  ');
      await activateMode(tester);
      expect(
        tester.widget<TextFormField>(field('username')).controller!.text,
        '  fixture-cat  ',
      );
      await tester.enterText(
        field('token'),
        '  fixture-activation-token-12345  ',
      );
      await tester.enterText(field('nickname'), '  小猫  ');
      await press(tester, '激活并登录');
      expect(api.calls.map((call) => call.$1), [
        '/auth/activate',
        '/auth/login',
      ]);
      expect(api.calls.first.$2, {
        'username': 'fixture-cat',
        'password': 'fixture-password-123',
        'token': 'fixture-activation-token-12345',
        'nickname': '小猫',
      });
      expect(app.uid, 'fixture-user');
    },
  );

  testWidgets(
    'server validation appears at the field and clears when corrected',
    (tester) async {
      final api = _AuthApi()
        ..activationFailure = const ApiFailure(
          'INVALID_INPUT',
          '服务器密码校验提示',
          422,
          {
            'field_errors': {'password': '服务器密码校验提示'},
          },
        );
      await _mount(tester, api);
      await activateMode(tester);
      await tester.enterText(field('token'), 'fixture-activation-token-12345');
      await tester.enterText(field('nickname'), '小猫');
      await tester.enterText(field('username'), 'fixture-cat');
      await tester.enterText(field('password'), 'fixture-password-123');
      await press(tester, '激活并登录');
      expect(find.text('服务器密码校验提示'), findsOneWidget);
      await tester.enterText(field('password'), 'corrected-password-123');
      await tester.pumpAndSettle();
      expect(find.text('服务器密码校验提示'), findsNothing);
      expect(
        tester.widget<TextFormField>(field('username')).controller!.text,
        'fixture-cat',
      );
    },
  );

  testWidgets(
    'login retry after successful activation never consumes the code a second time',
    (tester) async {
      final api = _AuthApi()..failLogin = true;
      final app = await _mount(tester, api);
      await activateMode(tester);
      await tester.enterText(field('token'), 'fixture-activation-token-12345');
      await tester.enterText(field('nickname'), '小猫');
      await tester.enterText(field('username'), 'fixture-cat');
      await tester.enterText(field('password'), 'fixture-password-123');
      await press(tester, '激活并登录');
      expect(find.textContaining('账号已激活。'), findsOneWidget);
      expect(find.textContaining('无需再次使用激活码'), findsOneWidget);
      expect(field('token'), findsNothing);
      api.failLogin = false;
      await press(tester, '登录');
      expect(api.calls.where((call) => call.$1 == '/auth/activate').length, 1);
      expect(app.uid, 'fixture-user');
    },
  );
}
