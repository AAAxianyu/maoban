import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/domain.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import 'pixel_sprite.dart';

class GrowthScreen extends StatefulWidget {
  final AppController app;
  const GrowthScreen(this.app, {super.key});
  @override
  State<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends State<GrowthScreen> {
  DateTime? selectedMonth;
  String? selectedUser;

  @override
  Widget build(BuildContext context) => Select(
    listenable: widget.app,
    select: () => [
      widget.app.snapshot?['growth'],
      widget.app.snapshot?['space'],
      widget.app.uid,
    ],
    builder: _build,
  );

  Widget _build(BuildContext context) {
    final app = widget.app;
    final data = app.data;
    if (data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = context.colors;
    final members = data.members;
    final user = members.any((m) => m.id == selectedUser)
        ? selectedUser!
        : app.uid;
    final growth = data.growth;
    final stats = growth.statsFor(user);
    final days = growth.calendarFor(user);
    final owned = growth.achievementsFor(user);
    final today = DateTime.parse(app.today);
    final month = selectedMonth ?? DateTime(today.year, today.month);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;
    final activeDays = [
      for (var n = 1; n <= count; n++)
        if (days.contains(dateKey(DateTime(month.year, month.month, n)))) n,
    ].length;
    return ListView(
      key: const PageStorageKey('growth'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (members.length > 1) ...[
          SegmentedButton<String>(
            segments: [
              for (final m in members)
                ButtonSegment<String>(
                  value: m.id,
                  label: Text(m.id == app.uid ? '我的' : 'TA的'),
                ),
            ],
            selected: {user},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => selectedUser = v.first),
          ),
          const SizedBox(height: 16),
        ],
        Text('每一步，都算数', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (label, value) in [
              ('有效完成', stats['effective_completions'] ?? 0),
              ('学习天数', stats['effective_days'] ?? 0),
              ('C 练习', stats['c_completions'] ?? 0),
            ]) ...[
              Expanded(
                child: Paper(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  child: Column(
                    children: [
                      Text('$value', style: theme.textTheme.titleLarge),
                      Meta(label),
                    ],
                  ),
                ),
              ),
              if (label != 'C 练习') const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            IconButton(
              tooltip: '上一个月',
              onPressed: () => setState(
                () => selectedMonth = DateTime(month.year, month.month - 1),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${month.year} 年 ${month.month} 月',
                    style: theme.textTheme.titleMedium,
                  ),
                  Meta('学习 $activeDays 天'),
                ],
              ),
            ),
            IconButton(
              tooltip: '下一个月',
              onPressed: isCurrentMonth
                  ? null
                  : () => setState(
                      () =>
                          selectedMonth = DateTime(month.year, month.month + 1),
                    ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final name in weekdayNames)
              Center(child: FittedBox(child: Meta(name))),
            for (var n = 1; n < month.weekday; n++) const SizedBox(),
            for (var n = 1; n <= count; n++)
              Builder(
                builder: (context) {
                  final date = dateKey(DateTime(month.year, month.month, n));
                  final active = days.contains(date);
                  final isToday = date == app.today;
                  return Semantics(
                    label: '${month.month}月$n日 ${active ? '有有效学习记录' : '无有效完成'}',
                    excludeSemantics: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: active ? colors.success : colors.paper,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(color: colors.ink, width: 2)
                            : Border.all(color: colors.line),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(4),
                      child: FittedBox(
                        child: Text(
                          '$n',
                          style: TextStyle(
                            color: active ? colors.onSuccess : colors.ink,
                            fontWeight: isToday ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => context.push('/milestones'),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('阶段目标与奖励'),
        ),
        const SizedBox(height: 24),
        Text('成就册', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final e in growth.achievementDefinitions.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                owned.contains(e.key) && achievementSprites.containsKey(e.key)
                ? PixelSprite(achievementSprites[e.key]!)
                : SizedBox(
                    width: 48,
                    child: Icon(
                      owned.contains(e.key)
                          ? Icons.emoji_events_outlined
                          : Icons.lock_outline,
                      color: colors.secondaryInk,
                    ),
                  ),
            title: Text(e.value),
            subtitle: Text(owned.contains(e.key) ? '纪念徽章已解锁' : '继续一点点积累'),
          ),
        const SizedBox(height: 16),
        const Meta('徽章保留获得时的纪念。上方学习统计和日历只计算当前有效完成，撤销或历史更正会反映在统计中。'),
      ],
    );
  }
}
