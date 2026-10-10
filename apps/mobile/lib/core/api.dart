import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class ApiFailure implements Exception {
  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> details;
  const ApiFailure(
    this.code,
    this.message,
    this.status, [
    this.details = const {},
  ]);
  bool get retryable => status == null || status == 429 || (status ?? 0) >= 500;
  @override
  String toString() => message;
}

/// A validation or state message meant to be shown to the user verbatim.
class UserMessage implements Exception {
  final String message;
  const UserMessage(this.message);
  @override
  String toString() => message;
}

class Api {
  final Dio dio;
  final FlutterSecureStorage vault;
  Map<String, dynamic>? tokens;
  Future<void>? _refreshing;
  int _sessionGeneration = 0;
  Api({Dio? client, FlutterSecureStorage? storage})
    : dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: const String.fromEnvironment('API_BASE_URL'),
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
            ),
          ),
      vault = storage ?? const FlutterSecureStorage();

  int get sessionGeneration => _sessionGeneration;

  Future<void> restore() async {
    final generation = _sessionGeneration;
    final saved = await vault.read(key: 'session');
    _requireSession(generation);
    tokens = saved == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(saved) as Map);
  }

  Future<void> setTokens(Map<String, dynamic> data) async {
    _sessionGeneration++;
    _refreshing = null;
    await _installTokens(data);
  }

  Future<void> _installTokens(Map<String, dynamic> data) async {
    tokens = data;
    await vault.write(key: 'session', value: jsonEncode(data));
  }

  Future<void> clear() async {
    _sessionGeneration++;
    _refreshing = null;
    tokens = null;
    await vault.delete(key: 'session');
    await vault.delete(key: 'profile');
  }

  Future<void> _refresh() async {
    if (_refreshing != null) return _refreshing;
    final generation = _sessionGeneration;
    final refreshToken = tokens?['refresh_token'];
    final work = () async {
      try {
        final r = await dio.post<Object?>(
          '/api/v1/auth/refresh',
          data: {'refresh_token': refreshToken},
        );
        _requireSession(generation);
        await _installTokens(Map<String, dynamic>.from(r.data as Map));
      } on DioException {
        throw const ApiFailure('UNAUTHENTICATED', '登录已过期，请重新登录', 401);
      }
    }();
    _refreshing = work;
    try {
      await work;
    } finally {
      if (identical(_refreshing, work)) _refreshing = null;
    }
  }

  void _requireSession(int generation) {
    if (generation != _sessionGeneration) {
      throw const ApiFailure('SESSION_CHANGED', '账号已切换，请重新操作', 409);
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    dynamic data,
    String? key,
    bool retry = true,
  }) async {
    if (dio.options.baseUrl.isEmpty) {
      throw const ApiFailure(
        'CONFIGURATION_MISSING',
        '未配置服务地址，请按运行手册启动应用',
        null,
      );
    }
    if (kReleaseMode && !dio.options.baseUrl.startsWith('https://')) {
      throw const ApiFailure('HTTPS_REQUIRED', '正式版需要 HTTPS 服务地址', null);
    }
    key ??= method == 'GET' ? null : const Uuid().v4();
    final generation = _sessionGeneration;
    try {
      final r = await dio.request<Object?>(
        '/api/v1$path',
        data: data,
        options: Options(
          method: method,
          headers: {
            if (tokens != null)
              'Authorization': 'Bearer ${tokens!['access_token']}',
            if (method != 'GET') 'Idempotency-Key': key,
          },
        ),
      );
      _requireSession(generation);
      return r.data;
    } on DioException catch (e) {
      _requireSession(generation);
      if (e.response?.statusCode == 401 &&
          retry &&
          tokens != null &&
          !['/auth/login', '/auth/refresh', '/auth/activate'].contains(path)) {
        await _refresh();
        _requireSession(generation);
        return request(method, path, data: data, key: key, retry: false);
      }
      final body = e.response?.data is Map
          ? Map<String, dynamic>.from(e.response!.data as Map)
          : <String, dynamic>{};
      throw ApiFailure(
        body['code'] as String? ?? 'NETWORK_ERROR',
        body['message'] as String? ?? '连接失败，操作已保留，请重试',
        e.response?.statusCode,
        body,
      );
    }
  }

  Future<List<dynamic>> all(String path) async {
    final result = <dynamic>[];
    while (true) {
      final batch = await getList(
        '$path${path.contains('?') ? '&' : '?'}offset=${result.length}&limit=100',
      );
      result.addAll(batch);
      if (batch.length < 100) return result;
    }
  }

  Future<dynamic> get(String path) => request('GET', path);

  /// [get] for endpoints that return a JSON object.
  Future<Map<String, dynamic>> getMap(String path) async =>
      Map<String, dynamic>.from(await get(path) as Map);

  /// [get] for endpoints that return a JSON array.
  Future<List<dynamic>> getList(String path) async =>
      await get(path) as List<dynamic>;
  Future<dynamic> post(String path, [dynamic data, String? key]) =>
      request('POST', path, data: data, key: key);
  Future<dynamic> put(String path, dynamic data) =>
      request('PUT', path, data: data);
}
