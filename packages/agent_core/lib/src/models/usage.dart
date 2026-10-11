import 'json.dart';

/// One usage limit of the account an agent runs on, such as Claude's 5-hour
/// session or weekly window.
class UsageWindow {
  const UsageWindow({
    required this.kind,
    required this.utilization,
    this.resetsAt,
    this.dayStart,
  });

  factory UsageWindow.fromJson(Json json) => UsageWindow(
    kind: json['kind'] as String,
    utilization: (json['utilization'] as num).toDouble(),
    resetsAt: decodeTimeOrNull(json['resetsAt']),
    dayStart: (json['dayStart'] as num?)?.toDouble(),
  );

  /// The CLI's name for the window, e.g. `five_hour` or `seven_day`.
  final String kind;

  /// The share used so far, from 0 to 1.
  final double utilization;
  final DateTime? resetsAt;

  /// For a weekly window, the share used when the day of the last update
  /// began, as far as the backend saw.
  final double? dayStart;

  bool get isWeekly => kind.startsWith('seven_day');

  double get remaining => (1 - utilization).clamp(0, 1).toDouble();

  String get label => switch (kind) {
    'five_hour' => 'Current session',
    'seven_day' => 'This week',
    'seven_day_opus' => 'This week (Opus)',
    'seven_day_sonnet' => 'This week (Sonnet)',
    _ => kind.replaceAll('_', ' '),
  };

  Json toJson() => {
    'kind': kind,
    'utilization': utilization,
    if (resetsAt != null) 'resetsAt': encodeTime(resetsAt!),
    if (dayStart != null) 'dayStart': dayStart,
  };
}

/// How much of a weekly window to use today so that what was left when the
/// day began lasts evenly until the reset, and how much of it is used.
typedef DailyPace = ({double used, double budget});

/// The usage limits an agent last reported, e.g. from Claude Code's rate
/// limit events.
class UsageLimits {
  const UsageLimits({
    required this.windows,
    required this.updatedAt,
    this.limited = false,
  });

  factory UsageLimits.fromJson(Json json) => UsageLimits(
    windows: decodeList(json['windows'], UsageWindow.fromJson),
    updatedAt: decodeTime(json['updatedAt']),
    limited: json['limited'] as bool? ?? false,
  );

  final List<UsageWindow> windows;
  final DateTime updatedAt;

  /// Whether the account has hit a limit and turns are being refused.
  final bool limited;

  /// The window closest to running out.
  UsageWindow? get tightest => windows.fold<UsageWindow?>(
    null,
    (best, w) => best == null || w.utilization > best.utilization ? w : best,
  );

  /// These limits with each weekly window's [UsageWindow.dayStart] worked
  /// out from the [previous] report: kept from earlier today, else the last
  /// share seen before today, or 0 if the window has reset since. Without
  /// one, today counts from now.
  UsageLimits trackingDays(UsageLimits? previous) {
    UsageWindow track(UsageWindow w) {
      if (!w.isWeekly) return w;
      final old = previous?.windows.where((o) => o.kind == w.kind).firstOrNull;
      final start = switch (old) {
        null => w.utilization,
        UsageWindow(:final resetsAt?) when !resetsAt.isAfter(updatedAt) => 0.0,
        _ when _sameDay(previous!.updatedAt, updatedAt) =>
          old.dayStart ?? old.utilization,
        _ => old.utilization,
      };
      return UsageWindow(
        kind: w.kind,
        utilization: w.utilization,
        resetsAt: w.resetsAt,
        dayStart: start,
      );
    }

    return UsageLimits(
      windows: [for (final w in windows) track(w)],
      updatedAt: updatedAt,
      limited: limited,
    );
  }

  /// Today's [DailyPace] for weekly window [w]: what was left when today
  /// began, split evenly over the time from then until the reset, so a reset
  /// within a day leaves all of it for today.
  DailyPace? dailyPace(UsageWindow w, {DateTime? now}) {
    final resetsAt = w.resetsAt;
    if (!w.isWeekly || resetsAt == null) return null;
    now ??= DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final left = resetsAt.difference(today);
    if (left <= Duration.zero) return null;
    // A report from an earlier day means nothing was used since.
    final start = _sameDay(updatedAt, now)
        ? (w.dayStart ?? w.utilization)
        : w.utilization;
    final share = (const Duration(days: 1).inMinutes / left.inMinutes).clamp(
      0.0,
      1.0,
    );
    return (
      used: (w.utilization - start).clamp(0.0, 1.0),
      budget: (1 - start).clamp(0.0, 1.0) * share,
    );
  }

  Json toJson() => {
    'windows': [for (final w in windows) w.toJson()],
    'updatedAt': encodeTime(updatedAt),
    if (limited) 'limited': true,
  };
}

/// How full a chat's conversation is: the tokens it sends the model each
/// turn against the model's context window.
class ContextUsage {
  const ContextUsage({
    required this.usedTokens,
    required this.maxTokens,
    required this.updatedAt,
  });

  factory ContextUsage.fromJson(Json json) => ContextUsage(
    usedTokens: json['usedTokens'] as int,
    maxTokens: json['maxTokens'] as int,
    updatedAt: decodeTime(json['updatedAt']),
  );

  final int usedTokens;
  final int maxTokens;
  final DateTime updatedAt;

  double get fraction =>
      maxTokens <= 0 ? 0 : (usedTokens / maxTokens).clamp(0, 1).toDouble();

  int get freeTokens => maxTokens > usedTokens ? maxTokens - usedTokens : 0;

  Json toJson() => {
    'usedTokens': usedTokens,
    'maxTokens': maxTokens,
    'updatedAt': encodeTime(updatedAt),
  };

  ContextUsage copyWith({
    int? usedTokens,
    int? maxTokens,
    DateTime? updatedAt,
  }) => ContextUsage(
    usedTokens: usedTokens ?? this.usedTokens,
    maxTokens: maxTokens ?? this.maxTokens,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// A token count such as 35.3k or 1M.
String formatTokens(int tokens) {
  String trim(double v) {
    final s = v.toStringAsFixed(v >= 100 ? 0 : 1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (tokens >= 1000000) return '${trim(tokens / 1000000)}M';
  if (tokens >= 1000) return '${trim(tokens / 1000)}k';
  return '$tokens';
}
