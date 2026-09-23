/// Light and dark Material 3 themes plus the [StatusColors] palette used by
/// every status indicator in the app.
library;

import 'package:flutter/material.dart';

const _seed = Color(0xFF4F6BED);

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.running,
    required this.waiting,
    required this.completed,
    required this.failed,
    required this.idle,
  });

  final Color running;
  final Color waiting;
  final Color completed;
  final Color failed;
  final Color idle;

  static const light = StatusColors(
    running: Color(0xFF1E6FE8),
    waiting: Color(0xFFB26A00),
    completed: Color(0xFF1E8E3E),
    failed: Color(0xFFD93025),
    idle: Color(0xFF6B7280),
  );

  static const dark = StatusColors(
    running: Color(0xFF7CB2FF),
    waiting: Color(0xFFFFC266),
    completed: Color(0xFF6DD58C),
    failed: Color(0xFFFF8A80),
    idle: Color(0xFF9CA3AF),
  );

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ?? light;

  @override
  StatusColors copyWith({
    Color? running,
    Color? waiting,
    Color? completed,
    Color? failed,
    Color? idle,
  }) {
    return StatusColors(
      running: running ?? this.running,
      waiting: waiting ?? this.waiting,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      idle: idle ?? this.idle,
    );
  }

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      running: Color.lerp(running, other.running, t)!,
      waiting: Color.lerp(waiting, other.waiting, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
      failed: Color.lerp(failed, other.failed, t)!,
      idle: Color.lerp(idle, other.idle, t)!,
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [
      brightness == Brightness.dark ? StatusColors.dark : StatusColors.light,
    ],
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: const ChipThemeData(showCheckmark: false),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
