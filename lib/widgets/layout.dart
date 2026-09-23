/// Breakpoints and layout helpers that let the mobile-first screens spread out
/// on tablets and in a desktop browser.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

abstract final class Breakpoints {
  /// From this width the shell swaps the bottom bar for a side rail.
  static const wide = 840.0;

  /// From this width the side rail shows its labels.
  static const extended = 1200.0;

  /// Widest a page's content grows before it is centered.
  static const maxContentWidth = 1100.0;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}

/// Extra horizontal space on each side that centers content of
/// [Breakpoints.maxContentWidth] inside [available].
double pageGutter(double available) =>
    math.max(0, (available - Breakpoints.maxContentWidth) / 2);

/// The soft top-to-bottom gradient every page sits on.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, 0.4),
          colors: [surfaces.backdropTop, surfaces.backdropBottom],
        ),
      ),
      child: child,
    );
  }
}

/// Centers [child] and caps its width, for bodies that are not slivers.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Lays [children] out in as many equal columns as fit at [minItemWidth]
/// (up to [maxColumns]), a single column on phones. Cells in a row share the
/// tallest cell's height so cards line up.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 340,
    this.maxColumns = 3,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            ((constraints.maxWidth + spacing) / (minItemWidth + spacing))
                .floor()
                .clamp(1, maxColumns);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) SizedBox(height: spacing),
                child,
              ],
            ],
          );
        }
        final rows = [
          for (var start = 0; start < children.length; start += columns)
            children.sublist(start, math.min(start + columns, children.length)),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) SizedBox(height: spacing),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) SizedBox(width: spacing),
                      Expanded(
                        child: c < row.length ? row[c] : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
