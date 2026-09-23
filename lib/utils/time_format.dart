/// Compact relative-time, date and duration strings for mobile UIs.
library;

String timeAgo(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${at.year}-${_two(at.month)}-${_two(at.day)}';
}

String formatDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  return '${d.inSeconds}s';
}

String clockTime(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

/// "Sep 24", or "Sep 24, 2027" outside the current year.
String shortDate(DateTime at, {DateTime? now}) {
  final base = '${_months[at.month - 1]} ${at.day}';
  return at.year == (now ?? DateTime.now()).year ? base : '$base, ${at.year}';
}

/// Calendar days from today until [day], negative for past days.
int daysUntil(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  // UTC dates keep daylight-saving shifts from skewing the day count.
  final today = DateTime.utc(n.year, n.month, n.day);
  return DateTime.utc(day.year, day.month, day.day).difference(today).inDays;
}

String dueLabel(DateTime due, {DateTime? now}) {
  final days = daysUntil(due, now: now);
  return switch (days) {
    < 0 => 'Overdue ${-days}d',
    0 => 'Due today',
    1 => 'Due tomorrow',
    < 7 => 'Due in ${days}d',
    _ => 'Due ${shortDate(due, now: now)}',
  };
}

/// "Sep 20 – Oct 4", "From Sep 20" or "Until Oct 4"; null without dates.
String? dateRange(DateTime? start, DateTime? end, {DateTime? now}) {
  return switch ((start, end)) {
    (null, null) => null,
    (final s?, null) => 'From ${shortDate(s, now: now)}',
    (null, final e?) => 'Until ${shortDate(e, now: now)}',
    (final s?, final e?) when daysUntil(e, now: s) == 0 => shortDate(
      s,
      now: now,
    ),
    (final s?, final e?) =>
      '${shortDate(s, now: now)} – ${shortDate(e, now: now)}',
  };
}

String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
