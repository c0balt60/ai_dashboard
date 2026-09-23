import 'package:flutter/material.dart';

import 'status_dot.dart';
import 'status_visuals.dart';

/// Pill-shaped status label, e.g. "● Running".
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.visual, {super.key, this.dense = false});

  final StatusVisual visual;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(visual, size: dense ? 6 : 8),
          const SizedBox(width: 2),
          Text(
            visual.label,
            style: (dense ? text.labelSmall : text.labelMedium)?.copyWith(
              color: visual.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
