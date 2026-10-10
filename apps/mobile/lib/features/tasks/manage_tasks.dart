import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../core/domain.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

class ManageTasks extends StatelessWidget {
  final AppController app;
  const ManageTasks(this.app, {super.key});

  Future<void> _decide(
    BuildContext context,
    dynamic version,
    bool accepted,
    VoidCallback reload,
  ) async {
    String? reason;
    if (!accepted) {
      reason = await textPrompt(context, '拒绝说明', maxLength: 200, action: '拒绝');
      if (reason == null || !context.mounted) return;
    }
    await attempt(context, () async {
      await app.command('${app.root}/task-versions/${version['id']}/decision', {
        'accepted': accepted,
        'reason': ?reason,
      });
      reload();
    });
  }

  Future<void> _schedule(
    BuildContext context,
    dynamic record,
    String state,
    VoidCallback reload,
  ) => attempt(context, success: '明天起生效', () async {
    await app.command('${app.root}/tasks/${record['task']['id']}/schedule', {
      'state': state,
      'effective_date': nextDateKey(app.today),
    });
    reload();
  });

  @override
  Widget build(BuildContext context) => RemoteList(
    title: '约定与版本',
    load: () async => await app.api.all('${app.root}/tasks'),
    emptyTitle: '还没有约定',
    emptyMessage: '添加一件每天都能坚持的小事。',
    action: FloatingActionButton.extended(
      onPressed: () => context.push('/task-editor'),
      icon: const Icon(Icons.add),
      label: const Text('新约定'),
    ),
    item: (context, record, reload) {
      final versions = (record['versions'] as List? ?? const []);
      // Pending or rejected proposals are listed below, not shown as current.
      final current =
          versions.lastWhere(
            (v) => (v as Map)['status'] == 'accepted',
            orElse: () => null,
          ) ??
          versions.lastOrNull;
      final executor = app.data?.members
          .where((m) => m.id == record['task']?['executor_id'])
          .firstOrNull;
      return Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current != null) ...[
              Text(
                '${current['title']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${current['standard']}'),
              Meta(
                [
                  ?executor?.nickname,
                  taskTags[current['tag']] ?? '学习',
                  '${current['points']} 小鱼干',
                  if (current['reminder'] != null) '${current['reminder']} 提醒',
                ].join(' · '),
              ),
            ],
            for (final v in versions) ...[
              const Divider(height: 16),
              Text(
                '第 ${v['version']} 版 · ${statusLabel('proposal', v['status'])}',
              ),
              if (v != current) Meta('${v['title']} · ${v['points']} 小鱼干'),
              if (v['rejection_reason'] != null &&
                  '${v['rejection_reason']}'.isNotEmpty)
                Meta('拒绝说明：${v['rejection_reason']}'),
              if (v['status'] == 'pending' && v['proposer_id'] != app.uid)
                CardActions(
                  primary: FilledButton(
                    onPressed: () => _decide(context, v, true, reload),
                    child: const Text('接受约定'),
                  ),
                  more: [('拒绝', () => _decide(context, v, false, reload))],
                ),
            ],
            CardActions(
              more: [
                (
                  '提议新版本',
                  () => context.push(
                    '/task-editor',
                    extra: Map<String, dynamic>.from(record as Map),
                  ),
                ),
                ('明日起暂停', () => _schedule(context, record, 'paused', reload)),
                ('明日起恢复', () => _schedule(context, record, 'active', reload)),
                ('明日起归档', () => _schedule(context, record, 'archived', reload)),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class CorrectionsScreen extends StatelessWidget {
  final AppController app;
  const CorrectionsScreen(this.app, {super.key});
  @override
  Widget build(BuildContext context) => RemoteList(
    title: '补记与更正',
    load: () async => await app.api.all('${app.root}/corrections'),
    emptyTitle: '没有补记或更正申请',
    emptyMessage: '在今日页切换到过去的日期，即可申请补记或撤销。',
    item: (context, c, reload) {
      Future<void> decide(bool accepted) => attempt(context, () async {
        await app.command('${app.root}/corrections/${c['id']}/decision', {
          'accepted': accepted,
        });
        reload();
      });
      return Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c['requester_id'] == app.uid ? '我' : 'TA'}${c['desired_state'] == true ? '申请补记完成' : '申请撤销历史记录'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${c['reason']}'),
            Meta(
              '${statusLabel('correction', c['status'])} · ${formatTime(c['created_at'])}',
            ),
            if (c['status'] == 'pending' && c['requester_id'] != app.uid)
              CardActions(
                primary: FilledButton(
                  onPressed: () => decide(true),
                  child: const Text('同意更正'),
                ),
                more: [('拒绝', () => decide(false))],
              ),
          ],
        ),
      );
    },
  );
}
