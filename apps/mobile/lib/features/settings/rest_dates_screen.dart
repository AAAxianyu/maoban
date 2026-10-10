import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

class RestDatesScreen extends StatefulWidget {
  final AppController app;
  const RestDatesScreen(this.app, {super.key});
  @override
  State<RestDatesScreen> createState() => _RestDatesScreenState();
}

class _RestDatesScreenState extends State<RestDatesScreen> {
  Future<void> add() async {
    final tomorrow = DateTime.parse(widget.app.today)
        .add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: tomorrow,
      firstDate: tomorrow,
      lastDate: tomorrow.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    await attempt(context, success: '已设为休息日', () async {
      await widget.app.command('${widget.app.root}/rest-dates', {
        'date': dateKey(date),
        'rest': true,
      });
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final dates =
        (app.snapshot?['rest_dates'] as List? ?? [])
            .where(
              (r) =>
                  r['user_id'] == app.uid &&
                  (r['date'] as String).compareTo(app.today) > 0,
            )
            .toList()
          ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    return Scaffold(
      appBar: AppBar(title: const Text('未来休息日')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '按小屋时区设置自己的休息日。只影响未来日期；已开始的一天和历史约定保留。休息日不生成必做任务，也不发全勤奖励。',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('添加休息日'),
            ),
            const SizedBox(height: 16),
            if (dates.isEmpty)
              const EmptyState('还没有未来休息日', '提前留出休息时间，让约定更容易坚持。'),
            for (final r in dates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.weekend_outlined),
                title: Text(formatDay('${r['date']}')),
                trailing: TextButton(
                  onPressed: () => attempt(context, () async {
                    await app.command('${app.root}/rest-dates', {
                      'date': r['date'],
                      'rest': false,
                    });
                    if (mounted) setState(() {});
                  }),
                  child: const Text('恢复学习日'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
