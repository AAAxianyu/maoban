import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/widgets.dart';
import '../growth/room_scene.dart';

class BindingScreen extends StatefulWidget {
  final AppController app;
  const BindingScreen(this.app, {super.key});
  @override
  State<BindingScreen> createState() => _BindingScreenState();
}

class _BindingScreenState extends State<BindingScreen> {
  final name = TextEditingController(text: '我们的自习室');
  final invite = TextEditingController();
  String zone = 'Asia/Shanghai';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    invite.dispose();
    super.dispose();
  }

  Future<void> submit(bool create) async {
    if (create && name.text.trim().isEmpty) {
      return showMessage(context, '给小屋起个名字吧');
    }
    if (!create && invite.text.trim().isEmpty) {
      return showMessage(context, '请粘贴 TA 发来的邀请码');
    }
    setState(() => busy = true);
    await attempt(context, () async {
      await widget.app.api.post(
        create ? '/spaces' : '/invitations/claim',
        create
            ? {'name': name.text.trim(), 'timezone': zone}
            : {'token': invite.text.trim()},
      );
      await widget.app.reloadUser();
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('为两只猫安个家')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const RoomScene(height: 180),
          const SizedBox(height: 24),
          Text('创建我们的小屋', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '小屋名称'),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy
                ? null
                : () async {
                    final picked = await pickTimezone(context, current: zone);
                    if (picked != null) setState(() => zone = picked);
                  },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '小屋时区',
                suffixIcon: Icon(Icons.public),
              ),
              child: Text(zone),
            ),
          ),
          const SizedBox(height: 8),
          const Meta('日程与全勤以这个时区的零点为界，创建后修改需双方确认。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : () => submit(true),
            child: const Text('确认时区并创建'),
          ),
          const Divider(),
          Text('加入对方的小屋', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: invite,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '一次性邀请码'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : () => submit(false),
            child: const Text('加入小屋'),
          ),
        ],
      ),
    ),
  );
}
