/// Product constants shared by the room, growth, task and notification screens.
library;

/// Permanent room XP needed for each keepsake, in unlock order.
const roomKeepsakes = [
  (id: 'lamp', name: '温暖台灯', xp: 10, sprite: 0),
  (id: 'cat_bed', name: '柔软猫窝', xp: 30, sprite: 1),
  (id: 'plant', name: '窗边植物', xp: 60, sprite: 2),
  (id: 'bookshelf', name: '共同书架', xp: 100, sprite: 3),
];

/// Badge cells in decorations-badges.png, keyed by achievement code.
const achievementSprites = {
  'first': 4,
  'seven_days': 5,
  'c_ten': 6,
  'together': 7,
  'thirty': 8,
};

/// Progress toward the next keepsake: `next` is null once all are unlocked.
({double fraction, int? next, int remaining}) keepsakeProgress(int xp) {
  var previous = 0;
  for (final keepsake in roomKeepsakes) {
    if (keepsake.xp > xp) {
      return (
        fraction: (xp - previous) / (keepsake.xp - previous),
        next: keepsake.xp,
        remaining: keepsake.xp - xp,
      );
    }
    previous = keepsake.xp;
  }
  return (fraction: 1, next: null, remaining: 0);
}

/// Task categories; milestone filters accept the same values plus `all`.
const taskTags = {
  'study': '学习',
  'cet6': '六级单词',
  'c': 'C 练习',
  'reading': '阅读',
  'exercise': '运动',
};

String taskGlyph(Object? tag) => switch (tag) {
  'c' => 'c',
  'exercise' => 'exercise',
  _ => 'book',
};

const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// Where an inbox notification or push tap for [eventType] should open.
String routeForEvent(String eventType) {
  if (eventType.startsWith('order')) return '/orders';
  if (eventType.startsWith('milestone')) return '/milestones';
  if (eventType.startsWith('correction')) return '/corrections';
  if (eventType.startsWith('task')) return '/tasks';
  if (eventType.startsWith('rules')) return '/rules';
  return '/feed';
}

/// Common IANA zones offered before free-form search.
const commonTimezones = [
  'Asia/Shanghai',
  'Asia/Hong_Kong',
  'Asia/Taipei',
  'Asia/Tokyo',
  'Asia/Singapore',
  'Europe/London',
  'Europe/Berlin',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Australia/Sydney',
];
