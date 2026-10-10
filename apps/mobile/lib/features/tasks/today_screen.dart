import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/domain.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/pixel_glyph.dart';
import '../../core/widgets.dart';
import '../feed/feed_screen.dart';
import '../growth/room_scene.dart';

class TodayScreen extends StatefulWidget {
  final AppController app;
  const TodayScreen(this.app, {super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool mine = true;
  String? selectedDate;
  Map<String, dynamic>? history;
  final submitting = <String>{};
  int _historyGeneration = 0;

  Future<void> _loadHistory(String day) async {
    final generation = ++_historyGeneration;
    try {
      final response = await widget.app.api.getMap(
        '${widget.app.root}/daily?day=$day',
      );
      if (!mounted || generation != _historyGeneration) return;
      setState(() {
        selectedDate = day;
        history = response;
      });
    } catch (_) {
      if (!mounted || generation != _historyGeneration) return;
      rethrow;
    }
  }

  Future<void> chooseDate() async {
    final today = DateTime.parse(widget.app.today);
    final value = await showDatePicker(
      context: context,
      initialDate: selectedDate == null ? today : DateTime.parse(selectedDate!),
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
      helpText: '查看哪一天的约定',
    );
    if (value == null || !mounted) return;
    final day = dateKey(value);
    if (day == widget.app.today) return backToToday();
    await attempt(context, () => _loadHistory(day));
  }

  void backToToday() {
    // Invalidate requests for dates the user has left, even if still in flight.
    _historyGeneration++;
    setState(() {
      selectedDate = null;
      history = null;
    });
  }

  Future<void> toggle(TaskInstance i) async {
    final app = widget.app;
    if (i.completed &&
        !await confirm(
          context,
          '撤销这次打卡？',
          '将回收 ${i.points} 小鱼干，以及不再满足的全勤和阶段积分。已花掉的部分会成为待抵扣额。小屋纪念经验保留。',
          action: '确认撤销',
        )) {
      return;
    }
    if (!mounted) return;
    if (i.date.isNotEmpty && i.date != app.today) {
      final reason = await textPrompt(
        context,
        i.completed ? '申请撤销这天的记录' : '申请补记这天的完成',
        action: '提交申请',
      );
      if (reason == null || reason.trim().isEmpty || !mounted) return;
      setState(() => submitting.add(i.id));
      await attempt(context, success: '已提交，等待 TA 确认', () async {
        await app.command('${app.root}/instances/${i.id}/corrections', {
          'desired_state': !i.completed,
          'expected_version': i.version,
          'reason': reason,
        });
        if (selectedDate != null) await _loadHistory(selectedDate!);
      });
      if (mounted) setState(() => submitting.remove(i.id));
      return;
    }
    // Queued immediately; the card shows the new state while sync runs.
    await attempt(context, () => app.checkin(i.raw, !i.completed));
  }

  Future<void> note(TaskInstance i) async {
    final value = await textPrompt(context, '学习笔记', initial: i.note);
    if (value == null || !mounted) return;
    await attempt(context, () async {
      await widget.app.command('${widget.app.root}/instances/${i.id}/note', {
        'note': value,
        'expected_version': i.version,
      });
      if (selectedDate != null) await _loadHistory(selectedDate!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Select(
      listenable: app,
      select: () => [
        app.snapshot?['daily'],
        app.snapshot?['wallet'],
        app.snapshot?['growth'],
        app.snapshot?['latest_partner_event'],
        app.today,
        app.pending,
        app.user,
      ],
      builder: (context) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final app = widget.app;
    final data = app.data;
    if (data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = context.colors;
    final daily = selectedDate == null
        ? data.daily
        : DailyPlan(history ?? const {});
    final all = daily.instances;
    final order = {for (var n = 0; n < all.length; n++) all[n].id: n};
    bool own(String user) => mine ? user == app.uid : user != app.uid;
    final shown = all.where((i) => own(i.userId)).toList()
      ..sort((a, b) {
        final state = (a.completed ? 1 : 0).compareTo(b.completed ? 1 : 0);
        if (state != 0) return state;
        final required = (a.required ? 0 : 1).compareTo(b.required ? 0 : 1);
        if (required != 0) return required;
        return order[a.id]!.compareTo(order[b.id]!);
      });
    final resting = daily.restingFor(own);
    final wallet = data.wallet;
    final growth = data.growth;
    final progress = keepsakeProgress(growth.permanentXp);
    final latest = data.latestPartnerEvent;
    final reduceMotion =
        (app.user?['preferences']?['reduce_motion'] ?? false) == true ||
        MediaQuery.of(context).disableAnimations;
    final compact = MediaQuery.sizeOf(context).height < 740;
    final done = shown.where((i) => i.completed).length;
    return RefreshIndicator(
      onRefresh: () async {
        await app.sync();
        if (selectedDate != null && mounted) {
          await attempt(this.context, () => _loadHistory(selectedDate!));
        }
      },
      child: ListView(
        key: const PageStorageKey('today'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          RoomScene(
            height: compact ? 120 : 190,
            pose: app.pose,
            reduceMotion: reduceMotion,
            decorations: growth.decorations,
          ),
          const SizedBox(height: 12),
          Semantics(
            label: progress.next == null
                ? '小屋全部纪念已解锁'
                : '小屋 ${growth.permanentXp} 点永久经验，还差 ${progress.remaining} 点解锁下一件纪念',
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: colors.success,
                backgroundColor: colors.line,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Meta(
                  'Lv.${growth.level} · ${progress.next == null ? '全部纪念已解锁' : '还差 ${progress.remaining} 点解锁下一件纪念'}',
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/ledger'),
                icon: const PixelGlyph('fish', size: 18),
                label: Text('${wallet.available} 小鱼干'),
              ),
            ],
          ),
          if (wallet.debt > 0)
            Meta(
              '待抵扣 ${wallet.debt} 小鱼干：后续收入会先用于抵扣。',
              color: theme.colorScheme.error,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedDate == null
                      ? '今日约定'
                      : '${formatDay(selectedDate!)}的约定',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (selectedDate != null)
                IconButton(
                  onPressed: backToToday,
                  tooltip: '回到今日',
                  icon: const Icon(Icons.today),
                ),
              IconButton(
                onPressed: chooseDate,
                tooltip: '查看其他日期',
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ],
          ),
          if (shown.isNotEmpty)
            Meta(
              selectedDate == null
                  ? '已完成 $done / ${shown.length}'
                  : '历史记录的修改需要另一位成员确认',
            ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('我的')),
              ButtonSegment(value: false, label: Text('TA的')),
            ],
            selected: {mine},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => mine = s.first),
          ),
          const SizedBox(height: 16),
          if (resting) const EmptyState('今天是休息日', '好好休息，也是约定的一部分。'),
          if (shown.isEmpty && !resting)
            EmptyState(
              mine ? '还没有约定' : 'TA 这天没有约定',
              mine ? '从一件容易坚持的小事开始。' : '可以给 TA 提一个小约定。',
              action: selectedDate == null
                  ? OutlinedButton(
                      onPressed: () => context.push('/task-editor'),
                      child: const Text('添加约定'),
                    )
                  : null,
            ),
          for (final i in shown) ...[
            _TaskCard(
              instance: i,
              mine: mine,
              queued: app.pending
                  .where((q) => q['instance'] == i.id)
                  .firstOrNull,
              submitting: submitting.contains(i.id),
              onToggle: () => toggle(i),
              onNote: () => note(i),
              onRetry: (id) => attempt(context, () => app.retryOperation(id)),
              onDiscard: (id) async {
                if (!await confirm(
                  context,
                  '使用服务器记录？',
                  '放弃本机这条同步失败的操作，不修改服务器记录。之后可按最新记录重新打卡。',
                )) {
                  return;
                }
                if (!context.mounted) return;
                await attempt(context, () => app.discardFailedOperation(id));
              },
            ),
            const SizedBox(height: 12),
          ],
          if (shown.isNotEmpty && selectedDate == null && mine)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/task-editor'),
                icon: const Icon(Icons.add),
                label: const Text('添加约定'),
              ),
            ),
          const SizedBox(height: 12),
          Paper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TA的最新动态', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  latest == null
                      ? 'TA还没有新动态，先约定一件小事吧。'
                      : 'TA${eventTitle('${latest['type']}')}',
                  style: theme.textTheme.bodyLarge,
                ),
                if (latest?['created_at'] != null)
                  Meta(formatTime(latest!['created_at'])),
                CardActions(
                  primary: latest == null
                      ? null
                      : FilledButton.tonalIcon(
                          icon: const PixelGlyph('paw', size: 20),
                          label: const Text('送个爪印'),
                          onPressed: () => attempt(
                            context,
                            success: '爪印已送达',
                            () => app.command(
                              '${app.root}/events/${latest['id']}/reactions',
                              {'kind': 'paw', 'message': ''},
                            ),
                          ),
                        ),
                  more: [('查看全部动态', () => context.push('/feed'))],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskInstance instance;
  final bool mine, submitting;
  final Map<String, Object?>? queued;
  final VoidCallback onToggle, onNote;
  final void Function(String id) onRetry, onDiscard;
  const _TaskCard({
    required this.instance,
    required this.mine,
    required this.queued,
    required this.submitting,
    required this.onToggle,
    required this.onNote,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final i = instance;
    final colors = context.colors;
    final failed = queued?['status'] == 'failed';
    final syncing = queued != null && !failed;
    // A queued check-in is shown as already done; sync confirms it shortly.
    final completed = syncing ? queued!['desired'] == 1 : i.completed;
    final (status, statusColor) = failed
        ? ('同步失败：${queued!['error']}', Theme.of(context).colorScheme.error)
        : syncing
        ? (completed ? '已记录 · 正在同步，小鱼干稍后入账' : '已撤销 · 正在同步', colors.secondaryInk)
        : completed
        ? ('已完成 · +${i.points} 小鱼干', colors.success)
        : ('+${i.points} 小鱼干 · ${i.required ? '必做' : '选做'}', colors.ink);
    return Paper(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 12),
            child: PixelGlyph(taskGlyph(i.tag), color: colors.success),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(i.standard),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (mine)
                  TextButton(
                    onPressed: onNote,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(i.note.isEmpty ? '添加笔记' : '查看笔记'),
                  ),
                if (failed)
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => onRetry(queued!['id'] as String),
                        child: const Text('重试同步'),
                      ),
                      TextButton(
                        onPressed: () => onDiscard(queued!['id'] as String),
                        child: const Text('使用服务器记录'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (mine)
            IconButton.filledTonal(
              onPressed: submitting || queued != null ? null : onToggle,
              icon: submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      completed ? Icons.check : Icons.check_box_outline_blank,
                    ),
              tooltip: syncing
                  ? '正在同步'
                  : completed
                  ? '撤销打卡'
                  : '完成打卡',
            )
          else
            Semantics(
              label: completed ? '已完成' : '未完成',
              child: Icon(
                completed ? Icons.check_circle : Icons.circle_outlined,
                color: completed ? colors.success : colors.secondaryInk,
              ),
            ),
        ],
      ),
    );
  }
}
