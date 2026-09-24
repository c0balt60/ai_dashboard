/// App navigation: five bottom-nav tabs (each with its own back stack) and
/// full-screen routes for a project, an agent chat, a new task and a to-do
/// list, pushed on the root navigator so they cover the nav bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/models.dart';
import '../features/agents/agent_chat_screen.dart';
import '../features/agents/agents_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/projects/project_dashboard_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tasks/new_task_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/todos/todo_list_screen.dart';
import 'shell_scaffold.dart';

abstract final class AppRoutes {
  static const dashboard = '/dashboard';
  static const projects = '/projects';
  static const agents = '/agents';
  static const tasks = '/tasks';
  static const settings = '/settings';

  static String project(String id) => '/project/$id';
  /// An agent's chat: [chatId] if given, else its latest chat in [projectId],
  /// else its latest chat overall.
  static String agent(String id, {String? chatId, String? projectId}) =>
      _withQuery('/agent/$id', {'chat': ?chatId, 'project': ?projectId});

  /// Prefilled from a to-do: [todoListId] and [todoItemId] link the new task
  /// to it so finishing the task ticks the to-do off.
  static String newTask({
    String? projectId,
    String? title,
    String? notes,
    String? agentId,
    String? todoListId,
    String? todoItemId,
  }) => _withQuery('/new-task', {
    'project': ?projectId,
    'title': ?title,
    'notes': ?notes,
    'agent': ?agentId,
    'list': ?todoListId,
    'item': ?todoItemId,
  });

  static String _withQuery(String path, Map<String, String> query) => Uri(
    path: path,
    queryParameters: query.isEmpty ? null : query,
  ).toString();

  static String todoList(String id) => '/list/$id';
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
        builder: (context, state) {
          final query = state.uri.queryParameters;
          final (list, item) = (query['list'], query['item']);
          return NewTaskScreen(
            projectId: query['project'],
            title: query['title'],
            notes: query['notes'],
            agentId: query['agent'],
            todo: list != null && item != null
                ? TodoLink(listId: list, itemId: item)
                : null,
          );
        },
      ),
      GoRoute(
        path: '/agent/:id',
        builder: (context, state) => AgentChatScreen(
          agentId: state.pathParameters['id']!,
          chatId: state.uri.queryParameters['chat'],
          projectId: state.uri.queryParameters['project'],
        ),
      ),
      GoRoute(
        path: '/list/:id',
        builder: (context, state) =>
            TodoListScreen(listId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _tab(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);
