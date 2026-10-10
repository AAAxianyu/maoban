import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/controller.dart';
import 'package:miaoban/app/theme.dart';
import 'package:miaoban/core/api.dart';
import 'package:miaoban/core/store.dart';
import 'package:miaoban/features/tasks/today_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets(
    'long task at 360px and 1.3 text has visible accessible check-in',
    (tester) async {
      final db = (await tester.runAsync(
        () => databaseFactory.openDatabase(inMemoryDatabasePath),
      ))!;
      final app = AppController(Api(), LocalStore(db));
      app.user = {
        'id': 'alice',
        'preferences': {'reduce_motion': true},
      };
      app.sid = 'test-room';
      app.snapshot = {
        'space': {'today': '2026-10-08'},
        'wallet': {'available': 35, 'debt': 0},
        'growth': {'level': 1, 'permanent_xp': 3},
        'daily': {
          'plans': <dynamic>[],
          'instances': [
            {
              'id': 'test-task',
              'user_id': 'alice',
              'title': '学习三十个六级新词并复习之前容易混淆的词汇',
              'standard': '使用自己的学习工具完成今天的练习',
              'tag': 'cet6',
              'points': 10,
              'required': true,
              'completed': false,
              'version': 0,
              'note': '',
            },
          ],
        },
      };
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 740),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(body: TodayScreen(app)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('学习三十个六级新词并复习之前容易混淆的词汇'), findsOneWidget);
      expect(find.byTooltip('完成打卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await tester.runAsync(() => db.close());
    },
  );
}
