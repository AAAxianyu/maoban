/// Date keys, display times and status wording shared by every screen.
library;

/// `yyyy-MM-dd` for a calendar date picked or built on the device.
String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The day after a space-local `yyyy-MM-dd` key.
String nextDateKey(String day) =>
    dateKey(DateTime.parse(day).add(const Duration(days: 1)));

/// `10月9日` (and the year when it differs from [now]).
String formatDay(String day, {DateTime? now}) {
  final date = DateTime.tryParse(day);
  if (date == null) return day;
  final current = now ?? DateTime.now();
  final prefix = date.year == current.year ? '' : '${date.year}年';
  return '$prefix${date.month}月${date.day}日';
}

/// Server timestamps rendered in the device's local time, relative when recent.
String formatTime(Object? value, {DateTime? now}) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) return value?.toString() ?? '';
  final time = parsed.toLocal();
  final current = now ?? DateTime.now();
  final age = current.difference(time);
  if (!age.isNegative) {
    if (age.inMinutes < 1) return '刚刚';
    if (age.inHours < 1) return '${age.inMinutes} 分钟前';
    if (age.inHours < 24 && time.day == current.day) {
      return '${age.inHours} 小时前';
    }
  }
  final clock =
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  final yesterday = DateTime(current.year, current.month, current.day - 1);
  if (time.year == yesterday.year &&
      time.month == yesterday.month &&
      time.day == yesterday.day) {
    return '昨天 $clock';
  }
  return '${formatDay(dateKey(time), now: current)} $clock';
}

/// `HH:mm` → TimeOfDay-like pair, or null when malformed.
(int, int)? parseClock(String? value) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value ?? '');
  if (match == null) return null;
  return (int.parse(match[1]!), int.parse(match[2]!));
}

String formatClock(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

const _proposalStatus = {
  'pending': '等待对方确认',
  'accepted': '已接受',
  'rejected': '已拒绝',
  'superseded': '已被新版本替代',
  'cancelled': '已取消',
};

const _statusLabels = <String, Map<String, String>>{
  'proposal': _proposalStatus,
  'rule': {..._proposalStatus, 'active': '生效中', 'expired': '已过期'},
  'wish': {
    'pending': '等待对方回应',
    'accepted': '已采纳',
    'rejected': '暂不采纳',
    'fulfilled': '已实现',
  },
  'correction': {
    'pending': '等待对方确认',
    'accepted': '已同意',
    'rejected': '已拒绝',
    'applied': '已更正',
  },
  'milestone': {
    ..._proposalStatus,
    'achieved': '已达成',
    'failed': '未达成',
    'completed': '已完成',
    'expired': '已结束',
  },
  'order': {
    'pending': '待兑现',
    'fulfilled': '已兑现，等待领取人确认',
    'completed': '已完成',
    'cancelled': '已取消',
  },
};

/// Human wording for a server status; unknown values never crash the screen.
String statusLabel(String kind, Object? status) =>
    _statusLabels[kind]?[status] ?? (status == null ? '未知状态' : '$status');
