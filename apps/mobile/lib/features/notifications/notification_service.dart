import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/controller.dart';
import '../feed/feed_screen.dart';
import 'quiet_hours.dart';
import 'reminder_plan.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin plugin;
  final DateTime Function() clock;
  NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? clock,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       clock = clock ?? DateTime.now;
  Future<void> _scheduleTail = Future.value();
  int _scheduleEpoch = 0;
  String? _lastScheduleKey;
  final MethodChannel apns = const MethodChannel('com.miaoban/push');
  final StreamController<Map<String, dynamic>> taps =
      StreamController.broadcast();
  bool allowed = false;
  final List<Map<String, dynamic>> initialTaps = [];
  String? _registeredUser;
  bool _registering = false;
  DateTime? _lastAttempt;
  String? _attemptSession;
  String? registrationError;
  AppController? _app;
  Future<void> init() async {
    tzdata.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) {
          taps.add(Map<String, dynamic>.from(jsonDecode(r.payload!) as Map));
        }
      },
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final payload = launch!.notificationResponse?.payload;
      if (payload != null) {
        initialTaps.add(Map<String, dynamic>.from(jsonDecode(payload) as Map));
      }
    }
    if (Platform.isIOS || Platform.isAndroid) {
      apns.setMethodCallHandler((call) async {
        if (call.method == 'notificationTap') {
          taps.add(Map<String, dynamic>.from(call.arguments as Map));
        } else if (call.method == 'tokenChanged') {
          _registeredUser = null;
          _lastAttempt = null;
          if (_app != null) unawaited(register(_app!));
        } else if (call.method == 'foregroundNotification' &&
            allowed &&
            _app?.sid == (call.arguments as Map)['space_id']) {
          await _foreground(Map<String, dynamic>.from(call.arguments as Map));
        }
      });
      final remote = await apns.invokeMethod<dynamic>('initialNotification');
      if (remote is Map) initialTaps.add(Map<String, dynamic>.from(remote));
    }
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'partner_events',
        'TA 的动态',
        description: '打卡、鼓励与奖励进度',
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'task_reminders',
        '每日约定提醒',
        description: '你接受的任务时间提醒',
      ),
    );
    await refreshPermission();
  }

  Future<void> refreshPermission() async {
    final previous = allowed;
    allowed = Platform.isIOS
        ? (await plugin
                      .resolvePlatformSpecificImplementation<
                        IOSFlutterLocalNotificationsPlugin
                      >()
                      ?.checkPermissions())
                  ?.isEnabled ??
              false
        : await plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.areNotificationsEnabled() ??
              false;
    if (previous != allowed) {
      _lastScheduleKey = null;
      _lastAttempt = null;
      _registeredUser = null;
    }
  }

  Future<void> _foreground(Map<String, dynamic> payload) async {
    final app = _app!;
    final uid = app.uid, session = app.api.sessionGeneration;
    try {
      final n = await app.api.get(
        '/notifications/${payload['notification_id']}',
      );
      if (!allowed ||
          uid != app.uid ||
          session != app.api.sessionGeneration ||
          app.needsLogin ||
          n['space_id'] != app.sid) {
        return;
      }
      final type = n['event']['type'] as String;
      final preferences = Map<String, dynamic>.from(
        app.user?['preferences'] as Map? ?? const {},
      );
      final category = type.startsWith('checkin')
          ? 'checkins'
          : type.startsWith('interaction')
          ? 'interactions'
          : 'rewards';
      final zone = reminderLocation(
        app.snapshot!['space']['config']['timezone'] as String,
      );
      final at = tz.TZDateTime.from(clock(), zone);
      if (preferences[category] == false ||
          afterQuietHours(
                at,
                preferences['quiet_start'] as String? ?? '22:00',
                preferences['quiet_end'] as String? ?? '08:00',
              ) !=
              at) {
        return;
      }
      await plugin.show(
        id: (payload['notification_id'] as String).hashCode & 0x7fffffff,
        title: '喵伴',
        body: preferences['lock_screen_details'] == true
            ? 'TA${eventTitle(type)}'
            : 'TA有新的打卡动态',
        payload: jsonEncode(payload),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'partner_events',
            'TA 的动态',
            tag: payload['notification_id'] as String?,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {
      // The inbox remains the source of truth when an alert cannot be authorized.
    } finally {
      if (uid == app.uid && session == app.api.sessionGeneration) {
        unawaited(app.sync());
      }
    }
  }

  Future<bool> request(AppController app) async {
    allowed = Platform.isIOS
        ? await plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, badge: true, sound: true) ??
              false
        : await plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.requestNotificationsPermission() ??
              false;
    _lastAttempt = null;
    _lastScheduleKey = null;
    await register(app);
    return allowed;
  }

  Future<void> register(AppController app) async {
    _app = app;
    final uid = app.uid, session = app.api.sessionGeneration;
    final attemptSession = '$uid/$session';
    if (_attemptSession != attemptSession) {
      _attemptSession = attemptSession;
      _lastAttempt = null;
      _registeredUser = null;
    }
    if (_registering ||
        (_lastAttempt != null &&
            clock().difference(_lastAttempt!) < const Duration(minutes: 10))) {
      return;
    }
    if (allowed &&
        app.user != null &&
        !app.needsLogin &&
        _registeredUser != app.uid) {
      _registering = true;
      _lastAttempt = clock();
      try {
        final token = await apns.invokeMethod<String>('register');
        if (token != null &&
            allowed &&
            uid == app.uid &&
            session == app.api.sessionGeneration &&
            !app.needsLogin &&
            identical(_app, app)) {
          await app.api.post('/devices', {
            'token': token,
            'platform': Platform.isIOS ? 'ios' : 'android',
            'provider': Platform.isIOS ? 'apns' : 'fcm',
          });
          if (uid != app.uid || session != app.api.sessionGeneration) return;
          _registeredUser = uid;
          registrationError = null;
        }
      } on PlatformException catch (e) {
        registrationError = e.message ?? '远程通知注册未完成';
      } catch (_) {
        registrationError = '远程通知注册未完成，请稍后重试';
      } finally {
        _registering = false;
      }
    }
  }

  Future<void> cancel() async {
    _scheduleEpoch++;
    _lastScheduleKey = null;
    _registeredUser = null;
    _lastAttempt = null;
    _attemptSession = null;
    _app = null;
    final work = _scheduleTail.then((_) => plugin.cancelAll());
    _scheduleTail = work.catchError((Object _) {});
    await work;
  }

  String? _scheduleKey(AppController app) {
    if (app.user == null ||
        app.needsLogin ||
        app.sid == null ||
        app.snapshot == null) {
      return null;
    }
    final zone = reminderLocation(
      app.snapshot!['space']['config']['timezone'] as String,
    );
    final date = tz.TZDateTime.from(
      clock(),
      zone,
    ).toIso8601String().substring(0, 10);
    return jsonEncode([
      app.uid,
      app.sid,
      app.api.sessionGeneration,
      allowed,
      app.snapshot!['snapshot_seq'],
      date,
      app.today,
      app.user!['preferences'],
    ]);
  }

  Future<void> _clearReminders() async {
    for (final request in await plugin.pendingNotificationRequests()) {
      try {
        final payload = jsonDecode(request.payload ?? '{}');
        if (payload['kind'] == 'task_reminder' || payload['task_id'] != null) {
          await plugin.cancel(id: request.id);
        }
      } catch (_) {
        /* An unrelated notification is preserved. */
      }
    }
  }

  Future<void> schedule(AppController app) {
    final epoch = _scheduleEpoch;
    final key = _scheduleKey(app);
    if (key == null || key == _lastScheduleKey) return Future.value();
    final work = _scheduleTail.then((_) async {
      bool active() => epoch == _scheduleEpoch && key == _scheduleKey(app);
      if (!active() || key == _lastScheduleKey) return;
      final preferences = Map<String, dynamic>.from(
        app.user?['preferences'] as Map? ?? const {},
      );
      // Fetch before replacing alarms, so offline failure leaves existing reminders intact.
      final tasks = allowed && preferences['reminders'] != false
          ? await app.api.all('${app.root}/tasks')
          : <dynamic>[];
      if (!active()) return;
      final reminders = allowed
          ? planReminders(
              account: app.uid,
              snapshot: app.snapshot!,
              tasks: tasks,
              preferences: preferences,
              now: clock(),
            )
          : <PlannedReminder>[];
      await _clearReminders();
      int id = 1;
      for (final reminder in reminders) {
        if (!active()) return;
        await plugin.zonedSchedule(
          id: id++,
          title: '喵伴 · 今日约定',
          body: preferences['lock_screen_details'] == true
              ? reminder.title
              : '留一点时间，完成和 TA 的小约定。',
          scheduledDate: reminder.at,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminders',
              '每日约定提醒',
              channelDescription: '你接受的任务时间提醒',
              importance: Importance.defaultImportance,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: jsonEncode({
            'kind': 'task_reminder',
            'account_id': app.uid,
            'space_id': app.sid,
            'task_id': reminder.taskId,
          }),
        );
      }
      if (active()) _lastScheduleKey = key;
    });
    _scheduleTail = work.catchError((Object _) {});
    return work;
  }
}
