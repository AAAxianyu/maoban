import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app/theme.dart';
import 'api.dart';
import 'domain.dart';
import 'format.dart';

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> textPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  int maxLength = 2000,
  String action = '保存',
}) async {
  final input = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: input,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        maxLength: maxLength,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, input.text),
          child: Text(action),
        ),
      ],
    ),
  );
  input.dispose();
  return result;
}

/// The text a user should see for [error]; internal details never leak.
String errorMessage(Object error) => switch (error) {
  ApiFailure(:final message) || UserMessage(:final message) => message,
  StateError(:final message) => message,
  FormatException() => '输入格式不正确，请检查后重试',
  _ => '操作没有完成，请稍后重试',
};

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs [action] and reports failure (and optional [success]) in a SnackBar.
Future<bool> attempt(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (success != null) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(errorMessage(e))));
    return false;
  }
}

class Paper extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Paper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: context.colors.paper,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.colors.line),
    ),
    child: child,
  );
}

class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final Widget? action;
  const EmptyState(this.title, this.message, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    child: Column(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

/// Secondary line under a card title (dates, statuses, balances).
class Meta extends StatelessWidget {
  final String text;
  final Color? color;
  const Meta(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: color ?? context.colors.secondaryInk),
  );
}

/// One primary action per card; everything else lives in an overflow menu.
class CardActions extends StatelessWidget {
  final Widget? primary;
  final List<(String, VoidCallback)> more;
  const CardActions({super.key, this.primary, this.more = const []});
  @override
  Widget build(BuildContext context) {
    if (primary == null && more.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: primary == null
            ? MainAxisAlignment.end
            : MainAxisAlignment.spaceBetween,
        children: [
          if (primary != null) Flexible(child: primary!),
          if (more.length == 1 && primary == null)
            TextButton(onPressed: more.single.$2, child: Text(more.single.$1))
          else if (more.isNotEmpty)
            PopupMenuButton<VoidCallback>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_horiz),
              onSelected: (callback) => callback(),
              itemBuilder: (context) => [
                for (final (label, callback) in more)
                  PopupMenuItem(value: callback, child: Text(label)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Offline / failure banner shown above the tabs.
class StatusBanner extends StatelessWidget {
  final bool offline;
  final String message;
  final VoidCallback onRetry;
  const StatusBanner({
    super.key,
    required this.offline,
    required this.message,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: offline ? c.offlineBanner : c.errorBanner,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Icon(
                offline ? Icons.cloud_off_outlined : Icons.error_outline,
                color: c.onBanner,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  offline ? '离线中 · 打卡会先保存在本机，联网后自动同步' : message,
                  style: TextStyle(color: c.onBanner),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rebuilds [builder] only when one of the [select]ed values changes identity.
///
/// AppController keeps unchanged snapshot sections identical across syncs, so
/// selecting a section skips rebuilds caused by unrelated updates.
class Select extends StatefulWidget {
  final Listenable listenable;
  final List<Object?> Function() select;
  final WidgetBuilder builder;
  const Select({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
  });
  @override
  State<Select> createState() => _SelectState();
}

class _SelectState extends State<Select> {
  late List<Object?> _values;
  @override
  void initState() {
    super.initState();
    _values = widget.select();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(Select old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    _values = widget.select();
  }

  void _changed() {
    final next = widget.select();
    var same = next.length == _values.length;
    for (var i = 0; same && i < next.length; i++) {
      same = identical(next[i], _values[i]) || next[i] == _values[i];
    }
    if (!same) setState(() => _values = next);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Tappable `HH:mm` field backed by the system time picker.
class ClockField extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool clearable;
  const ClockField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.clearable = false,
  });
  @override
  Widget build(BuildContext context) {
    final parsed = parseClock(value);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: parsed?.$1 ?? 20,
            minute: parsed?.$2 ?? 0,
          ),
        );
        if (picked != null) onChanged(formatClock(picked.hour, picked.minute));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && parsed != null
              ? IconButton(
                  tooltip: '清除$label',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close),
                )
              : const Icon(Icons.schedule),
        ),
        child: Text(parsed == null ? '未设置' : value!),
      ),
    );
  }
}

/// Searchable IANA timezone chooser; common zones are listed first.
Future<String?> pickTimezone(BuildContext context, {String? current}) {
  if (!tz.timeZoneDatabase.isInitialized) tzdata.initializeTimeZones();
  final all =
      tz.timeZoneDatabase.locations.keys.where((z) => z.contains('/')).toList()
        ..sort();
  return showDialog<String>(
    context: context,
    builder: (context) {
      var query = '';
      return StatefulBuilder(
        builder: (context, setState) {
          final q = query.trim().toLowerCase();
          final zones = q.isEmpty
              ? [
                  ...commonTimezones,
                  ...all.where((z) => !commonTimezones.contains(z)),
                ]
              : all.where((z) => z.toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: const Text('选择小屋时区'),
            contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '搜索，例如 Shanghai',
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: zones.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(zones[i]),
                        selected: zones[i] == current,
                        trailing: zones[i] == current
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(context, zones[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// A pushed list page backed by the server.
///
/// Give [load] to fetch everything at once, or [loadPage] to fetch [pageSize]
/// items at a time as the user scrolls.
class RemoteList extends StatefulWidget {
  final String title;
  final Future<List<dynamic>> Function()? load;
  final Future<List<dynamic>> Function(int offset)? loadPage;
  final int pageSize;
  final Widget Function(BuildContext, dynamic, VoidCallback) item;
  final Widget? action;
  final String emptyTitle, emptyMessage;
  const RemoteList({
    super.key,
    required this.title,
    this.load,
    this.loadPage,
    this.pageSize = 50,
    required this.item,
    this.action,
    this.emptyTitle = '这里还很安静',
    this.emptyMessage = '新的记录会出现在这里。',
  }) : assert((load == null) != (loadPage == null));
  @override
  State<RemoteList> createState() => RemoteListState();
}

class RemoteListState extends State<RemoteList> {
  List<dynamic>? items;
  Object? error;
  bool loadingMore = false, exhausted = false;
  int _generation = 0;
  int _nextOffset = 0;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<List<dynamic>> _fetch(int offset) =>
      widget.loadPage != null ? widget.loadPage!(offset) : widget.load!();

  Future<void> reload() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        error = null;
        _reloading = true;
        loadingMore = false;
      });
    }
    try {
      final first = await _fetch(0);
      if (!mounted || generation != _generation) return;
      setState(() {
        items = first;
        _nextOffset = first.length;
        exhausted = widget.loadPage == null || first.length < widget.pageSize;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => error = e);
      // With data already on screen the error page is hidden, so say it here.
      if (items != null) showMessage(context, errorMessage(e));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _reloading = false);
      }
    }
  }

  Future<void> _more() async {
    if (_reloading || loadingMore || exhausted || items == null) return;
    final generation = _generation;
    setState(() => loadingMore = true);
    try {
      final page = await _fetch(_nextOffset);
      if (!mounted || generation != _generation) return;
      // Offset paging can repeat a row when new items arrive meanwhile.
      final seen = {for (final item in items!) _identity(item)};
      setState(() {
        // Advance over every fetched row, including duplicates removed below.
        _nextOffset += page.length;
        items = [
          ...items!,
          ...page.where((item) => !seen.contains(_identity(item))),
        ];
        exhausted = page.length < widget.pageSize;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        showMessage(context, errorMessage(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => loadingMore = false);
      }
    }
  }

  static Object? _identity(dynamic item) => item is Map ? item['id'] : item;

  Widget _body() {
    if (items == null && error != null) {
      return ListView(
        children: [
          EmptyState(
            '读取失败',
            errorMessage(error!),
            action: OutlinedButton(onPressed: reload, child: const Text('重试')),
          ),
        ],
      );
    }
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items!.isEmpty) {
      return ListView(
        children: [EmptyState(widget.emptyTitle, widget.emptyMessage)],
      );
    }
    final data = items!;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _more();
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: data.length + (exhausted ? 0 : 1),
        itemBuilder: (context, i) => i == data.length
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : widget.item(context, data[i], reload),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          onPressed: reload,
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
        ),
      ],
    ),
    floatingActionButton: widget.action,
    body: RefreshIndicator(onRefresh: reload, child: _body()),
  );
}
