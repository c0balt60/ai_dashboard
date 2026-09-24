import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';
import '../data/models/models.dart';
import '../providers/backend_providers.dart';
import '../utils/time_format.dart';
import 'common.dart';
import 'status/agent_avatar.dart';
import 'status/status_badge.dart';
import 'status/status_visuals.dart';

/// List card for an agent: avatar, status, project/folder and current
/// activity. Tapping opens the agent chat unless [onTap] is given: its chat
/// for [projectId] when set, otherwise its latest chat.
class AgentCard extends ConsumerWidget {
  const AgentCard(
    this.agent, {
    super.key,
    this.onTap,
    this.projectId,
    this.compact = false,
  });

  final Agent agent;
  final VoidCallback? onTap;
  final String? projectId;

  /// Fixed-width variant for horizontal carousels.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final project = agent.projectId == null
        ? null
        : ref.watch(projectProvider(agent.projectId!));
    final otherProjects = agent.projectIds
        .where((id) => id != agent.projectId)
        .length;

    final header = Row(
      children: [
        AgentAvatar(agent, radius: compact ? 18 : 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agent.name,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                agent.type.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        StatusBadge(agent.status.visual(context), dense: compact),
      ],
    );

    return SizedBox(
      width: compact ? 260 : null,
      child: Card(
        child: InkWell(
          onTap:
              onTap ??
              () => context.push(
                AppRoutes.agent(agent.id, projectId: projectId),
              ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                const SizedBox(height: 12),
                Text(
                  agent.activity,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (project != null)
                      Flexible(
                        child: InfoChip(
                          otherProjects > 0
                              ? '${project.name} +$otherProjects'
                              : project.name,
                          icon: Icons.folder_open,
                        ),
                      )
                    else if (otherProjects > 0)
                      InfoChip(
                        '$otherProjects project${otherProjects == 1 ? '' : 's'}',
                        icon: Icons.folder_outlined,
                      )
                    else
                      const InfoChip('Unassigned', icon: Icons.folder_off),
                    if (agent.branch != null && !compact) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: InfoChip(agent.branch!, icon: Icons.call_split),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      timeAgo(agent.lastActive),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
