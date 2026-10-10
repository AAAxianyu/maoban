import 'package:timezone/timezone.dart' as tz;

import 'quiet_hours.dart';

tz.Location reminderLocation(String name) =>
    name == 'UTC' || name == 'GMT' ? tz.UTC : tz.getLocation(name);

class PlannedReminder {
  final tz.TZDateTime at;
  final String taskId;
  final String title;
  const PlannedReminder(this.at, this.taskId, this.title);
}

/// Plans civil dates from accepted terms; today's frozen instance wins over edits.
List<PlannedReminder> planReminders({
  required String account,
  required Map<String, dynamic> snapshot,
  required List<dynamic> tasks,
  required Map<String, dynamic> preferences,
  required DateTime now,
}) {
  if (preferences['reminders'] == false) return [];
  final space = snapshot['space'];
  final currentZone = reminderLocation(space['config']['timezone'] as String);
  final civilNow = tz.TZDateTime.from(now, currentZone);
  final rests = (snapshot['rest_dates'] as List? ?? [])
      .where((r) => r['user_id'] == account)
      .map((r) => r['date'])
      .toSet();
  final result = <PlannedReminder>[];
  for (int offset = 0; offset < 7; offset++) {
    final civil = DateTime(
      civilNow.year,
      civilNow.month,
      civilNow.day + offset,
    );
    final date = civil.toIso8601String().substring(0, 10);
    if (rests.contains(date)) continue;
    final rules =
        (space['rules'] as List? ?? [])
            .where(
              (r) =>
                  r['status'] == 'accepted' &&
                  '${r['effective_date']}'.compareTo(date) <= 0,
            )
            .toList()
          ..sort(
            (a, b) => ('${a['effective_date']}${a['created_at']}').compareTo(
              '${b['effective_date']}${b['created_at']}',
            ),
          );
    final zone = rules.isEmpty
        ? currentZone
        : reminderLocation(rules.last['timezone'] as String);
    for (final record in tasks) {
      if (record['task']['executor_id'] != account) continue;
      final changes =
          (record['schedule'] as List)
              .where((c) => '${c['effective_date']}'.compareTo(date) <= 0)
              .toList()
            ..sort(
              (a, b) => ('${a['effective_date']}${a['created_at']}').compareTo(
                '${b['effective_date']}${b['created_at']}',
              ),
            );
      if (changes.isNotEmpty && changes.last['state'] != 'active') continue;
      final versions =
          (record['versions'] as List)
              .where(
                (v) =>
                    v['status'] == 'accepted' &&
                    '${v['starts_on']}'.compareTo(date) <= 0,
              )
              .toList()
            ..sort(
              (a, b) => (a['version'] as int).compareTo(b['version'] as int),
            );
      if (versions.isEmpty) continue;
      final instance = date == space['today']
          ? (snapshot['daily']['instances'] as List)
                .where(
                  (i) =>
                      i['task_id'] == record['task']['id'] &&
                      i['user_id'] == account,
                )
                .firstOrNull
          : null;
      if (instance?['completed'] == true) continue;
      final version = instance == null
          ? versions.last
          : versions
                    .where((v) => v['id'] == instance['task_version_id'])
                    .firstOrNull ??
                versions.last;
      if (version['reminder'] == null ||
          !(version['weekdays'] as List).contains(civil.weekday) ||
          (version['ends_on'] != null &&
              '${version['ends_on']}'.compareTo(date) < 0)) {
        continue;
      }
      final time = (version['reminder'] as String).split(':');
      final at = afterQuietHours(
        tz.TZDateTime(
          zone,
          civil.year,
          civil.month,
          civil.day,
          int.parse(time[0]),
          int.parse(time[1]),
        ),
        preferences['quiet_start'] as String? ?? '22:00',
        preferences['quiet_end'] as String? ?? '08:00',
      );
      if (at.isAfter(now)) {
        result.add(
          PlannedReminder(
            at,
            record['task']['id'] as String,
            version['title'] as String,
          ),
        );
      }
    }
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result.take(60).toList(); // Leave iOS capacity for partner alerts.
}
