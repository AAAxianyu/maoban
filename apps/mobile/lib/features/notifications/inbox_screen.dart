import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/domain.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../feed/feed_screen.dart';

class InboxScreen extends StatelessWidget {
  final AppController app;
  const InboxScreen(this.app, {super.key});
  static const _pageSize = 50;
  @override
  Widget build(BuildContext context) => RemoteList(
    title: '通知收件箱',
    pageSize: _pageSize,
    loadPage: (offset) =>
        app.api.getList('/notifications?offset=$offset&limit=$_pageSize'),
    emptyTitle: '收件箱是空的',
    emptyMessage: 'TA 的打卡、鼓励和奖励进度会出现在这里。',
    item: (context, n, reload) {
      final unread = n['read'] != true;
      final type = '${n['event']?['type']}';
      return Paper(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Badge(
            isLabelVisible: unread,
            smallSize: 8,
            child: Icon(
              unread ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
              color: unread ? null : context.colors.secondaryInk,
            ),
          ),
          title: Text(
            'TA${eventTitle(type)}',
            style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
          subtitle: Text(formatTime(n['created_at'])),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => attempt(context, () async {
            if (unread) {
              await app.api.post('/notifications/${n['id']}/read');
              unawaited(app.sync());
            }
            if (!context.mounted) return;
            await context.push(routeForEvent(type));
            reload();
          }),
        ),
      );
    },
  );
}
