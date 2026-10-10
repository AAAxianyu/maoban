import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/pixel_glyph.dart';
import '../../core/widgets.dart';

class RewardsScreen extends StatelessWidget {
  final AppController app;
  const RewardsScreen(this.app, {super.key});

  Future<void> redeem(BuildContext context, Reward r) async {
    if (!await confirm(
      context,
      '兑换「${r.title}」？',
      '将扣除 ${r.price} 小鱼干。兑换后由对方兑现，再由你确认收到。',
      action: '确认兑换',
    )) {
      return;
    }
    if (!context.mounted) return;
    await attempt(context, () async {
      await app.command('${app.root}/rewards/${r.id}/redeem', {
        'confirmed_price': r.price,
      });
      if (context.mounted) unawaited(context.push('/orders'));
    });
  }

  @override
  Widget build(BuildContext context) => Select(
    listenable: app,
    select: () => [app.snapshot?['rewards'], app.snapshot?['wallet'], app.uid],
    builder: _build,
  );

  Widget _build(BuildContext context) {
    final data = app.data;
    if (data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final items = data.rewards;
    final available = data.wallet.available;
    final forMe = items.where((r) => r.recipientId == app.uid).toList();
    final fromMe = items.where((r) => r.recipientId != app.uid).toList();
    return ListView(
      key: const PageStorageKey('rewards'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('把努力换成小小期待', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            const PixelGlyph('fish', size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '可用 $available 小鱼干',
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/ledger'),
              child: const Text('流水'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => context.push('/reward-editor'),
              icon: const Icon(Icons.add),
              label: const Text('提供奖品'),
            ),
            OutlinedButton(
              onPressed: () => context.push('/orders'),
              child: const Text('兑换记录'),
            ),
            OutlinedButton(
              onPressed: () => context.push('/wishes'),
              child: const Text('愿望清单'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (items.isEmpty) const EmptyState('奖励铺还没开张', '由你们亲自约定喜欢的奖品和兑现方式。'),
        if (forMe.isNotEmpty) ...[
          Text('我可以兑换', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final r in forMe) ...[
            _RewardCard(
              reward: r,
              action: _redeemButton(context, r, available),
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (fromMe.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('我提供的奖品', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final r in fromMe) ...[
            _RewardCard(
              reward: r,
              action: r.providerId == app.uid
                  ? OutlinedButton(
                      onPressed: () => context.push(
                        '/reward-editor',
                        extra: Map<String, dynamic>.from(r.raw),
                      ),
                      child: const Text('编辑与上下架'),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  Widget _redeemButton(BuildContext context, Reward r, int available) {
    final (label, enabled) = !r.published
        ? ('暂未上架', false)
        : r.stock == 0
        ? ('已兑完', false)
        : available < r.price
        ? ('还差 ${r.price - available} 小鱼干', false)
        : ('兑换奖品', true);
    return FilledButton(
      onPressed: enabled ? () => redeem(context, r) : null,
      child: Text(label),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final Reward reward;
  final Widget? action;
  const _RewardCard({required this.reward, this.action});
  @override
  Widget build(BuildContext context) {
    final r = reward;
    return Paper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PixelGlyph('gift'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  r.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${r.price} 小鱼干',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: context.colors.success),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.description),
          const SizedBox(height: 4),
          Meta(
            '${r.stock == null ? '不限库存' : '剩余 ${r.stock} 份'} · ${r.published ? '已上架' : '已下架'}',
          ),
          if (action != null) CardActions(primary: action),
        ],
      ),
    );
  }
}

class OrdersScreen extends StatelessWidget {
  final AppController app;
  const OrdersScreen(this.app, {super.key});
  @override
  Widget build(BuildContext context) => RemoteList(
    title: '兑换与兑现',
    load: () async => await app.api.all('${app.root}/orders'),
    emptyTitle: '还没有兑换记录',
    emptyMessage: '在奖励铺兑换奖品后，兑现进度会出现在这里。',
    item: (context, o, reload) {
      Future<void> command(String action) async {
        var reason = '';
        if (action.contains('cancel')) {
          if (!await confirm(
            context,
            '确认处理退款？',
            '${o['price']} 小鱼干将按原订单退款规则处理。已完成订单不能自行退款。',
          )) {
            return;
          }
          if (action == 'request_cancel' && context.mounted) {
            final input = await textPrompt(
              context,
              '退款原因',
              maxLength: 500,
              action: '提交',
            );
            if (input == null) return;
            reason = input;
          }
        }
        if (!context.mounted) return;
        await attempt(context, () async {
          await app.command('${app.root}/orders/${o['id']}/command', {
            'action': action,
            'expected_version': o['version'],
            'reason': reason,
          });
          reload();
        });
      }

      final status = o['status'];
      final mineToFulfil = o['provider_id'] == app.uid;
      final mineToReceive = o['recipient_id'] == app.uid;
      final cancelRequested = o['cancel_requested_by'] != null;
      final reviewCancel =
          cancelRequested && o['cancel_requested_by'] != app.uid;
      final Widget? primary = reviewCancel
          ? FilledButton(
              onPressed: () => command('approve_cancel'),
              child: const Text('同意退款'),
            )
          : status == 'pending' && mineToFulfil
          ? FilledButton(
              onPressed: () => command('fulfill'),
              child: const Text('标记已兑现'),
            )
          : status == 'fulfilled' && mineToReceive && !cancelRequested
          ? FilledButton(
              onPressed: () => command('confirm'),
              child: const Text('确认收到'),
            )
          : null;
      final more = <(String, VoidCallback)>[
        if (reviewCancel) ('拒绝退款', () => command('reject_cancel')),
        if (status == 'pending' && o['milestone_id'] == null)
          ('取消并退款', () => command('cancel')),
        if (status == 'fulfilled' && !cancelRequested)
          ('申请退款／未收到', () => command('request_cancel')),
      ];
      return Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${o['title']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ('${o['description'] ?? ''}'.isNotEmpty)
              Text('${o['description']}'),
            const SizedBox(height: 4),
            Text(
              o['milestone_id'] != null
                  ? '阶段赠品 · 不扣小鱼干'
                  : '兑换 ${o['price']} 小鱼干',
            ),
            Meta(
              [
                statusLabel('order', status),
                if (o['created_at'] != null) formatTime(o['created_at']),
              ].join(' · '),
            ),
            if (cancelRequested)
              Meta(
                o['cancel_requested_by'] == app.uid
                    ? '已申请退款，等待 TA 处理'
                    : 'TA 申请了退款',
              ),
            if (o['corrected'] == true) const Meta('目标事实已更正；已兑现事实保留。'),
            if (o['cancel_reason'] != null) Meta('退款说明：${o['cancel_reason']}'),
            CardActions(primary: primary, more: more),
          ],
        ),
      );
    },
  );
}

class WishesScreen extends StatefulWidget {
  final AppController app;
  const WishesScreen(this.app, {super.key});
  @override
  State<WishesScreen> createState() => _WishesScreenState();
}

class _WishesScreenState extends State<WishesScreen> {
  final _list = GlobalKey<RemoteListState>();
  AppController get app => widget.app;

  Future<void> wish() async {
    final title = await textPrompt(
      context,
      '许一个小愿望',
      maxLength: 120,
      action: '许愿',
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    await attempt(context, success: '愿望已告诉 TA', () async {
      await app.command('${app.root}/wishes', {
        'title': title.trim(),
        'description': '',
      });
      await _list.currentState?.reload();
    });
  }

  @override
  Widget build(BuildContext context) => RemoteList(
    key: _list,
    title: '愿望清单',
    load: () async => await app.api.all('${app.root}/wishes'),
    emptyTitle: '还没有愿望',
    emptyMessage: '写下想要的小奖励，TA 可以把它变成奖品。',
    action: FloatingActionButton.extended(
      onPressed: wish,
      icon: const Icon(Icons.add),
      label: const Text('许愿'),
    ),
    item: (context, w, reload) => Paper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${w['title']}', style: Theme.of(context).textTheme.titleMedium),
          if ('${w['description'] ?? ''}'.isNotEmpty)
            Text('${w['description']}'),
          Meta(
            '${w['requester_id'] == app.uid ? '我的愿望' : 'TA 的愿望'} · ${statusLabel('wish', w['status'])}',
          ),
          if (w['requester_id'] != app.uid && w['status'] == 'pending')
            CardActions(
              primary: FilledButton(
                onPressed: () => context.push(
                  '/reward-editor',
                  extra: {
                    'wish_id': w['id'],
                    'title': w['title'],
                    'recipient_id': w['requester_id'],
                  },
                ),
                child: const Text('采纳并创建奖品'),
              ),
              more: [
                (
                  '暂不采纳',
                  () => attempt(context, () async {
                    await app.command(
                      '${app.root}/wishes/${w['id']}/decision',
                      {'accepted': false},
                    );
                    reload();
                  }),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
