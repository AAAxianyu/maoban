import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

class LedgerScreen extends StatelessWidget {
  final AppController app;
  const LedgerScreen(this.app, {super.key});
  @override
  Widget build(BuildContext context) => RemoteList(
    title: '小鱼干流水',
    // The ledger API pages oldest-first, so read all pages and show newest first.
    load: () async {
      final all = <dynamic>[];
      var offset = 0;
      while (true) {
        final page = await app.api.getList(
          '${app.root}/ledger?offset=$offset&limit=100',
        );
        all.addAll(page);
        if (page.length < 100) break;
        offset += 100;
      }
      return all.reversed.toList();
    },
    emptyTitle: '还没有流水',
    emptyMessage: '完成约定获得的小鱼干和兑换支出会记录在这里。',
    item: (context, e, reload) {
      final delta = e['delta'] is num ? e['delta'] as num : 0;
      return Paper(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e['reason']}'),
                  Meta(
                    '${formatTime(e['created_at'])} · 余额 ${e['balance_after']}',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${delta > 0 ? '+' : ''}$delta',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: delta > 0
                    ? context.colors.success
                    : delta < 0
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ],
        ),
      );
    },
  );
}
