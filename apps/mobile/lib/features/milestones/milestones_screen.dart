import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../core/domain.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

class MilestonesScreen extends StatelessWidget {
  final AppController app;
  const MilestonesScreen(this.app, {super.key});

  Future<void> _command(
    BuildContext context,
    String path,
    Map<String, dynamic> body,
    VoidCallback reload,
  ) => attempt(context, () async {
    await app.command('${app.root}/milestones/$path', body);
    reload();
  });

  @override
  Widget build(BuildContext context) => RemoteList(
    title: '阶段目标',
    load: () async => await app.api.all('${app.root}/milestones'),
    emptyTitle: '还没有阶段目标',
    emptyMessage: '约定一个一段时间内的目标，达成后获得奖励。',
    action: FloatingActionButton.extended(
      onPressed: () => context.push('/milestone-editor'),
      icon: const Icon(Icons.add),
      label: const Text('新目标'),
    ),
    item: (context, g, reload) {
      final id = g['id'];
      final evidence = '${g['evidence'] ?? ''}';
      final manual = g['status'] == 'accepted' && g['metric'] == 'manual';
      final canDecide = g['status'] == 'pending' && g['proposer_id'] != app.uid;
      final canSubmit =
          manual &&
          g['executor_id'] == app.uid &&
          g['manual_confirmed'] != true;
      final canConfirm =
          manual && g['approver_id'] == app.uid && evidence.isNotEmpty;
      Future<void> submitEvidence() async {
        final text = await textPrompt(
          context,
          '提交完成证据',
          initial: evidence,
          action: '提交',
        );
        if (text == null || !context.mounted) return;
        await _command(context, '$id/evidence', {
          'evidence': text,
          'expected_version': g['version'],
        }, reload);
      }

      final rawTarget = g['target'], rawProgress = g['progress'];
      final target = rawTarget is num && rawTarget > 0 ? rawTarget : 1;
      final progress = (rawProgress is num ? rawProgress : 0) / target;
      return Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${g['title']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${g['standard']}'),
            const SizedBox(height: 8),
            if (g['metric'] != 'manual') ...[
              LinearProgressIndicator(
                value: progress.clamp(0, 1).toDouble(),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 4),
            ],
            Meta(
              '${formatDay('${g['starts_on']}')} – ${formatDay('${g['ends_on']}')} · '
              '${g['metric'] == 'manual' ? '由另一人确认' : '进度 ${g['progress']}/${g['target']}'}',
            ),
            Meta(
              g['reward_points'] == null
                  ? '阶段赠品：${g['gift_title']}'
                  : '阶段奖励：${g['reward_points']} 小鱼干',
            ),
            Meta(statusLabel('milestone', g['status'])),
            if (evidence.isNotEmpty) Text('证据：$evidence'),
            CardActions(
              primary: canDecide
                  ? FilledButton(
                      onPressed: () => _command(context, '$id/decision', {
                        'accepted': true,
                      }, reload),
                      child: const Text('接受目标'),
                    )
                  : canConfirm
                  ? FilledButton(
                      onPressed: () => _command(context, '$id/confirm', {
                        'accepted': true,
                      }, reload),
                      child: const Text('确认达成'),
                    )
                  : canSubmit
                  ? FilledButton.tonal(
                      onPressed: submitEvidence,
                      child: Text(evidence.isEmpty ? '提交证据' : '更新证据'),
                    )
                  : null,
              more: [
                if (canDecide)
                  (
                    '拒绝目标',
                    () => _command(context, '$id/decision', {
                      'accepted': false,
                    }, reload),
                  ),
                if (canConfirm)
                  (
                    '未达成／更正',
                    () => _command(context, '$id/confirm', {
                      'accepted': false,
                    }, reload),
                  ),
                if (g['status'] == 'accepted')
                  (
                    '提议修改目标',
                    () => context.push(
                      '/milestone-editor',
                      extra: Map<String, dynamic>.from(g as Map),
                    ),
                  ),
                ('查看版本与审批', () => context.push('/milestones/$id/versions')),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class MilestoneEditor extends StatefulWidget {
  final AppController app;
  final Map<String, dynamic>? initial;
  const MilestoneEditor(this.app, {this.initial, super.key});
  @override
  State<MilestoneEditor> createState() => _MilestoneEditorState();
}

class _MilestoneEditorState extends State<MilestoneEditor> {
  final title = TextEditingController(),
      standard = TextEditingController(),
      target = TextEditingController(text: '10'),
      points = TextEditingController(text: '30'),
      gift = TextEditingController();
  final form = GlobalKey<FormState>();
  String metric = 'tasks', tag = 'c';
  String? executor;
  bool physical = false, busy = false;
  late DateTime start, end;
  @override
  void initState() {
    super.initState();
    start = DateTime.parse(widget.app.today);
    end = start.add(const Duration(days: 30));
    executor = widget.app.uid;
    final g = widget.initial;
    if (g != null) {
      title.text = '${g['title'] ?? ''}';
      standard.text = '${g['standard'] ?? ''}';
      target.text = '${g['target']}';
      metric = g['metric'] as String? ?? 'tasks';
      tag = g['tag'] as String? ?? 'all';
      executor = g['executor_id'] as String?;
      physical = g['reward_points'] == null;
      points.text = '${g['reward_points'] ?? 30}';
      gift.text = '${g['gift_title'] ?? ''}';
      final priorEnd = DateTime.parse(g['ends_on'] as String);
      if (!priorEnd.isBefore(start)) end = priorEnd;
    }
  }

  @override
  void dispose() {
    title.dispose();
    standard.dispose();
    target.dispose();
    points.dispose();
    gift.dispose();
    super.dispose();
  }

  Future<void> date(bool finish) async {
    final result = await showDatePicker(
      context: context,
      initialDate: finish ? end : start,
      firstDate: DateTime.parse(widget.app.today),
      lastDate: start.add(const Duration(days: 730)),
    );
    if (result != null) {
      setState(() {
        if (finish) {
          end = result;
        } else {
          start = result;
        }
      });
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (end.isBefore(start)) {
      showMessage(context, '结束日期不能早于开始日期');
      return;
    }
    setState(() => busy = true);
    await attempt(context, success: '目标已提议，等待 TA 接受', () async {
      final path = widget.initial == null
          ? '${widget.app.root}/milestones'
          : '${widget.app.root}/milestones/${widget.initial!['id']}/versions';
      await widget.app.command(path, {
        'executor_id': executor,
        'title': title.text,
        'standard': standard.text,
        'metric': metric,
        'tag': tag == 'all' ? null : tag,
        'target': metric == 'manual' ? 1 : int.parse(target.text),
        'starts_on': dateKey(start),
        'ends_on': dateKey(end),
        'reward_points': physical ? null : int.parse(points.text),
        'gift_title': physical ? gift.text : null,
      });
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initial == null ? '约定一个阶段目标' : '提议修改阶段目标'),
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: title,
              decoration: const InputDecoration(labelText: '目标名称'),
              maxLength: 120,
              validator: (v) => v!.trim().isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: standard,
              decoration: const InputDecoration(labelText: '完成标准'),
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              validator: (v) => v!.trim().isEmpty ? '写下完成标准' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: executor,
              decoration: const InputDecoration(labelText: '执行人'),
              items: [
                for (final m in widget.app.data?.members ?? const <Member>[])
                  DropdownMenuItem<String>(
                    value: m.id,
                    child: Text(m.nickname),
                  ),
              ],
              onChanged: widget.initial == null ? (v) => executor = v : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: metric,
              decoration: const InputDecoration(labelText: '确认方式'),
              items: const [
                DropdownMenuItem(value: 'tasks', child: Text('累计有效任务数')),
                DropdownMenuItem(value: 'days', child: Text('累计有效学习天数')),
                DropdownMenuItem(value: 'manual', child: Text('由另一人确认')),
              ],
              onChanged: (v) => setState(() => metric = v!),
            ),
            if (metric != 'manual') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '目标数量'),
                validator: (v) => int.tryParse(v!) == null || int.parse(v) < 1
                    ? '请输入正整数'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: tag,
                decoration: const InputDecoration(labelText: '累计类别'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全部')),
                  for (final e in taskTags.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => tag = v!),
              ),
            ],
            const SizedBox(height: 16),
            _DateRow(
              start: formatDay(dateKey(start)),
              end: formatDay(dateKey(end)),
              onStart: () => date(false),
              onEnd: () => date(true),
            ),
            SwitchListTile.adaptive(
              title: const Text('奖励为实物／陪伴'),
              value: physical,
              onChanged: widget.initial == null
                  ? (v) => setState(() => physical = v)
                  : null,
            ),
            if (physical)
              TextFormField(
                controller: gift,
                decoration: const InputDecoration(labelText: '提供者承诺的阶段赠品'),
                maxLength: 120,
                validator: (v) => v!.trim().isEmpty ? '请输入赠品' : null,
              )
            else
              TextFormField(
                controller: points,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '阶段小鱼干（1–10000）'),
                validator: (v) {
                  final n = int.tryParse(v!);
                  return n == null || n < 1 || n > 10000
                      ? '请输入 1–10000 的整数'
                      : null;
                },
              ),
            const SizedBox(height: 16),
            const Text('双方接受后才生效。阶段实物奖励不消耗商城库存，不再次扣分；奖励只按本目标有效额度发放。'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? '提交中…' : '提议目标'),
            ),
          ],
        ),
      ),
    ),
  );
}

class MilestoneVersionsScreen extends StatelessWidget {
  final AppController app;
  final String id;
  const MilestoneVersionsScreen(this.app, this.id, {super.key});
  @override
  Widget build(BuildContext context) => RemoteList(
    title: '阶段目标版本',
    load: () async => await app.api.all('${app.root}/milestones/$id/versions'),
    emptyTitle: '还没有版本记录',
    item: (context, v, reload) => Paper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '版本 ${v['version']} · ${v['data']['title']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('${v['data']['standard']}'),
          Meta(
            '${formatDay('${v['data']['starts_on']}')} – ${formatDay('${v['data']['ends_on']}')} · 目标 ${v['data']['target']}',
          ),
          Meta(
            v['status'] == 'pending'
                ? '等待接受；原约定继续有效'
                : statusLabel('proposal', v['status']),
          ),
          if (v['rejection_reason'] != null)
            Text('原因：${v['rejection_reason']}'),
          if (v['status'] == 'pending' && v['approver_id'] == app.uid)
            Wrap(
              spacing: 8,
              children: [
                for (final accept in [true, false])
                  OutlinedButton(
                    onPressed: () => attempt(context, () async {
                      String? reason;
                      if (!accept) {
                        reason = await textPrompt(context, '拒绝原因（可留空）');
                        if (reason == null) return;
                      } else if (!await confirm(
                        context,
                        '接受新目标版本？',
                        '新标准会重新计算阶段奖励。更正会记入流水；已经兑现的赠品保留交付事实。',
                        action: '接受修改',
                      )) {
                        return;
                      }
                      await app.command(
                        '${app.root}/milestone-versions/${v['id']}/decision',
                        {'accepted': accept, 'reason': reason ?? ''},
                      );
                      reload();
                    }),
                    child: Text(accept ? '接受修改' : '拒绝修改'),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _DateRow extends StatelessWidget {
  final String start, end;
  final VoidCallback onStart, onEnd;
  const _DateRow({
    required this.start,
    required this.end,
    required this.onStart,
    required this.onEnd,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.event_outlined),
          label: Text('开始 $start'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onEnd,
          icon: const Icon(Icons.event_available_outlined),
          label: Text('结束 $end'),
        ),
      ),
    ],
  );
}
