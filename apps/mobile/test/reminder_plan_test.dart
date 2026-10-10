import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/features/notifications/reminder_plan.dart';
import 'package:timezone/data/latest.dart' as data;

Map<String, dynamic> version(
  String id,
  int n,
  String time, {
  String status = 'accepted',
}) => {
  'id': id,
  'version': n,
  'title': '约定$n',
  'reminder': time,
  'status': status,
  'starts_on': '2026-10-01',
  'ends_on': null,
  'weekdays': [1, 2, 3, 4, 5, 6, 7],
};
Map<String, dynamic> record({String account = 'alice'}) => {
  'task': {'id': 'task', 'executor_id': account},
  'schedule': <dynamic>[],
  'versions': [
    version('old', 1, '10:00'),
    version('new', 2, '16:00'),
    version('pending', 3, '12:00', status: 'pending'),
  ],
};
Map<String, dynamic> snapshot() => {
  'snapshot_seq': 1,
  'space': {
    'today': '2026-10-08',
    'config': {'timezone': 'UTC'},
    'rules': <dynamic>[],
  },
  'rest_dates': <dynamic>[],
  'daily': <String, dynamic>{
    'instances': [
      {
        'task_id': 'task',
        'user_id': 'alice',
        'task_version_id': 'old',
        'completed': false,
      },
    ],
  },
};
void main() {
  data.initializeTimeZones();
  test('today uses frozen terms; future uses latest accepted version, never pending', () {
    final result = planReminders(
      account: 'alice',
      snapshot: snapshot(),
      tasks: [record()],
      preferences: {},
      now: DateTime.utc(2026, 10, 8, 9),
    );
    expect(result.length, 7);
    expect(result.first.at.hour, 10);
    expect(result[1].at.hour, 16);
    final done = snapshot();
    done['daily']['instances'][0]['completed'] = true;
    expect(
      planReminders(
        account: 'alice',
        snapshot: done,
        tasks: [record()],
        preferences: {},
        now: DateTime.utc(2026, 10, 8, 9),
      ).length,
      6,
    );
  });
  test(
    'rest, future pause, expiry, weekdays and account scope exclude alarms',
    () {
      final state = snapshot();
      state['rest_dates'] = [
        {'user_id': 'alice', 'date': '2026-10-09'},
      ];
      final task = record();
      task['schedule'] = [
        {
          'state': 'paused',
          'effective_date': '2026-10-11',
          'created_at': '2026-10-08',
        },
      ];
      task['versions'][1]['ends_on'] = '2026-10-09';
      expect(
        planReminders(
          account: 'alice',
          snapshot: state,
          tasks: [
            task,
            record(account: 'bob'),
          ],
          preferences: {},
          now: DateTime.utc(2026, 10, 8, 9),
        ).length,
        1,
      );
      expect(
        planReminders(
          account: 'alice',
          snapshot: state,
          tasks: [task],
          preferences: {'reminders': false},
          now: DateTime.utc(2026, 10, 8, 9),
        ),
        isEmpty,
      );
    },
  );
  test('future accepted timezone and DST use civil clock; earliest alarms get capacity', () {
    final state = snapshot();
    state['space']['today'] = '2026-10-31';
    state['daily']['instances'] = <dynamic>[];
    state['space']['config']['timezone'] = 'America/Los_Angeles';
    final task = record();
    task['versions'] = [version('old', 1, '23:00')];
    final result = planReminders(
      account: 'alice',
      snapshot: state,
      tasks: [task],
      preferences: {},
      now: DateTime.utc(2026, 10, 31, 16),
    );
    expect(
      result.first.at.toUtc(),
      DateTime.utc(2026, 11, 1, 16),
    ); // DST ends that morning.
    state['space']['rules'] = [
      {
        'status': 'accepted',
        'effective_date': '2026-11-01',
        'timezone': 'Asia/Shanghai',
        'created_at': '2026-10-31',
      },
    ];
    final changed = planReminders(
      account: 'alice',
      snapshot: state,
      tasks: [task],
      preferences: {'quiet_start': '22:00', 'quiet_end': '22:00'},
      now: DateTime.utc(2026, 10, 31, 16),
    );
    expect(changed[1].at.timeZoneOffset, const Duration(hours: 8));
    final many = List.generate(20, (i) => record()..['task']['id'] = '$i');
    final limited = planReminders(
      account: 'alice',
      snapshot: snapshot(),
      tasks: many,
      preferences: {},
      now: DateTime.utc(2026, 10, 8, 9),
    );
    expect(limited.length, 60);
    expect(limited.last.at.day, 10);
  });
}
