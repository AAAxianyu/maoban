import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/domain.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../growth/pixel_sprite.dart';
import '../growth/room_scene.dart';

class RoomScreen extends StatelessWidget {
  final AppController app;
  const RoomScreen(this.app, {super.key});

  Future<void> invite(BuildContext context) => attempt(context, () async {
    final result = await app.command('${app.root}/invitations');
    if (!context.mounted) return;
    final token = '${result['token'] ?? ''}';
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('邀请 TA 加入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('一次性邀请，48 小时有效。TA 可在激活页用此码创建独立账号，也可登录后加入。'),
            const SizedBox(height: 16),
            Paper(
              padding: const EdgeInsets.all(12),
              child: SelectableText(token.isEmpty ? '请重新创建邀请' : token),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final revoked = await attempt(
                dialog,
                success: '邀请已撤销',
                () => app.command(
                  '${app.root}/invitations/${result['id']}/revoke',
                ),
              );
              if (revoked && dialog.mounted) Navigator.pop(dialog);
            },
            child: const Text('撤销邀请'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: token.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: token));
                    if (dialog.mounted) showMessage(dialog, '邀请码已复制');
                  },
            child: const Text('复制邀请码'),
          ),
        ],
      ),
    );
  });

  @override
  Widget build(BuildContext context) => Select(
    listenable: app,
    select: () => [app.snapshot?['growth'], app.snapshot?['space'], app.user],
    builder: _build,
  );

  Widget _build(BuildContext context) {
    final data = app.data;
    if (data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final growth = data.growth;
    final members = data.members;
    final xp = growth.permanentXp;
    final progress = keepsakeProgress(xp);
    final decorations = growth.decorations;
    return ListView(
      key: const PageStorageKey('room'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        RoomScene(
          height: 240,
          decorations: decorations,
          pose: app.pose,
          reduceMotion:
              (app.user?['preferences']?['reduce_motion'] ?? false) == true ||
              MediaQuery.of(context).disableAnimations,
        ),
        const SizedBox(height: 24),
        Text(data.spaceName, style: theme.textTheme.titleLarge),
        Meta(members.map((m) => m.nickname).join(' 与 ')),
        const SizedBox(height: 12),
        Text('Lv.${growth.level} · $xp 点永久纪念经验'),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress.fraction,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          color: context.colors.success,
          backgroundColor: context.colors.line,
        ),
        const SizedBox(height: 4),
        Meta(
          progress.next == null
              ? '全部纪念装饰已解锁'
              : '还差 ${progress.remaining} 点经验解锁下一件纪念',
        ),
        const SizedBox(height: 12),
        const Text('每个任务日期实例首次有效完成，给小屋留下一点纪念。撤销不让装饰倒退；成长页的有效学习统计会按更正后的事实变化。'),
        if (members.length < 2) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => invite(context),
            icon: const Icon(Icons.person_add),
            label: const Text('邀请另一只猫'),
          ),
        ] else ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => attempt(
              context,
              success: '已轻轻提醒 TA',
              () => app.command('${app.root}/nudge'),
            ),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('轻轻提醒 TA（每天一次）'),
          ),
        ],
        const SizedBox(height: 24),
        Text('一起解锁的纪念', style: theme.textTheme.titleLarge),
        for (final keepsake in roomKeepsakes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: decorations.contains(keepsake.id)
                ? PixelSprite(keepsake.sprite)
                : const SizedBox(width: 48, child: Icon(Icons.lock_outline)),
            title: Text(keepsake.name),
            subtitle: Text(
              decorations.contains(keepsake.id)
                  ? '已永久解锁'
                  : '${keepsake.xp} 经验解锁',
            ),
          ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.forum_outlined),
          title: const Text('小屋留言与动态'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/feed'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.public),
          title: const Text('小屋时区与全勤约定'),
          subtitle: data.timezone.isEmpty ? null : Text(data.timezone),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/rules'),
        ),
      ],
    );
  }
}

class RulesScreen extends StatefulWidget {
  final AppController app;
  const RulesScreen(this.app, {super.key});
  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final _list = GlobalKey<RemoteListState>();
  AppController get app => widget.app;

  Future<void> propose(BuildContext context) => attempt(context, () async {
    final zone = await pickTimezone(context, current: app.data?.timezone);
    if (zone == null || !context.mounted) return;
    final points = await textPrompt(
      context,
      '全勤奖励（0–100 小鱼干）',
      initial: '5',
      maxLength: 3,
      action: '提议',
    );
    if (points == null) return;
    final n = int.tryParse(points.trim());
    if (n == null || n < 0 || n > 100) {
      throw const UserMessage('请输入 0–100 的整数');
    }
    await app.command('${app.root}/rules', {
      'timezone': zone,
      'attendance_points': n,
      'effective_date': nextDateKey(app.today),
    });
    await _list.currentState?.reload();
    if (context.mounted) showMessage(context, '新规则已提交，等待 TA 确认');
  });

  @override
  Widget build(BuildContext context) => RemoteList(
    key: _list,
    title: '小屋规则',
    load: () async => (await app.api.get(app.root))['rules'] as List,
    emptyTitle: '还没有规则记录',
    emptyMessage: '提议新的时区或全勤奖励，双方确认后次日生效。',
    action: FloatingActionButton.extended(
      onPressed: () => propose(context),
      icon: const Icon(Icons.add),
      label: const Text('提议新规则'),
    ),
    item: (context, r, reload) => Paper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r['timezone']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '全勤 ${r['attendance_points']} 小鱼干 · ${formatDay('${r['effective_date']}')} 生效',
          ),
          Meta(statusLabel('rule', r['status'])),
          if (r['status'] == 'pending' && r['proposer_id'] != app.uid)
            CardActions(
              primary: FilledButton(
                onPressed: () => _decide(context, r, true, reload),
                child: const Text('接受规则'),
              ),
              more: [('拒绝', () => _decide(context, r, false, reload))],
            ),
        ],
      ),
    ),
  );

  Future<void> _decide(
    BuildContext context,
    dynamic r,
    bool accept,
    VoidCallback reload,
  ) => attempt(context, () async {
    await app.command('${app.root}/rules/${r['id']}/decision', {
      'accepted': accept,
    });
    reload();
  });
}
