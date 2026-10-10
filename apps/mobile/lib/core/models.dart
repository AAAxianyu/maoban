/// Typed, read-only views over the server snapshot JSON.
///
/// The JSON map stays the cached source of truth; these views give screens
/// null-safe accessors instead of scattering `map['key']` casts.
library;

typedef Json = Map<String, dynamic>;

Json _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
List<Json> _list(Object? value) =>
    value is List ? [for (final item in value) _map(item)] : const <Json>[];
int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;
String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

class Member {
  final String id, nickname;
  const Member(this.id, this.nickname);
  factory Member.fromJson(Json json) =>
      Member(_string(json['id']), _string(json['nickname'], '小猫'));
}

class Wallet {
  final int available, debt;
  const Wallet(this.available, this.debt);
  factory Wallet.fromJson(Json json) =>
      Wallet(_int(json['available']), _int(json['debt']));
}

class TaskInstance {
  final Json raw;
  const TaskInstance(this.raw);
  String get id => _string(raw['id']);
  String get userId => _string(raw['user_id']);
  String get title => _string(raw['title']);
  String get standard => _string(raw['standard']);
  String get tag => _string(raw['tag'], 'study');
  String get date => _string(raw['date']);
  String get note => _string(raw['note']);
  int get points => _int(raw['points']);
  int get version => _int(raw['version']);
  bool get completed => raw['completed'] == true;
  bool get required => raw['required'] == true;
}

class DailyPlan {
  final Json raw;
  const DailyPlan(this.raw);
  List<TaskInstance> get instances => [
    for (final i in _list(raw['instances'])) TaskInstance(i),
  ];
  bool restingFor(bool Function(String userId) who) =>
      _list(raw['plans'])
          .any((p) => p['rest'] == true && who(_string(p['user_id'])));
}

class Growth {
  final Json raw;
  const Growth(this.raw);
  int get level => _int(raw['level'], 1);
  int get permanentXp => _int(raw['permanent_xp']);
  Set<String> get decorations => {
    for (final d in _list(raw['decorations'])) _string(d['decoration']),
  };
  Json statsFor(String user) => _map(_map(raw['stats'])[user]);
  Set<String> calendarFor(String user) => {
    for (final c in _list(raw['calendar']))
      if (c['user_id'] == user) _string(c['date']),
  };
  Set<String> achievementsFor(String user) => {
    for (final a in _list(raw['achievements']))
      if (a['user_id'] == user) _string(a['code']),
  };
  Map<String, String> get achievementDefinitions => {
    for (final e in _map(raw['achievement_definitions']).entries)
      e.key: '${e.value}',
  };
}

class Reward {
  final Json raw;
  const Reward(this.raw);
  String get id => _string(raw['id']);
  String get title => _string(raw['title']);
  String get description => _string(raw['description']);
  String get providerId => _string(raw['provider_id']);
  String get recipientId => _string(raw['recipient_id']);
  int get price => _int(raw['price']);
  int? get stock => raw['stock'] is num ? _int(raw['stock']) : null;
  bool get published => raw['published'] == true;
}

class Snapshot {
  final Json raw;
  const Snapshot(this.raw);
  Json get _space => _map(raw['space']);
  String get today => _string(_space['today']);
  String get spaceName => _string(_map(_space['space'])['name'], '我们的小屋');
  String get timezone => _string(_map(_space['config'])['timezone']);
  List<Member> get members => [
    for (final m in _list(_space['members'])) Member.fromJson(m),
  ];
  Wallet get wallet => Wallet.fromJson(_map(raw['wallet']));
  Growth get growth => Growth(_map(raw['growth']));
  DailyPlan get daily => DailyPlan(_map(raw['daily']));
  List<Reward> get rewards => [
    for (final r in _list(raw['rewards'])) Reward(r),
  ];
  Json? get latestPartnerEvent {
    final event = raw['latest_partner_event'];
    return event is Map ? _map(event) : null;
  }

  List<Json> get restDates => _list(raw['rest_dates']);
}
