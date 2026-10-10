import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/controller.dart';
import '../../core/widgets.dart';
import '../notifications/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  final AppController app;
  final NotificationService notifications;
  const SettingsScreen(this.app, this.notifications, {super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final nickname = TextEditingController();
  final form = GlobalKey<FormState>();
  Map<String, dynamic> values = {};
  bool busy = false, dirty = false;
  @override
  void initState() {
    super.initState();
    final u = widget.app.user!;
    nickname.text = '${u['nickname'] ?? ''}';
    nickname.addListener(_changed);
    values = {
      'quiet_start': '22:00',
      'quiet_end': '08:00',
      'avatar': u['avatar'],
      'reduce_motion': false,
      'checkins': true,
      'interactions': true,
      'rewards': true,
      'reminders': true,
      'gentle_nudges': true,
      'lock_screen_details': false,
      ...Map<String, dynamic>.from(u['preferences'] as Map? ?? const {}),
    };
  }

  void _changed() {
    if (!dirty) setState(() => dirty = true);
  }

  void _set(String key, Object? value) => setState(() {
    values[key] = value;
    dirty = true;
  });

  @override
  void dispose() {
    nickname.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    final saved = await attempt(context, success: '设置已保存', () async {
      await widget.app.api.put('/preferences', {
        ...values,
        'nickname': nickname.text.trim(),
      });
      await widget.app.reloadUser();
      await widget.notifications.schedule(widget.app);
    });
    if (!mounted) return;
    setState(() {
      busy = false;
      if (saved) dirty = false;
    });
    if (saved && mounted) Navigator.pop(context);
  }

  Future<void> export() async => attempt(context, () async {
    final data = await widget.app.api.get('${widget.app.root}/export');
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/miaoban-export-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: '喵伴授权空间数据导出'),
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  });
  Future<void> logout() async {
    bool keep = false;
    if (widget.app.pending.isNotEmpty) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('还有未同步操作'),
          content: const Text('可留在本机等待同一账号再次登录；其他账号无法读取或发送这些操作。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('继续使用'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('放弃并退出'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('保留并退出'),
            ),
          ],
        ),
      );
      if (result == null) return;
      keep = result == 'keep';
    } else if (!await confirm(context, '退出账号？', '本机会清除账号缓存和通知，重新登录后恢复服务器记录。')) {
      return;
    }
    if (!mounted) return;
    await attempt(context, () async {
      await widget.app.logout(keepQueue: keep);
      await widget.notifications.cancel();
      if (mounted) {
        dirty = false;
        context.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await confirm(
            context,
            '放弃未保存的修改？',
            '离开后，这次对昵称和通知设置的修改不会保存。',
            action: '放弃修改',
          ) &&
          mounted) {
        setState(() => dirty = false);
        Navigator.pop(this.context);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('账号与设置'),
        actions: [
          if (dirty)
            TextButton(onPressed: busy ? null : save, child: const Text('保存')),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: nickname,
                decoration: const InputDecoration(labelText: '昵称'),
                maxLength: 40,
                validator: (v) => (v ?? '').trim().isEmpty ? '昵称不能为空' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: values['avatar'] as String?,
                decoration: const InputDecoration(labelText: '猫咪形象'),
                items: const [
                  DropdownMenuItem(value: 'ginger', child: Text('奶油橘猫')),
                  DropdownMenuItem(value: 'gray', child: Text('灰白猫')),
                ],
                onChanged: (v) => _set('avatar', v),
              ),
              const SizedBox(height: 24),
              Text('通知与提醒', style: Theme.of(context).textTheme.titleLarge),
              for (final e in {
                'checkins': 'TA的打卡动态',
                'interactions': '鼓励与留言',
                'rewards': '奖励与阶段进度',
                'reminders': '本地约定提醒',
                'gentle_nudges': '允许轻轻提醒',
                'lock_screen_details': '锁屏显示简短学习详情',
                'reduce_motion': '减少猫咪动态效果',
              }.entries)
                SwitchListTile.adaptive(
                  title: Text(e.value),
                  value: values[e.key] == true,
                  onChanged: (v) => _set(e.key, v),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClockField(
                      label: '免打扰开始',
                      value: values['quiet_start'] as String?,
                      onChanged: (v) => _set('quiet_start', v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClockField(
                      label: '免打扰结束',
                      value: values['quiet_end'] as String?,
                      onChanged: (v) => _set('quiet_end', v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => attempt(context, () async {
                  if (!await confirm(
                    context,
                    '允许喵伴提醒你？',
                    '用于约定时间提醒和 TA 的动态；拒绝后仍可打卡，所有消息仍在收件箱。',
                    action: '请求系统权限',
                  )) {
                    return;
                  }
                  final allowed = await widget.notifications.request(
                    widget.app,
                  );
                  await widget.notifications.schedule(widget.app);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          allowed
                              ? widget.notifications.registrationError ??
                                    '通知权限已授予'
                              : '系统未授予通知权限，主要功能仍可用',
                        ),
                      ),
                    );
                  }
                }),
                child: const Text('查看／申请系统通知权限'),
              ),
              const Meta('系统通知被拒绝时，前台同步和收件箱仍可正常使用。免打扰时段按小屋时区计算。'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? '正在保存…' : '保存设置'),
              ),
              const Divider(),
              OutlinedButton.icon(
                onPressed: () => context.push('/rest-dates'),
                icon: const Icon(Icons.weekend_outlined),
                label: const Text('安排未来休息日'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: export,
                icon: const Icon(Icons.download),
                label: const Text('导出授权空间数据'),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: logout, child: const Text('退出登录')),
            ],
          ),
        ),
      ),
    ),
  );
}
