import 'package:clock/clock.dart';

abstract final class TimeFormat {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String hm(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}';

  /// Compact label for conversation lists: time today, weekday this week,
  /// otherwise a date.
  static String short(DateTime time, {DateTime? now}) {
    final reference = now ?? clock.now();
    if (isSameDay(time, reference)) return hm(time);
    final days = _startOfDay(reference).difference(_startOfDay(time)).inDays;
    if (days == 1) return 'Yesterday';
    if (days < 7) return _weekdays[time.weekday - 1];
    return '${time.day} ${_months[time.month - 1]}';
  }

  static String day(DateTime time, {DateTime? now}) {
    final reference = now ?? clock.now();
    final days = _startOfDay(reference).difference(_startOfDay(time)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    final label =
        '${_weekdays[time.weekday - 1]}, ${time.day} ${_months[time.month - 1]}';
    return time.year == reference.year ? label : '$label ${time.year}';
  }

  static String lastSeen(DateTime? time, {DateTime? now}) {
    if (time == null) return 'offline';
    final reference = now ?? clock.now();
    final diff = reference.difference(time);
    if (diff.inMinutes < 1) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
    if (isSameDay(time, reference)) return 'last seen today at ${hm(time)}';
    if (diff.inDays < 7) return 'last seen ${short(time, now: reference)}';
    return 'last seen ${time.day} ${_months[time.month - 1]}';
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _startOfDay(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  static String _two(int value) => value.toString().padLeft(2, '0');
}
