/// Light and dark Material 3 themes, the [StatusColors] palette used by every
/// status indicator, and the [AppSurfaces] backdrop/card colors.
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
    waiting: Color(0xFF8A5300),
    completed: Color(0xFF17753A),
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

/// Page backdrop gradient and card colors. Cards sit on the backdrop without
/// borders, so the two must contrast in both brightnesses.
@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({
    required this.backdropTop,
    required this.backdropBottom,
    required this.card,
  });

  factory AppSurfaces.fromScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final base = dark ? scheme.surface : scheme.surfaceContainerLow;
    return AppSurfaces(
      backdropTop: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.12 : 0.14),
        base,
      ),
      backdropBottom: base,
      card: dark ? scheme.surfaceContainer : scheme.surfaceContainerLowest,
    );
  }

  final Color backdropTop;
  final Color backdropBottom;
  final Color card;

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>() ??
      AppSurfaces.fromScheme(Theme.of(context).colorScheme);

  /// A soft wash of [accent] over the card color, for pastel tiles.
  Color tint(Color accent, Brightness brightness) => Color.alphaBlend(
    accent.withValues(alpha: brightness == Brightness.dark ? 0.2 : 0.14),
    card,
  );

  @override
  AppSurfaces copyWith({
    Color? backdropTop,
    Color? backdropBottom,
    Color? card,
  }) {
    return AppSurfaces(
      backdropTop: backdropTop ?? this.backdropTop,
      backdropBottom: backdropBottom ?? this.backdropBottom,
      card: card ?? this.card,
    );
  }

  @override
  AppSurfaces lerp(AppSurfaces? other, double t) {
    if (other == null) return this;
    return AppSurfaces(
      backdropTop: Color.lerp(backdropTop, other.backdropTop, t)!,
      backdropBottom: Color.lerp(backdropBottom, other.backdropBottom, t)!,
      card: Color.lerp(card, other.card, t)!,
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final surfaces = AppSurfaces.fromScheme(scheme);
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.copyWith(
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
  WidgetStateProperty<T> selected<T>(T on, T off) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? on : off,
      );

  return ThemeData(
    colorScheme: scheme,
    textTheme: text,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: surfaces.backdropBottom,
    extensions: [
      brightness == Brightness.dark ? StatusColors.dark : StatusColors.light,
      surfaces,
    ],
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: surfaces.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: ChipThemeData(
      showCheckmark: false,
      shape: const StadiumBorder(),
      // The outline keeps unselected chips visible on card-colored sheets.
      side: WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      color: selected(scheme.inverseSurface, surfaces.card),
      labelStyle: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onInverseSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaces.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: Colors.transparent,
      iconTheme: selected(
        IconThemeData(color: scheme.onSurface, size: 26),
        IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      ),
      labelTextStyle: selected(
        text.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: text.labelLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: text.labelLarge?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(width: 3, color: scheme.onSurface),
      ),
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      unselectedLabelStyle: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 4,
      shape: const StadiumBorder(),
      extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: surfaces.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaces.card,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaces.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
  );
}
