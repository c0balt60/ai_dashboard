import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/agent_card.dart';
import '../../widgets/common.dart';
import '../../widgets/project_card.dart';
import '../../widgets/status/status_visuals.dart';

final _pingProvider = FutureProvider.autoDispose<Duration>(
  (ref) => ref.watch(backendProvider).ping(),
);

/// Home tab: connection status, headline stats, weekly throughput and what
/// agents are doing right now.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = <AsyncValue<Object?>>[
      ref.watch(agentsProvider),
      ref.watch(projectsProvider),
      ref.watch(tasksProvider),
    ].where((v) => v.value == null).firstOrNull;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          onRefresh: () => ref.refresh(_pingProvider.future),
          child: CustomScrollView(
            slivers: [
              const SliverAppBar(pinned: true, title: Text('Dashboard')),
              if (pending != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AsyncValueView(
                    pending,
                    data: (_) => const SizedBox.shrink(),
                  ),
                )
              else
                SliverList.list(
                  children: const [
                    _Padded(_ConnectionCard()),
                    SizedBox(height: 12),
                    _Padded(_StatsGrid()),
                    _WeeklyChart(),
                    _ActiveAgents(),
                    _RecentProjects(),
                    _RecentActivity(),
                    SizedBox(height: 24),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );
}

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final ping = ref.watch(_pingProvider);

    final (subtitle, color) = switch (ping) {
      AsyncValue(hasError: true) => ('Ping failed', colors.failed),
      AsyncValue(value: final latency?) => (
        'Ping ${latency.inMilliseconds} ms',
        latency.inMilliseconds < 100 ? colors.completed : colors.waiting,
      ),
      _ => ('Pinging…', colors.idle),
    };

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        leading: Icon(Icons.desktop_windows, color: color),
        title: const Text('Main PC · Connected (mock)'),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
        trailing: ping.isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Ping again',
                onPressed: () => ref.invalidate(_pingProvider),
              ),
      ),
    );
  }
}

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final colors = StatusColors.of(context);
    final rate = stats.testPassRate;

    final tiles = [
      StatTile(
        icon: Icons.smart_toy,
        label: 'Active agents',
        value: '${stats.activeAgents} of ${stats.totalAgents}',
        caption: 'running now',
        color: colors.running,
        onTap: () => context.go(AppRoutes.agents),
      ),
      StatTile(
        icon: Icons.bolt,
        label: 'Running tasks',
        value: '${stats.runningTasks}',
        caption: '+${stats.queuedTasks} queued',
        color: colors.waiting,
        onTap: () => context.go(AppRoutes.tasks),
      ),
      StatTile(
        icon: Icons.science,
        label: 'Test pass rate',
        value: rate == null ? '–' : '${(rate * 100).round()}%',
        caption: 'latest runs',
        color: switch (rate) {
          null => colors.idle,
          >= 0.95 => colors.completed,
          >= 0.8 => colors.waiting,
          _ => colors.failed,
        },
        onTap: () => context.go(AppRoutes.projects),
      ),
      StatTile(
        icon: Icons.task_alt,
        label: 'Done in 24h',
        value: '${stats.completedLast24h}',
        caption: 'tasks completed',
        color: colors.completed,
        onTap: () => context.go(AppRoutes.tasks),
      ),
    ];

    // IntrinsicHeight keeps both tiles in a row equally tall at any text scale.
    Widget row(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ],
      ),
    );

    return Column(
      children: [
        row(tiles[0], tiles[1]),
        const SizedBox(height: 12),
        row(tiles[2], tiles[3]),
      ],
    );
  }
}

class _WeeklyChart extends ConsumerWidget {
  const _WeeklyChart();

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _barAreaHeight = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perDay = ref.watch(dashboardStatsProvider).completedPerDay;
    final now = DateTime.now();
    final days = [
      for (var i = 0; i < perDay.length; i++)
        DateTime(now.year, now.month, now.day - (perDay.length - 1 - i)),
    ];
    final maxCount = perDay.fold(0, (a, b) => a > b ? a : b);
    final total = perDay.fold(0, (a, b) => a + b);
    final letters = [for (final d in days) _dayLetters[d.weekday - 1]];
    final summary = [
      for (var i = 0; i < days.length; i++) '${letters[i]} ${perDay[i]}',
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Completed this week', count: total),
        _Padded(
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Semantics(
                label: 'Tasks completed per day: $summary',
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < perDay.length; i++)
                        Expanded(
                          child: _Bar(
                            count: perDay[i],
                            // Empty days still get a stub so the baseline reads.
                            height: maxCount == 0
                                ? 4
                                : (perDay[i] / maxCount * _barAreaHeight).clamp(
                                    4,
                                    _barAreaHeight,
                                  ),
                            day: letters[i],
                            highlighted: i == perDay.length - 1,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.count,
    required this.height,
    required this.day,
    required this.highlighted,
  });

  final int count;
  final double height;
  final String day;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: theme.textTheme.labelSmall?.copyWith(
            color: count == 0 ? scheme.outline : scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 22,
          height: height,
          decoration: BoxDecoration(
            color: highlighted
                ? scheme.primary
                : scheme.primary.withValues(alpha: count == 0 ? 0.2 : 0.45),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day,
          style: theme.textTheme.labelMedium?.copyWith(
            color: highlighted ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: highlighted ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
  }
}

class _ActiveAgents extends ConsumerWidget {
  const _ActiveAgents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentsProvider).value ?? const [];
    final busy = [
      ...agents.where((a) => a.status == AgentStatus.running),
      ...agents.where((a) => a.status == AgentStatus.waiting),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Active agents',
          count: busy.length,
          actionLabel: 'See all',
          onAction: () => context.go(AppRoutes.agents),
        ),
        if (busy.isEmpty)
          const EmptyState(
            icon: Icons.bedtime_outlined,
            message: 'No agents are running right now.',
          )
        else
          // A Row rather than a fixed-height ListView so cards never clip at
          // large text scales; there are only ever a handful of agents.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, agent) in busy.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    AgentCard(agent, compact: true),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentProjects extends ConsumerWidget {
  const _RecentProjects();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = [...?ref.watch(projectsProvider).value]
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    final recent = projects.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Recent projects',
          actionLabel: 'See all',
          onAction: () => context.go(AppRoutes.projects),
        ),
        if (recent.isEmpty)
          const EmptyState(
            icon: Icons.folder_off_outlined,
            message: 'No projects yet.',
          )
        else
          for (final (i, project) in recent.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _Padded(ProjectCard(project)),
          ],
      ],
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(recentActivityProvider).take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Recent activity'),
        if (activity.isEmpty)
          const EmptyState(
            icon: Icons.history,
            message: 'Nothing has happened yet.',
          )
        else
          _Padded(
            Card(
              child: Column(
                children: [
                  for (final (i, item) in activity.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    _ActivityRow(project: item.project, entry: item.entry),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.project, required this.entry});

  final Project project;
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = entry.level.visual(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      dense: true,
      onTap: () => context.push(AppRoutes.project(project.id)),
      leading: Icon(
        visual.icon,
        color: visual.color,
        size: entry.level == LogLevel.info ? 12 : 20,
        semanticLabel: visual.label,
      ),
      minLeadingWidth: 24,
      title: Text(entry.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(project.name, overflow: TextOverflow.ellipsis),
      trailing: Text(timeAgo(entry.at), style: muted),
    );
  }
}
