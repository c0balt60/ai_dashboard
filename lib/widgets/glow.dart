/// Soft glows for widgets that float over content, such as the prompt bars
/// and FABs, and the haze that fades content out behind them.
library;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// A wide primary-tinted halo plus a tight shadow for definition. The halo is
/// stronger in dark mode, where a light glow reads better than a shadow.
List<BoxShadow> floatingGlow(BuildContext context) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final scheme = theme.colorScheme;
  return [
    BoxShadow(
      color: scheme.primary.withValues(alpha: dark ? 0.32 : 0.22),
      blurRadius: 40,
      spreadRadius: 2,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: scheme.shadow.withValues(alpha: dark ? 0.35 : 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

/// Paints [floatingGlow] around [child], which should be opaque and match
/// [shape].
class FloatingGlow extends StatelessWidget {
  const FloatingGlow({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
  });

  final Widget child;
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(shape: shape, shadows: floatingGlow(context)),
    child: child,
  );
}

/// A bottom-up fade into the backdrop color, placed under floating bars so
/// content scrolling beneath them dissolves instead of being cut off.
class BottomHaze extends StatelessWidget {
  const BottomHaze({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    final color = AppSurfaces.of(context).backdropBottom;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.85),
              color,
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
      ),
    );
  }
}
