import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';
import '../data/models/models.dart';
import '../providers/backend_providers.dart';
import '../utils/time_format.dart';
import 'common.dart';
import 'status/agent_avatar.dart';
import 'status/status_visuals.dart';

/// Summary card for a project: its agents, branch and latest test result.
/// Tapping opens the project dashboard unless [onTap] is given.
class ProjectCard extends ConsumerWidget {
  const ProjectCard(this.project, {super.key, this.onTap});

  final Project project;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final agents = ref.watch(agentsForProjectProvider(project.id));
    final run = project.latestTestRun;
    final runVisual = run?.status.visual(context);

    return Card(
      child: InkWell(
        onTap: onTap ?? () => context.push(AppRoutes.project(project.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    timeAgo(project.lastActivity),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                project.path,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (agents.isEmpty)
                    Text('No agents', style: theme.textTheme.labelMedium)
                  else
                    _AvatarStack(agents),
                  const SizedBox(width: 8),
                  Flexible(
                    child: InfoChip(project.branch, icon: Icons.call_split),
                  ),
                  const Spacer(),
                  if (run != null && runVisual != null) ...[
                    Icon(runVisual.icon, size: 16, color: runVisual.color),
                    const SizedBox(width: 4),
                    Text(
                      run.failed > 0
                          ? '${run.failed} failing'
                          : '${run.passed} passed',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: runVisual.color,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack(this.agents);

  final List<Agent> agents;

  @override
  Widget build(BuildContext context) {
    const radius = 12.0;
    const step = radius * 1.6;
    final shown = agents.take(4).toList();
    return SizedBox(
      width: step * (shown.length - 1) + radius * 2 + 8,
      height: radius * 2 + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: AgentAvatar(shown[i], radius: radius),
            ),
        ],
      ),
    );
  }
}
