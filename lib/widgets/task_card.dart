import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';
import '../providers/backend_providers.dart';
import '../utils/time_format.dart';
import 'status/status_dot.dart';
import 'status/status_visuals.dart';

/// Queue card for a task, reading as "(Codex) Implement X · project".
/// Active tasks show a progress bar.
class TaskCard extends ConsumerWidget {
  const TaskCard(this.task, {super.key, this.onTap, this.showProject = true});

  final AgentTask task;
  final VoidCallback? onTap;
  final bool showProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visual = task.state.visual(context);
    final agent = task.agentId == null
        ? null
        : ref.watch(agentProvider(task.agentId!));
    final project = ref.watch(projectProvider(task.projectId));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: visual.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusDot(visual, size: 8),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              agent == null
                                  ? 'Unassigned'
                                  : '(${agent.type.shortLabel}) ${agent.name}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: visual.color,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeAgo(task.completedAt ?? task.updatedAt),
                            style: muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        task.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showProject && project != null) ...[
                        const SizedBox(height: 2),
                        Text('in ${project.name}', style: muted),
                      ],
                      if (task.state == TaskState.active) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: task.progress,
                                  minHeight: 6,
                                  color: visual.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${(task.progress * 100).round()}%',
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
