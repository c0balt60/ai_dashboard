import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import 'status_dot.dart';
import 'status_visuals.dart';

/// Agent-type icon inside a ring colored by the agent's status, with a status
/// dot in the corner.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar(this.agent, {super.key, this.radius = 22});

  final Agent agent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final visual = agent.status.visual(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: radius * 2 + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: visual.color, width: 2),
            ),
            child: CircleAvatar(
              radius: radius,
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: Icon(agent.type.icon, size: radius),
            ),
          ),
          Positioned(
            right: -radius * 0.2,
            bottom: -radius * 0.2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surface,
              ),
              child: StatusDot(visual, size: radius * 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
