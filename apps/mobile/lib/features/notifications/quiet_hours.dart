import 'package:timezone/timezone.dart' as tz;

/// Uses the space's civil date, including DST, rather than adding 24 hours.
tz.TZDateTime afterQuietHours(
  tz.TZDateTime at,
  String startText,
  String endText,
) {
  int minutes(String text) {
    final p = text.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  final start = minutes(startText),
      end = minutes(endText),
      current = at.hour * 60 + at.minute;
  final quiet = start < end
      ? current >= start && current < end
      : start > end && (current >= start || current < end);
  if (!quiet) return at;
  final nextDay = start > end && current >= start ? 1 : 0;
  return tz.TZDateTime(
    at.location,
    at.year,
    at.month,
    at.day + nextDay,
    end ~/ 60,
    end % 60,
  );
}
