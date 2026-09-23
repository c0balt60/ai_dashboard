/// Riverpod access to the [AgentBackend] and derived, UI-ready views of its
/// data. Screens should watch these rather than the backend directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend/agent_backend.dart';
import '../data/backend/mock_backend.dart';
import '../data/models/models.dart';

final backendProvider = Provider<AgentBackend>((ref) {
  final backend = MockAgentBackend();
  ref.onDispose(backend.dispose);
  return backend;
});

final agentsProvider = StreamProvider<List<Agent>>(
  (ref) => ref.watch(backendProvider).watchAgents(),
);

final projectsProvider = StreamProvider<List<Project>>(
  (ref) => ref.watch(backendProvider).watchProjects(),
);

final tasksProvider = StreamProvider<List<AgentTask>>(
  (ref) => ref.watch(backendProvider).watchTasks(),
);

final messagesProvider = StreamProvider.family<List<ChatMessage>, String>(
  (ref, agentId) => ref.watch(backendProvider).watchMessages(agentId),
);

final agentProvider = Provider.family<Agent?, String>((ref, id) {
  final agents = ref.watch(agentsProvider).value ?? const [];
  return agents.where((a) => a.id == id).firstOrNull;
});

/// The agent a new chat opens with: the most recently active one, so "Ask an
/// agent" picks up where the owner last left off.
final defaultChatAgentProvider = Provider<Agent?>((ref) {
  final agents = ref.watch(agentsProvider).value ?? const [];
  return agents.fold<Agent?>(
    null,
    (best, a) =>
        best == null || a.lastActive.isAfter(best.lastActive) ? a : best,
  );
});

final projectProvider = Provider.family<Project?, String>((ref, id) {
  final projects = ref.watch(projectsProvider).value ?? const [];
  return projects.where((p) => p.id == id).firstOrNull;
});

final taskProvider = Provider.family<AgentTask?, String>((ref, id) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  return tasks.where((t) => t.id == id).firstOrNull;
});

final agentsForProjectProvider = Provider.family<List<Agent>, String>((
  ref,
  projectId,
) {
  final agents = ref.watch(agentsProvider).value ?? const [];
  return agents.where((a) => a.projectId == projectId).toList();
});

/// Tasks for one project, most recently updated first.
final tasksForProjectProvider = Provider.family<List<AgentTask>, String>((
  ref,
  projectId,
) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  return tasks.where((t) => t.projectId == projectId).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

/// Every [TaskState] mapped to its tasks. Open states are oldest first (queue
/// order); finished states are newest first.
final tasksByStateProvider = Provider<Map<TaskState, List<AgentTask>>>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  return {
    for (final state in TaskState.values)
      state: tasks.where((t) => t.state == state).toList()
        ..sort(
          (a, b) => switch (state) {
            TaskState.completed ||
            TaskState.failed => (b.completedAt ?? b.updatedAt).compareTo(
              a.completedAt ?? a.updatedAt,
            ),
            _ => a.createdAt.compareTo(b.createdAt),
          },
        ),
  };
});

/// Projects that currently have at least one running or waiting agent.
final activeProjectIdsProvider = Provider<Set<String>>((ref) {
  final agents = ref.watch(agentsProvider).value ?? const [];
  return {
    for (final a in agents)
      if (a.isBusy && a.projectId != null) a.projectId!,
  };
});

/// Most recent log entries across all projects.
final recentActivityProvider =
    Provider<List<({Project project, LogEntry entry})>>((ref) {
      final projects = ref.watch(projectsProvider).value ?? const [];
      final entries = [
        for (final p in projects)
          for (final e in p.log) (project: p, entry: e),
      ]..sort((a, b) => b.entry.at.compareTo(a.entry.at));
      return entries.take(20).toList();
    });

class DashboardStats {
  const DashboardStats({
    required this.activeAgents,
    required this.totalAgents,
    required this.runningTasks,
    required this.queuedTasks,
    required this.testPassRate,
    required this.completedLast24h,
    required this.completedPerDay,
  });

  final int activeAgents;
  final int totalAgents;
  final int runningTasks;
  final int queuedTasks;

  /// Share of passing tests across each project's latest run, or null when no
  /// runs exist.
  final double? testPassRate;
  final int completedLast24h;

  /// Completed-task counts for the last 7 days, oldest first; the last entry
  /// is today.
  final List<int> completedPerDay;
}

final dashboardStatsProvider = Provider<DashboardStats>((ref) {
  final agents = ref.watch(agentsProvider).value ?? const [];
  final tasks = ref.watch(tasksProvider).value ?? const [];
  final projects = ref.watch(projectsProvider).value ?? const [];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  var passed = 0;
  var total = 0;
  for (final p in projects) {
    final run = p.latestTestRun;
    if (run == null || run.status == TestStatus.running) continue;
    passed += run.passed;
    total += run.total;
  }

  final completed = tasks
      .where((t) => t.state == TaskState.completed && t.completedAt != null)
      .map((t) => t.completedAt!)
      .toList();
  final perDay = List<int>.filled(7, 0);
  for (final at in completed) {
    final day = DateTime(at.year, at.month, at.day);
    final daysAgo = today.difference(day).inDays;
    if (daysAgo >= 0 && daysAgo < 7) perDay[6 - daysAgo]++;
  }

  return DashboardStats(
    activeAgents: agents.where((a) => a.status == AgentStatus.running).length,
    totalAgents: agents.length,
    runningTasks: tasks.where((t) => t.state == TaskState.active).length,
    queuedTasks: tasks
        .where(
          (t) => t.state == TaskState.waiting || t.state == TaskState.backlog,
        )
        .length,
    testPassRate: total == 0 ? null : passed / total,
    completedLast24h: completed
        .where((at) => now.difference(at).inHours < 24)
        .length,
    completedPerDay: perDay,
  );
});
