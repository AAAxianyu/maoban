import 'package:flutter_test/flutter_test.dart';
import 'package:miaoban/features/notifications/quiet_hours.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  data.initializeTimeZones();
  final la = tz.getLocation('America/Los_Angeles');
  test(
    'overnight DND across DST uses next civil morning, not 24-hour arithmetic',
    () {
      final result = afterQuietHours(
        tz.TZDateTime(la, 2026, 10, 31, 23),
        '22:00',
        '08:00',
      );
      expect(result.day, 1);
      expect(result.month, 11);
      expect(result.hour, 8);
      expect(result.timeZoneOffset, const Duration(hours: -8));
      expect(result.toUtc(), DateTime.utc(2026, 11, 1, 16));
    },
  );
  test(
    'same-day quiet period and disabled equal endpoints leave correct boundary',
    () {
      final morning = tz.TZDateTime(la, 2026, 10, 8, 7, 59);
      expect(afterQuietHours(morning, '06:00', '08:00').hour, 8);
      final edge = tz.TZDateTime(la, 2026, 10, 8, 8);
      expect(afterQuietHours(edge, '06:00', '08:00'), edge);
      expect(afterQuietHours(morning, '22:00', '22:00'), morning);
    },
  );
}
