import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/core/api.dart';

class _Backend implements HttpClientAdapter {
  final refreshStarted = Completer<void>();
  final finishRefresh = Completer<void>();
  final keys = <String?>[];
  final payloads = <dynamic>[];
  bool holdRefresh = true;
  int protectedRequests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/auth/refresh')) {
      refreshStarted.complete();
      if (holdRefresh) await finishRefresh.future;
      return response({
        'access_token': 'rotated',
        'refresh_token': 'rotated-refresh',
      });
    }
    protectedRequests++;
    keys.add(options.headers['Idempotency-Key'] as String?);
    payloads.add(options.data);
    if (protectedRequests == 1) {
      return response({'code': 'UNAUTHENTICATED'}, 401);
    }
    return response({'accepted': true});
  }

  ResponseBody response(dynamic data, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
  @override
  void close({bool force = false}) {}
}

class _HeldStorage extends FlutterSecureStorage {
  final gate = Completer<String?>();
  bool held = false;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key == 'session' && !held) {
      held = true;
      return gate.future;
    }
    return super.read(key: key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Api client(_Backend backend) => Api(
    client: Dio(BaseOptions(baseUrl: 'http://isolated.invalid'))
      ..httpClientAdapter = backend,
  );

  for (final logout in [false, true]) {
    test(
      'a delayed vault restoration cannot overwrite ${logout ? 'logout' : 'a new account'}',
      () async {
        final vault = _HeldStorage();
        final api = Api(storage: vault);
        final pending = expectLater(
          api.restore(),
          throwsA(
            isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
          ),
        );
        if (logout) {
          await api.clear();
        } else {
          await api.setTokens({
            'access_token': 'new-account',
            'refresh_token': 'new-refresh',
          });
        }
        vault.gate.complete(
          '{"access_token":"old-account","refresh_token":"old-refresh"}',
        );
        await pending;
        expect(api.tokens?['access_token'], logout ? isNull : 'new-account');
        final saved = await vault.read(key: 'session');
        expect(saved, logout ? isNull : contains('new-account'));
      },
    );
  }

  test(
    'a delayed refresh cannot revive tokens or retry after logout',
    () async {
      final backend = _Backend();
      final api = client(backend);
      await api.setTokens({
        'access_token': 'old',
        'refresh_token': 'old-refresh',
      });
      final pending = api.get('/spaces/room/snapshot');
      final assertion = expectLater(
        pending,
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      await backend.refreshStarted.future;
      await api.clear();
      backend.finishRefresh.complete();
      await assertion;
      expect(api.tokens, isNull);
      expect(await api.vault.read(key: 'session'), isNull);
      expect(backend.protectedRequests, 1);
    },
  );

  test('an old refresh cannot overwrite a newly logged-in account', () async {
    final backend = _Backend();
    final api = client(backend);
    await api.setTokens({
      'access_token': 'old',
      'refresh_token': 'old-refresh',
    });
    final assertion = expectLater(
      api.get('/spaces/old/snapshot'),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await backend.refreshStarted.future;
    await api.setTokens({
      'access_token': 'new-account',
      'refresh_token': 'new-account-refresh',
    });
    backend.finishRefresh.complete();
    await assertion;
    expect(api.tokens!['access_token'], 'new-account');
    expect(
      jsonDecode((await api.vault.read(key: 'session'))!)['access_token'],
      'new-account',
    );
  });

  test('a legitimate token rotation retries the original mutation with the same UUID and payload', () async {
    final backend = _Backend()..holdRefresh = false;
    final api = client(backend);
    await api.setTokens({
      'access_token': 'old',
      'refresh_token': 'old-refresh',
    });
    expect(await api.post('/spaces/room/tasks', {'title': 'One intent'}), {
      'accepted': true,
    });
    expect(backend.keys, hasLength(2));
    expect(backend.keys[0], isNotEmpty);
    expect(backend.keys[0], backend.keys[1]);
    expect(backend.payloads[0], backend.payloads[1]);
    expect(api.tokens!['access_token'], 'rotated');
  });
}
