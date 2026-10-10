import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/controller.dart';
import 'app/theme.dart';
import 'core/api.dart';
import 'core/domain.dart';
import 'core/pixel_glyph.dart';
import 'core/store.dart';
import 'core/widgets.dart';
import 'features/auth/auth_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/growth/growth_screen.dart';
import 'features/milestones/milestones_screen.dart';
import 'features/notifications/inbox_screen.dart';
import 'features/notifications/notification_service.dart';
import 'features/rewards/reward_editor.dart';
import 'features/rewards/rewards_screen.dart';
import 'features/settings/rest_dates_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/space/binding_screen.dart';
import 'features/space/room_screen.dart';
import 'features/tasks/manage_tasks.dart';
import 'features/tasks/task_editor.dart';
import 'features/tasks/today_screen.dart';
import 'features/wallet/ledger_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  final controller = AppController(Api(), store);
  final notifications = NotificationService();
  await notifications.init();
  runApp(
    ProviderScope(
      overrides: [appProvider.overrideWithValue(controller)],
      child: MiaobanApp(controller, notifications),
    ),
  );
  await controller.init();
  controller.changed();
}

class MiaobanApp extends StatefulWidget {
  final AppController app;
  final NotificationService notifications;
  const MiaobanApp(this.app, this.notifications, {super.key});
  @override
  State<MiaobanApp> createState() => _MiaobanAppState();
}

class _MiaobanAppState extends State<MiaobanApp> with WidgetsBindingObserver {
  late GoRouter router;
  StreamSubscription<Map<String, dynamic>>? taps;
  Map<String, dynamic>? _pendingTap;
  bool _routingTap = false;

  bool get _ready {
    final app = widget.app;
    return !app.initializing &&
        app.user != null &&
        !app.needsLogin &&
        app.sid != null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final app = widget.app;
    GoRoute page(String path, Widget Function(GoRouterState) build) =>
        GoRoute(path: path, builder: (context, state) => build(state));
    StatefulShellBranch tab(String path, Widget Function() build) =>
        StatefulShellBranch(routes: [page(path, (_) => build())]);
    router = GoRouter(
      refreshListenable: app,
      redirect: (context, state) {
        final path = state.uri.path;
        if (!_ready) return path == '/' ? null : '/';
        return path == '/' ? '/today' : null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ListenableBuilder(
            listenable: app,
            builder: (context, _) => app.initializing
                ? const _StartupScreen()
                : app.user == null || app.needsLogin
                ? AuthScreen(app)
                : BindingScreen(app),
          ),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => HomeScreen(app, shell),
          branches: [
            tab('/today', () => TodayScreen(app)),
            tab('/room', () => RoomScreen(app)),
            tab('/rewards', () => RewardsScreen(app)),
            tab('/growth', () => GrowthScreen(app)),
          ],
        ),
        page('/rest-dates', (_) => RestDatesScreen(app)),
        page(
          '/task-editor',
          (s) => TaskEditor(app, task: s.extra as Map<String, dynamic>?),
        ),
        page('/tasks', (_) => ManageTasks(app)),
        page('/corrections', (_) => CorrectionsScreen(app)),
        page('/feed', (_) => FeedScreen(app)),
        page('/rules', (_) => RulesScreen(app)),
        page('/ledger', (_) => LedgerScreen(app)),
        page(
          '/reward-editor',
          (s) => RewardEditor(app, initial: s.extra as Map<String, dynamic>?),
        ),
        page('/orders', (_) => OrdersScreen(app)),
        page('/wishes', (_) => WishesScreen(app)),
        page('/milestones', (_) => MilestonesScreen(app)),
        page(
          '/milestone-editor',
          (s) =>
              MilestoneEditor(app, initial: s.extra as Map<String, dynamic>?),
        ),
        page(
          '/milestones/:id/versions',
          (s) => MilestoneVersionsScreen(app, s.pathParameters['id']!),
        ),
        page('/notifications', (_) => InboxScreen(app)),
        page(
          '/settings',
          (_) => app.user == null
              ? AuthScreen(app)
              : SettingsScreen(app, widget.notifications),
        ),
      ],
    );
    taps = widget.notifications.taps.stream.listen((payload) {
      _pendingTap = payload;
      unawaited(_routePendingTap());
    });
    if (widget.notifications.initialTaps.isNotEmpty) {
      _pendingTap = widget.notifications.initialTaps.last;
      widget.notifications.initialTaps.clear();
    }
    app.addListener(_updateNotifications);
  }

  Future<void> _routePendingTap() async {
    final app = widget.app;
    if (_routingTap ||
        app.initializing ||
        _pendingTap == null ||
        app.user == null ||
        app.needsLogin ||
        app.snapshot == null) {
      return;
    }
    _routingTap = true;
    final payload = _pendingTap!;
    _pendingTap = null;
    try {
      final uid = app.uid, session = app.api.sessionGeneration;
      if (payload['space_id'] != app.sid ||
          (payload['account_id'] != null && payload['account_id'] != uid)) {
        return;
      }
      await app.sync();
      if (app.needsLogin ||
          !mounted ||
          app.uid != uid ||
          app.api.sessionGeneration != session) {
        return;
      }
      final nid = payload['notification_id'];
      if (nid != null) {
        // Look up this authorized ID even when the inbox contains more than one page.
        final n = await app.api.get('/notifications/$nid');
        await app.api.post('/notifications/$nid/read');
        final type = n['event']['type'] as String;
        if (!mounted) return;
        unawaited(router.push(routeForEvent(type)));
      } else {
        router.go('/today');
      }
    } catch (_) {
      if (mounted) unawaited(router.push('/notifications'));
    } finally {
      _routingTap = false;
    }
  }

  void _updateNotifications() {
    if (widget.app.initializing) return;
    unawaited(_routePendingTap());
    unawaited(
      widget.notifications.register(widget.app).catchError((Object _) {}),
    );
    unawaited(
      widget.notifications.schedule(widget.app).catchError((Object _) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        () async {
          // Resume first: a failing permission check must not leave sync paused.
          await widget.app.resume();
          await widget.notifications.refreshPermission();
          _updateNotifications();
        }().catchError((Object _) {}),
      );
    } else if (state == AppLifecycleState.paused) {
      widget.app.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(_updateNotifications);
    taps?.cancel();
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '喵伴',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    darkTheme: appDarkTheme(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: router,
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelGlyph('paw', size: 48),
              const SizedBox(height: 24),
              Semantics(liveRegion: true, child: const Text('正在恢复账号与小屋…')),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  final AppController app;
  final StatefulNavigationShell shell;
  const HomeScreen(this.app, this.shell, {super.key});

  static const _titles = ['喵伴 · 今日', '我们的小屋', '奖励铺', '一起成长'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_titles[shell.currentIndex]),
      actions: [
        IconButton(
          onPressed: () => context.push('/notifications'),
          icon: const Icon(Icons.notifications_none),
          tooltip: '通知收件箱',
        ),
        IconButton(
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.account_circle_outlined),
          tooltip: '账号与设置',
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (path) => context.push(path),
          itemBuilder: (context) => const [
            PopupMenuItem(value: '/tasks', child: Text('管理约定')),
            PopupMenuItem(value: '/corrections', child: Text('补记与更正')),
            PopupMenuItem(value: '/rest-dates', child: Text('安排休息日')),
            PopupMenuItem(value: '/feed', child: Text('彼此的动态')),
            PopupMenuItem(value: '/ledger', child: Text('小鱼干流水')),
          ],
        ),
      ],
    ),
    body: SafeArea(
      child: Select(
        listenable: app,
        select: () => [app.error, app.offline, app.snapshot == null],
        builder: (context) => Column(
          children: [
            if (app.error != null)
              StatusBanner(
                offline: app.offline,
                message: app.error!,
                onRetry: app.sync,
              ),
            Expanded(
              child: app.snapshot == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('正在打开我们的小屋…'),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: app.sync,
                            child: const Text('重新连接'),
                          ),
                        ],
                      ),
                    )
                  : shell,
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (n) =>
          shell.goBranch(n, initialLocation: n == shell.currentIndex),
      destinations: const [
        NavigationDestination(icon: PixelGlyph('today'), label: '今日'),
        NavigationDestination(icon: PixelGlyph('room'), label: '小屋'),
        NavigationDestination(icon: PixelGlyph('gift'), label: '奖励'),
        NavigationDestination(icon: PixelGlyph('growth'), label: '成长'),
      ],
    ),
  );
}
