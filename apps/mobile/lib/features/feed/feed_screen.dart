import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

String eventTitle(String type) =>
    {
      'checkin.completed': '完成了一项约定',
      'checkin.reversed': '更正了一次打卡',
      'task.proposed': '提出新的约定',
      'task.accepted': '接受了约定',
      'task.rejected': '拒绝了约定',
      'member.joined': '加入了小屋',
      'interaction.reaction': '送来一份鼓励',
      'interaction.nudge': '轻轻提醒了一下',
      'order.redeemed': '兑换了一份奖品',
      'order.fulfill': '兑现了一份奖品',
      'order.confirm': '确认收到奖品',
      'order.cancel': '取消了兑换',
      'milestone.rewarded': '获得了阶段奖励',
      'milestone.gift': '解锁了阶段赠品',
      'achievement.unlocked': '获得了新成就',
      'room.unlocked': '小屋解锁新装饰',
      'correction.requested': '申请补记或更正',
      'rules.proposed': '提议新的小屋规则',
    }[type] ??
    '更新了小屋记录';

class FeedScreen extends StatelessWidget {
  final AppController app;
  const FeedScreen(this.app, {super.key});

  static const _reactions = [
    ('hug', '抱抱', Icons.favorite_border),
    ('high_five', '击掌', Icons.back_hand_outlined),
    ('paw', '爪印', Icons.pets),
  ];

  Future<void> _react(
    BuildContext context,
    dynamic e,
    String kind,
    VoidCallback reload,
  ) async {
    var message = '';
    if (kind == 'message') {
      final input = await textPrompt(
        context,
        '给 TA 留一句话',
        maxLength: 200,
        action: '发送',
      );
      if (input == null || input.trim().isEmpty || !context.mounted) return;
      message = input.trim();
    }
    await attempt(context, success: '已送出', () async {
      await app.command('${app.root}/events/${e['id']}/reactions', {
        'kind': kind,
        'message': message,
      });
      reload();
    });
  }

  @override
  Widget build(BuildContext context) => RemoteList(
    title: '彼此的动态',
    // The events API pages oldest-first by sequence, so read every page and
    // show the newest first; the list itself renders lazily.
    load: () async {
      final all = <dynamic>[];
      var cursor = 0;
      while (true) {
        final page = await app.api.getList(
          '${app.root}/events?after_seq=$cursor',
        );
        all.addAll(page);
        if (page.length < 100) break;
        cursor = page.last['seq'] as int;
      }
      return all.reversed.toList();
    },
    emptyTitle: '还没有动态',
    emptyMessage: '完成一次打卡，彼此的进展会出现在这里。',
    item: (context, e, reload) {
      final mine = e['actor_id'] == app.uid;
      final message = e['data'] is Map ? e['data']['message'] : null;
      return Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${mine ? '我' : 'TA'}${eventTitle('${e['type']}')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message is String && message.isNotEmpty) Text(message),
            Meta(formatTime(e['created_at'])),
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final (kind, label, icon) in _reactions)
                      Tooltip(
                        message: '送一个$label',
                        child: ActionChip(
                          avatar: Icon(icon, size: 18),
                          label: Text(label),
                          onPressed: () => _react(context, e, kind, reload),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('留言'),
                      onPressed: () => _react(context, e, 'message', reload),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
