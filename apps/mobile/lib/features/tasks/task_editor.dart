import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/domain.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

class TaskEditor extends StatefulWidget {
  final AppController app;
  final Map<String, dynamic>? task;
  const TaskEditor(this.app, {super.key, this.task});
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final standard = TextEditingController();
  final points = TextEditingController(text: '10');
  String? reminder;
  String? executor;
  String tag = 'study';
  late DateTime start;
  DateTime? end;
  Set<int> weekdays = {1, 2, 3, 4, 5, 6, 7};
  bool required = true, busy = false;
  @override
  void initState() {
    super.initState();
    start = DateTime.parse(widget.app.today).add(const Duration(days: 1));
    executor = widget.app.uid;
    if (widget.task != null) {
      final t = widget.task!['task'];
      final v = (widget.task!['versions'] as List).last;
      title.text = '${v['title'] ?? ''}';
      standard.text = '${v['standard'] ?? ''}';
      points.text = '${v['points'] ?? 10}';
      tag = v['tag'] as String? ?? 'study';
      required = v['required'] == true;
      executor = t['executor_id'] as String?;
      weekdays = (v['weekdays'] as List? ?? const []).cast<int>().toSet();
      reminder = v['reminder'] as String?;
    }
  }

  @override
  void dispose() {
    title.dispose();
    standard.dispose();
    points.dispose();
    super.dispose();
  }

  Future<void> date(bool isEnd) async {
    final value = await showDatePicker(
      context: context,
      initialDate: isEnd ? (end ?? start) : start,
      firstDate: DateTime.parse(widget.app.today),
      lastDate: start.add(const Duration(days: 730)),
    );
    if (value != null) {
      setState(() {
        if (isEnd) {
          end = value;
        } else {
          start = value;
        }
      });
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (weekdays.isEmpty) {
      showMessage(context, '至少选择一个重复星期');
      return;
    }
    if (end != null && end!.isBefore(start)) {
      showMessage(context, '结束日期不能早于开始日期');
      return;
    }
    setState(() => busy = true);
    await attempt(context, success: '约定已发出', () async {
      await widget.app.command(
        widget.task == null
            ? '${widget.app.root}/tasks'
            : '${widget.app.root}/tasks/${widget.task!['task']['id']}/versions',
        {
          'executor_id': executor,
          'title': title.text,
          'standard': standard.text,
          'points': int.parse(points.text),
          'tag': tag,
          'required': required,
          'weekdays': weekdays.toList()..sort(),
          'starts_on': dateKey(start),
          'ends_on': end == null ? null : dateKey(end!),
          'reminder': reminder,
        },
      );
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.task == null ? '新的每日约定' : '提议新版本')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: title,
              decoration: const InputDecoration(labelText: '约定名称'),
              maxLength: 120,
              validator: (v) => v!.trim().isEmpty ? '请输入约定名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: standard,
              decoration: const InputDecoration(labelText: '完成标准'),
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              validator: (v) => v!.trim().isEmpty ? '写下怎样算完成' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: executor,
              decoration: const InputDecoration(labelText: '谁来完成'),
              items: [
                for (final m in widget.app.data?.members ?? const <Member>[])
                  DropdownMenuItem<String>(
                    value: m.id,
                    child: Text(m.nickname),
                  ),
              ],
              onChanged: widget.task == null
                  ? (v) => setState(() => executor = v)
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: tag,
              decoration: const InputDecoration(labelText: '学习类别'),
              items: [
                for (final e in taskTags.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => tag = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: points,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '小鱼干奖励（0–1000）'),
              validator: (v) {
                final n = int.tryParse(v!);
                return n == null || n < 0 || n > 1000 ? '请输入 0–1000 的整数' : null;
              },
            ),
            SwitchListTile.adaptive(
              title: const Text('每日必做'),
              subtitle: const Text('当天新约定为选做，次日起进入必做集合。'),
              value: required,
              onChanged: (v) => setState(() => required = v),
            ),
            const SizedBox(height: 8),
            Text('重复星期', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int n = 1; n <= 7; n++)
                  FilterChip(
                    label: Text('周${weekdayNames[n - 1]}'),
                    selected: weekdays.contains(n),
                    onSelected: (v) => setState(() {
                      v ? weekdays.add(n) : weekdays.remove(n);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => date(false),
                    icon: const Icon(Icons.event_outlined),
                    label: Text('开始 ${formatDay(dateKey(start))}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => date(true),
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(
                      end == null ? '不设结束' : '结束 ${formatDay(dateKey(end!))}',
                    ),
                  ),
                ),
                if (end != null)
                  IconButton(
                    tooltip: '移除结束日期',
                    onPressed: () => setState(() => end = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Meta('一次性任务将开始与结束设为同一天，并勾选当天星期。'),
            const SizedBox(height: 16),
            ClockField(
              label: '本地提醒（选填）',
              value: reminder,
              clearable: true,
              onChanged: (v) => setState(() => reminder = v),
            ),
            const SizedBox(height: 16),
            const Meta('有积分的自建任务需对方接受；给对方的提议需执行人接受。新版本被接受前，旧版本继续有效。'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? '正在保存…' : '发出约定'),
            ),
          ],
        ),
      ),
    ),
  );
}
