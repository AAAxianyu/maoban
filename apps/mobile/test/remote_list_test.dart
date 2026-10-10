import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/app/theme.dart';
import 'package:miaoban/core/widgets.dart';

List<Map<String, dynamic>> rows(String prefix, int count) => [
  for (var i = 0; i < count; i++) {'id': '$prefix-$i'},
];

Future<void> nearListEnd(WidgetTester tester) async {
  final context = tester.element(find.byType(ListView));
  ScrollUpdateNotification(
    metrics: FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 1000,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    ),
    context: context,
  ).dispatch(context);
  await tester.pump();
}

Future<void> showList(
  WidgetTester tester,
  GlobalKey<RemoteListState> key,
  Future<List<dynamic>> Function(int) load,
) => tester.pumpWidget(
  MaterialApp(
    theme: appTheme(),
    home: RemoteList(
      key: key,
      title: '通知收件箱',
      pageSize: 2,
      loadPage: load,
      item: (_, dynamic row, _) =>
          SizedBox(height: 350, child: Text((row as Map)['id'] as String)),
    ),
  ),
);

List<String> loadedIds(GlobalKey<RemoteListState> key) => key
    .currentState!
    .items!
    .map((dynamic row) => (row as Map)['id'] as String)
    .toList();

void main() {
  testWidgets('duplicate pages do not hide older notifications', (
    tester,
  ) async {
    final key = GlobalKey<RemoteListState>();
    var server = rows('old', 4);
    final offsets = <int>[];
    await showList(tester, key, (offset) async {
      offsets.add(offset);
      return server.skip(offset).take(2).toList();
    });
    await tester.pump();
    server = [...rows('new', 2), ...server];

    await nearListEnd(tester);
    expect(loadedIds(key), ['old-0', 'old-1']);
    await nearListEnd(tester);
    expect(loadedIds(key), ['old-0', 'old-1', 'old-2', 'old-3']);
    await nearListEnd(tester);
    expect(offsets, [0, 2, 4, 6]);
    expect(key.currentState!.exhausted, isTrue);
    await nearListEnd(tester);
    expect(offsets, [0, 2, 4, 6]);
  });

  testWidgets('refresh resets paging and discards an older page', (
    tester,
  ) async {
    final key = GlobalKey<RemoteListState>();
    final stalePage = Completer<List<dynamic>>();
    final refreshedPage = Completer<List<dynamic>>();
    final nextPage = Completer<List<dynamic>>();
    final offsets = <int>[];
    await showList(tester, key, (offset) {
      offsets.add(offset);
      return switch (offsets.length) {
        1 => Future.value(rows('old', 2)),
        2 => stalePage.future,
        3 => refreshedPage.future,
        4 => nextPage.future,
        _ => throw StateError('Unexpected page request'),
      };
    });
    await tester.pump();
    await nearListEnd(tester);
    unawaited(key.currentState!.reload());
    await tester.pump();
    await nearListEnd(tester);
    expect(offsets, [0, 2, 0]);

    refreshedPage.complete(rows('fresh', 2));
    await tester.pump();
    await nearListEnd(tester);
    expect(offsets, [0, 2, 0, 2]);

    stalePage.complete([
      {'id': 'old-2'},
    ]);
    await tester.pump();
    await nearListEnd(tester);
    expect(offsets, [0, 2, 0, 2]);
    expect(loadedIds(key), ['fresh-0', 'fresh-1']);

    nextPage.complete([
      {'id': 'fresh-2'},
    ]);
    await tester.pump();
    expect(loadedIds(key), ['fresh-0', 'fresh-1', 'fresh-2']);
    expect(key.currentState!.exhausted, isTrue);
  });

  testWidgets('failed next page retries without skipping notifications', (
    tester,
  ) async {
    final key = GlobalKey<RemoteListState>();
    final offsets = <int>[];
    await showList(tester, key, (offset) async {
      offsets.add(offset);
      if (offsets.length == 1) return rows('old', 2);
      if (offsets.length == 2) throw StateError('Test network failure');
      return [
        {'id': 'old-2'},
      ];
    });
    await tester.pump();
    await nearListEnd(tester);
    expect(loadedIds(key), ['old-0', 'old-1']);
    await nearListEnd(tester);
    expect(offsets, [0, 2, 2]);
    expect(loadedIds(key), ['old-0', 'old-1', 'old-2']);
  });
}
