import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';

final appProvider = Provider<AppController>(
  (ref) => throw StateError('AppController must be provided'),
);

class AppController extends ChangeNotifier {
  final Api api;
  final LocalStore store;
  Map<String, dynamic>? user;
  String? sid;
  Map<String, dynamic>? snapshot;
  List<Map<String, Object?>> pending = [];
  String? error;
  bool loading = false;
  bool initializing = false;
  bool offline = false;
  bool needsLogin = false;

  /// Cat animation frame; separate so a pose change never rebuilds pages.
  final pose = ValueNotifier<int>(0);
  int get catPose => pose.value;
  set catPose(int value) => pose.value = value;
  WebSocket? _socket;
  bool _paused = false;
  Timer? _retry;
  Timer? _feedback;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _changingSession = false;
  bool _disposed = false;
  int _sessionGeneration = 0;
  Completer<void>? _syncIdle;
  Future<void>? _initialization;
  int _failures = 0;
  AppController(this.api, this.store);
  void changed() => notifyListeners();
  String get uid => user?['id'] as String? ?? '';
  String get root => '/spaces/$sid';
  String get today => data?.today ?? '';

  Snapshot? _data;
  Map<String, dynamic>? _dataSource;

  /// Typed view of [snapshot], rebuilt only when the snapshot changes.
  Snapshot? get data {
    final source = snapshot;
    if (source == null) return null;
    if (!identical(source, _dataSource)) {
      _dataSource = source;
      _data = Snapshot(source);
    }
    return _data;
  }

  List<Map<String, dynamic>> get instances =>
      (snapshot?['daily']?['instances'] as List? ?? [])
          .cast<Map<String, dynamic>>();

  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    initializing = true;
    notifyListeners();
    try {
      await _restoreAccount();
    } catch (e) {
      if (e is ApiFailure && e.code == 'SESSION_CHANGED') return;
      // Corrupt/unavailable local storage must not expose raw token JSON in an error.
      user = null;
      sid = null;
      snapshot = null;
      pending = [];
      needsLogin = true;
      error = '本机会话恢复失败，请重新登录。';
      try {
        await api.clear();
      } catch (_) {}
    } finally {
      initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _restoreAccount() async {
    await api.restore();
    if (api.tokens == null) return;
    final profile = await api.vault.read(key: 'profile');
    if (profile != null) {
      user = Map<String, dynamic>.from(jsonDecode(profile) as Map);
    }
    try {
      user = await api.getMap('/auth/me');
      await api.vault.write(key: 'profile', value: jsonEncode(user));
    } catch (e) {
      _error(e);
    }
    if (user != null) {
      final spaces = user!['spaces'] as List? ?? [];
      if (spaces.isNotEmpty) {
        final savedSpace = await api.vault.read(key: 'active_space_$uid');
        sid = spaces.any((s) => s['id'] == savedSpace)
            ? savedSpace
            : spaces.first['id'] as String?;
        await api.vault.write(key: 'active_space_$uid', value: sid);
        snapshot = await store.read(uid, sid!);
        pending = _keep(pending, await store.queue(uid, sid!));
        await sync();
      }
    }
  }

  Future<void> login(String username, String password) async {
    await _beginSessionChange();
    try {
      await api.setTokens(
        Map<String, dynamic>.from(
          await api.post('/auth/login', {
            'username': username,
            'password': password,
          }) as Map,
        ),
      );
      await api.vault.delete(key: 'profile');
      user = null;
      sid = null;
      snapshot = null;
      pending = [];
    } finally {
      _changingSession = false;
    }
    error = null;
    needsLogin = false;
    await _restoreAccount();
    notifyListeners();
  }

  Future<void> reloadUser() async {
    user = await api.getMap('/auth/me');
    await api.vault.write(key: 'profile', value: jsonEncode(user));
    final spaces = user!['spaces'] as List;
    sid = spaces.isEmpty
        ? null
        : spaces.any((s) => s['id'] == sid)
        ? sid
        : spaces.first['id'] as String?;
    await api.vault.write(key: 'active_space_$uid', value: sid);
    if (sid != null) await sync();
    notifyListeners();
  }

  Future<dynamic> command(String path, [dynamic data]) async {
    final result = await api.post(path, data);
    await sync();
    return result;
  }

  void _error(Object e) {
    error = e.toString();
    if (e is ApiFailure) {
      offline = e.retryable;
      needsLogin = e.status == 401;
    }
  }

  Future<void> sync() async {
    if (_disposed || _changingSession || sid == null || api.tokens == null) {
      return;
    }
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    final generation = _sessionGeneration;
    final idle = Completer<void>();
    _syncIdle = idle;
    bool active() => !_disposed && generation == _sessionGeneration;
    try {
      final previousLevel = snapshot?['growth']?['level'] as int?;
      final received = await api.getMap('$root/snapshot');
      if (!active()) return;
      snapshot = _merge(snapshot, received);
      if (previousLevel != null &&
          (snapshot!['growth']['level'] as int) > previousLevel) {
        catPose = 3;
      }
      await store.cache(uid, sid!, snapshot!);
      if (!active()) return;
      offline = false;
      error = null;
      needsLogin = false;
      pending = _keep(pending, await store.queue(uid, sid!));
      if (!active()) return;
      var submitted = false;
      for (final op in pending) {
        if (op['status'] == 'failed') continue;
        final id = op['id'] as String;
        final desired = op['desired'] == 1;
        final version = op['version'];
        final current = instances
            .where((i) => i['id'] == op['instance'])
            .firstOrNull;
        if (current != null && current['completed'] == desired) {
          await store.remove(id);
          continue;
        }
        await store.update(id, {'attempts': (op['attempts'] as int) + 1});
        if (!active()) return;
        submitted = true;
        try {
          await api.post('$root/instances/${op['instance']}/checkin', {
            'desired_state': desired,
            'expected_version': version,
          }, id);
          if (!active()) return;
          await store.remove(id);
          catPose = 2;
        } on ApiFailure catch (e) {
          if (!active()) return;
          if (e.code == 'DATE_REQUIRES_REVIEW') {
            try {
              await api.post('$root/instances/${op['instance']}/corrections', {
                'desired_state': desired,
                'expected_version': version,
                'reason': '跨日离线操作补记，等待另一位成员确认',
              }, '$id-review');
              if (!active()) return;
              await store.remove(id);
            } on ApiFailure catch (reviewError) {
              await store.update(id, {
                'status': reviewError.retryable ? 'pending' : 'failed',
                'error': reviewError.message,
              });
              if (reviewError.retryable) rethrow;
            }
          } else if (e.retryable) {
            rethrow;
          } else {
            await store.update(id, {'status': 'failed', 'error': e.message});
            if (e.status == 401) rethrow;
          }
        }
      }
      // Only check-ins sent above can have changed the server since the first read.
      if (submitted) {
        final latest = await api.getMap('$root/snapshot');
        if (!active()) return;
        snapshot = _merge(snapshot, latest);
        await store.cache(uid, sid!, snapshot!);
      }
      pending = _keep(pending, await store.queue(uid, sid!));
      if (!active()) return;
      _failures = 0;
      _retry?.cancel();
      // A live socket pushes changes, so polling is only a slow safety net then.
      if (!_paused) {
        _retry = Timer(Duration(seconds: _socket == null ? 20 : 90), sync);
      }
      _feedback?.cancel();
      _feedback = Timer(const Duration(milliseconds: 500), () => catPose = 0);
      if (_socket == null && !_paused) unawaited(_connect());
    } catch (e) {
      if (!active()) return;
      _error(e);
      if (sid != null) pending = _keep(pending, await store.queue(uid, sid!));
      final seconds = min(60, 2 << min(_failures++, 5)) + Random().nextInt(3);
      _retry?.cancel();
      if (!needsLogin && !_paused) {
        _retry = Timer(Duration(seconds: seconds), sync);
      }
    } finally {
      _syncing = false;
      idle.complete();
      if (identical(_syncIdle, idle)) _syncIdle = null;
      if (active()) notifyListeners();
      if (_syncAgain) {
        _syncAgain = false;
        if (!_changingSession && !offline && !needsLogin) unawaited(sync());
      }
    }
  }

  /// Keeps unchanged top-level sections identical so selective rebuilds skip them.
  static Map<String, dynamic> _merge(
    Map<String, dynamic>? previous,
    Map<String, dynamic> next,
  ) {
    if (previous == null) return next;
    var same = previous.length == next.length;
    final merged = <String, dynamic>{};
    for (final entry in next.entries) {
      final old = previous[entry.key];
      if (previous.containsKey(entry.key) &&
          jsonEncode(old) == jsonEncode(entry.value)) {
        merged[entry.key] = old;
      } else {
        merged[entry.key] = entry.value;
        same = false;
      }
    }
    return same ? previous : merged;
  }

  static List<Map<String, Object?>> _keep(
    List<Map<String, Object?>> previous,
    List<Map<String, Object?>> next,
  ) => jsonEncode(previous) == jsonEncode(next) ? previous : next;

  /// App went to the background: stop polling and the socket until [resume].
  void pause() {
    _paused = true;
    _retry?.cancel();
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
  }

  Future<void> resume() {
    _paused = false;
    return sync();
  }

  Future<void> _connect() async {
    if (_disposed ||
        _paused ||
        _changingSession ||
        sid == null ||
        api.tokens == null) {
      return;
    }
    final generation = _sessionGeneration;
    try {
      final url = Uri.parse('${api.dio.options.baseUrl}/api/v1$root/ws')
          .replace(
            scheme: api.dio.options.baseUrl.startsWith('https') ? 'wss' : 'ws',
          );
      final socket = await WebSocket.connect(
        url.toString(),
        headers: {'Authorization': 'Bearer ${api.tokens!['access_token']}'},
      );
      if (_disposed || _paused || generation != _sessionGeneration) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.add(jsonEncode({'after_seq': snapshot?['snapshot_seq'] ?? 0}));
      socket.listen(
        (_) {
          if (identical(_socket, socket) && generation == _sessionGeneration) {
            unawaited(sync());
          }
        },
        onDone: () {
          if (identical(_socket, socket)) {
            _socket = null;
            unawaited(sync());
          }
        },
        onError: (Object _) {
          if (identical(_socket, socket)) _socket = null;
        },
      );
    } catch (_) {
      if (generation == _sessionGeneration) _socket = null;
    }
  }

  Future<void> checkin(Map<String, dynamic> instance, bool desired) async {
    await store.enqueue(uid, sid!, instance, desired);
    pending = _keep(pending, await store.queue(uid, sid!));
    notifyListeners();
    await sync();
  }

  Future<void> retryOperation(String id) async {
    await store.update(id, {'status': 'pending', 'error': ''});
    await sync();
  }

  Future<void> discardFailedOperation(String id) async {
    final operation = pending.where((op) => op['id'] == id).firstOrNull;
    if (operation == null || operation['status'] != 'failed') return;
    final account = uid, space = sid;
    await store.remove(id);
    final remaining = await store.queue(account, space!);
    if (uid != account || sid != space) return;
    pending = remaining;
    notifyListeners();
    await sync();
  }

  Future<void> logout({required bool keepQueue}) async {
    // Offline logout would leave the old push registration active: retry server logout first.
    await _beginSessionChange();
    try {
      await api.post('/auth/logout');
      await store.logout(uid, keepQueue: keepQueue);
      await api.clear();
      _retry?.cancel();
      await _socket?.close();
      _socket = null;
      user = null;
      sid = null;
      snapshot = null;
      pending = [];
      needsLogin = false;
      error = null;
    } finally {
      _changingSession = false;
      notifyListeners();
    }
  }

  Future<void> _beginSessionChange() async {
    await _initialization;
    _changingSession = true;
    _sessionGeneration++;
    _retry?.cancel();
    await _syncIdle?.future;
    await _socket?.close();
    _socket = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionGeneration++;
    _retry?.cancel();
    _feedback?.cancel();
    _socket?.close();
    pose.dispose();
    super.dispose();
  }
}
