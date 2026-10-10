import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/widgets.dart';

class RewardEditor extends StatefulWidget {
  final AppController app;
  final Map<String, dynamic>? initial;
  const RewardEditor(this.app, {super.key, this.initial});
  @override
  State<RewardEditor> createState() => _RewardEditorState();
}

class _RewardEditorState extends State<RewardEditor> {
  final title = TextEditingController(),
      description = TextEditingController(),
      price = TextEditingController(text: '70'),
      stock = TextEditingController();
  final form = GlobalKey<FormState>();
  bool published = true, busy = false;
  String icon = 'gift';
  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      title.text = '${i['title'] ?? ''}';
      description.text = '${i['description'] ?? ''}';
      price.text = '${i['price'] ?? 70}';
      stock.text = i['stock'] == null ? '' : '${i['stock']}';
      published = i['published'] as bool? ?? true;
      icon = i['icon'] as String? ?? 'gift';
    }
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    price.dispose();
    stock.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final recipient =
        widget.initial?['recipient_id'] ??
        (widget.app.snapshot!['space']['members'] as List)
            .where((m) => m['id'] != widget.app.uid)
            .firstOrNull?['id'];
    if (recipient == null) {
      showMessage(context, '先邀请另一位成员加入小屋，再提供奖品');
      return;
    }
    setState(() => busy = true);
    await attempt(context, () async {
      final data = {
        'recipient_id': recipient,
        'title': title.text,
        'description': description.text,
        'price': int.parse(price.text),
        'stock': stock.text.isEmpty ? null : int.parse(stock.text),
        'published': published,
        'icon': icon,
      };
      final id = widget.initial?['id'];
      final result = id == null
          ? await widget.app.api.post('${widget.app.root}/rewards', data)
          : await widget.app.api.put('${widget.app.root}/rewards/$id', {
              ...data,
              'expected_version': widget.initial!['version'],
            });
      if (widget.initial?['wish_id'] != null) {
        await widget.app.api.post(
          '${widget.app.root}/wishes/${widget.initial!['wish_id']}/decision',
          {'accepted': true, 'reward_id': result['id']},
        );
      }
      await widget.app.sync();
      if (mounted) {
        showMessage(context, id == null ? '奖品已上架' : '奖品已保存');
        Navigator.pop(context);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initial?['id'] == null ? '提供一份奖品' : '编辑奖品'),
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: title,
              decoration: const InputDecoration(labelText: '奖品名称'),
              maxLength: 120,
              validator: (v) => v!.trim().isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: description,
              decoration: const InputDecoration(labelText: '描述与兑现说明'),
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              validator: (v) => v!.trim().isEmpty ? '写下如何兑现' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '价格（小鱼干）'),
              validator: (v) {
                final n = int.tryParse(v!);
                return n == null || n < 1 || n > 100000
                    ? '请输入 1–100000 的整数'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '可兑换库存（空白为不限）'),
              validator: (v) {
                if (v!.isEmpty) return null;
                final n = int.tryParse(v);
                return n == null || n < 0 || n > 10000
                    ? '请输入 0–10000 的整数'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: icon,
              decoration: const InputDecoration(labelText: '预设图标'),
              items: const [
                DropdownMenuItem(value: 'gift', child: Text('礼物')),
                DropdownMenuItem(value: 'drink', child: Text('饮料')),
                DropdownMenuItem(value: 'movie', child: Text('电影')),
                DropdownMenuItem(value: 'meal', child: Text('美食')),
                DropdownMenuItem(value: 'date', child: Text('约会')),
              ],
              onChanged: (v) => setState(() => icon = v!),
            ),
            SwitchListTile.adaptive(
              title: const Text('上架可兑换'),
              value: published,
              onChanged: (v) => setState(() => published = v),
            ),
            const Text('由你负责兑现，只有另一位成员可以兑换。修改商品不会改变已有订单的价格与说明。'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? '保存中…' : '保存奖品'),
            ),
          ],
        ),
      ),
    ),
  );
}
