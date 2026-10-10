import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/app/theme.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:miaoban/features/tasks/today_screen.dart';
import 'package:sqflite/sqflite.dart';

Map<String, dynamic> emptyDay() => {
  'plans': <dynamic>[],
  'instances': <dynamic>[],
};

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryApi extends Api {
  final Future<Map<String, dynamic>> Function(String) load;
  _HistoryApi(this.load);

  @override
  Future<Map<String, dynamic>> getMap(String path) =>
      load(Uri.parse(path).queryParameters['day']!);
}

class _App extends AppController {
  _App(Api api) : super(api, LocalStore(_UnusedDatabase())) {
    user = {
      'id': 'alice',
      'preferences': {'reduce_motion': true},
    };
    sid = 'test-room';
    snapshot = {
      'space': {'today': '2026-10-09'},
      'wallet': {'available': 0},
      'daily': emptyDay(),
      'growth': {'level': 1, 'permanent_xp': 0},
    };
  }

  @override
  Future<void> sync() async {}
}

Future<void> _showToday(WidgetTester tester, _App app) async {
  addTearDown(app.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: TodayScreen(app)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chooseDay(WidgetTester tester, int day) async {
  await tester.ensureVisible(find.byTooltip('查看其他日期'));
  await tester.tap(find.byTooltip('查看其他日期'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('$day').last);
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
}

void main() {
  for (final fails in [false, true]) {
    testWidgets(
      'returning to today ignores a delayed history ${fails ? 'error' : 'response'}',
      (tester) async {
        final waiting = Completer<Map<String, dynamic>>();
        var loads = 0;
        final requestedDays = <String>[];
        final app = _App(
          _HistoryApi((day) {
            requestedDays.add(day);
            return ++loads == 1 ? Future.value(emptyDay()) : waiting.future;
          }),
        );
        await _showToday(tester, app);
        await _chooseDay(tester, 8);
        expect(find.text('10月8日的约定'), findsOneWidget);

        unawaited(
          tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh(),
        );
        await tester.pump();
        expect(loads, 2);
        expect(requestedDays, ['2026-10-08', '2026-10-08']);
        await tester.tap(find.byTooltip('回到今日'));
        await tester.pump();
        expect(find.text('今日约定'), findsOneWidget);

        if (fails) {
          waiting.completeError(StateError('Abandoned history request'));
        } else {
          waiting.complete(emptyDay());
        }
        await tester.pumpAndSettle();
        expect(find.text('今日约定'), findsOneWidget);
        expect(find.text('10月8日的约定'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('an older response cannot replace the latest chosen date', (
    tester,
  ) async {
    final waiting = Completer<Map<String, dynamic>>();
    final app = _App(
      _HistoryApi(
        (day) =>
            day == '2026-10-08' ? waiting.future : Future.value(emptyDay()),
      ),
    );
    await _showToday(tester, app);
    await _chooseDay(tester, 8);
    await _chooseDay(tester, 7);
    expect(find.text('10月7日的约定'), findsOneWidget);
    waiting.complete(emptyDay());
    await tester.pumpAndSettle();
    expect(find.text('10月7日的约定'), findsOneWidget);
    expect(find.text('10月8日的约定'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a current history request still reports its error', (
    tester,
  ) async {
    final app = _App(
      _HistoryApi(
        (_) => Future.error(StateError('Current history request failed')),
      ),
    );
    await _showToday(tester, app);
    await _chooseDay(tester, 8);
    expect(find.text('今日约定'), findsOneWidget);
    expect(find.text('Current history request failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
