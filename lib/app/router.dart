/// App navigation: five bottom-nav tabs (each with its own back stack) and
/// full-screen routes for a project, an agent chat and a new task, pushed on
/// the root navigator so they cover the nav bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/agents/agent_chat_screen.dart';
import '../features/agents/agents_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/projects/project_dashboard_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tasks/new_task_screen.dart';
import '../features/tasks/tasks_screen.dart';
import 'shell_scaffold.dart';

abstract final class AppRoutes {
  static const dashboard = '/dashboard';
  static const projects = '/projects';
  static const agents = '/agents';
  static const tasks = '/tasks';
  static const settings = '/settings';

  static String project(String id) => '/project/$id';
  static String agent(String id) => '/agent/$id';
  static String newTask({String? projectId, String? title, String? agentId}) {
    final query = {'project': ?projectId, 'title': ?title, 'agent': ?agentId};
    return Uri(
      path: '/new-task',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ShellScaffold(shell: shell),
        branches: [
          _tab(AppRoutes.dashboard, const DashboardScreen()),
          _tab(AppRoutes.projects, const ProjectsScreen()),
          _tab(AppRoutes.agents, const AgentsScreen()),
          _tab(AppRoutes.tasks, const TasksScreen()),
          _tab(AppRoutes.settings, const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: '/project/:id',
        builder: (context, state) =>
            ProjectDashboardScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/new-task',
        builder: (context, state) => NewTaskScreen(
          projectId: state.uri.queryParameters['project'],
          title: state.uri.queryParameters['title'],
          agentId: state.uri.queryParameters['agent'],
        ),
      ),
      GoRoute(
        path: '/agent/:id',
        builder: (context, state) =>
            AgentChatScreen(agentId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _tab(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);
