import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard/app/app.dart';
import 'package:ai_dashboard/app/router.dart';
import 'package:ai_dashboard/features/agents/agent_chat_screen.dart';
import 'package:ai_dashboard/features/agents/agents_screen.dart';
import 'package:ai_dashboard/features/dashboard/dashboard_screen.dart';
import 'package:ai_dashboard/features/projects/project_dashboard_screen.dart';
import 'package:ai_dashboard/features/projects/projects_screen.dart';
import 'package:ai_dashboard/features/settings/settings_screen.dart';
import 'package:ai_dashboard/features/tasks/new_task_screen.dart';
import 'package:ai_dashboard/features/tasks/tasks_screen.dart';
import 'package:ai_dashboard/features/todos/todo_list_screen.dart';
import 'package:ai_dashboard/features/todos/todo_lists_view.dart';
import 'package:ai_dashboard/providers/backend_providers.dart';
import 'package:ai_dashboard/widgets/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _tabs = {
  'Projects': ProjectsScreen,
  'Agents': AgentsScreen,
  'Tasks': TasksScreen,
  'Settings': SettingsScreen,
  'Dashboard': DashboardScreen,
};

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size physicalSize,
  required double pixelRatio,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWith((ref) {
          final backend = MockAgentBackend(
            simulate: false,
            latency: Duration.zero,
          );
          ref.onDispose(backend.dispose);
          return backend;
        }),
      ],
      child: const App(),
    ),
  );
  // Status dots animate forever, so pump fixed frames instead of settling.
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byType(DashboardScreen), findsOneWidget);
}

/// Visits every tab through [navigation], switches the Tasks tab to its
/// lists and then pushes every full-screen route.
Future<void> _visitEverything(WidgetTester tester, Type navigation) async {
  for (final MapEntry(key: label, value: screen) in _tabs.entries) {
    await tester.tap(
      find.descendant(of: find.byType(navigation), matching: find.text(label)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(screen), findsOneWidget, reason: label);
  }

  final router = ProviderScope.containerOf(tester.element(find.byType(App)))
      .read(routerProvider);

  router.go(AppRoutes.tasks);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('My lists'));
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(TodoListsView), findsOneWidget);

  router.push(AppRoutes.agent('a1'));
  await _pumpChat(tester);
  expect(find.byType(AgentChatScreen), findsOneWidget);
  expect(find.textContaining('Route and signature'), findsOneWidget);

  router.push(AppRoutes.project('p2'));
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(ProjectDashboardScreen), findsOneWidget);

  router.push(AppRoutes.todoList('l1'));
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(TodoListScreen), findsOneWidget);

  // A to-do handed off to an agent opens the page prefilled.
  router.push(AppRoutes.newTask(title: 'Ship the lists', agentId: 'a1'));
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(NewTaskScreen), findsOneWidget);
  expect(find.text('Ship the lists'), findsOneWidget);
}

/// Waits for a pushed chat route to animate in, then gives its streams a
/// frame each: the chats resolve which chat to show, and only then does its
/// message stream subscribe.
Future<void> _pumpChat(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// MaterialApp animates theme changes: one frame starts the animation, the
/// next lands after it has finished.
Future<void> _pumpThemeChange(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Opens the "New list" sheet from the Tasks tab. Sheets animate in after
/// the frame that pushes them, so it pumps once more before waiting.
Future<BottomSheet> _openNewListSheet(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(App)))
      .read(routerProvider)
      .go(AppRoutes.tasks);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('My lists'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('New list'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return tester.widget<BottomSheet>(find.byType(BottomSheet));
}

void main() {
  testWidgets('every tab and detail screen renders on a phone-sized screen', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    expect(find.byType(NavigationRail), findsNothing);
    await _visitEverything(tester, NavigationBar);
  });

  testWidgets('wide browser window uses the side rail and renders everything', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1440, 900), pixelRatio: 1);
    expect(find.byType(NavigationBar), findsNothing);
    await _visitEverything(tester, NavigationRail);
  });

  testWidgets('landscape phone keeps the bottom bar and fits every screen', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(2745, 1236), pixelRatio: 3);
    expect(find.byType(NavigationRail), findsNothing);
    await _visitEverything(tester, NavigationBar);
  });

  testWidgets('"Ask an agent" opens the chat of the most recent agent', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    await tester.tap(find.text('Ask an agent…'));
    await _pumpChat(tester);
    expect(find.byType(AgentChatScreen), findsOneWidget);

    // An empty chat greets the owner with suggestions instead of bubbles.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    final agentId = container.read(defaultChatAgentProvider)!.id;
    final chat = container.read(
      latestChatProvider((agentId: agentId, projectId: null)),
    )!;
    await container.read(backendProvider).clearMessages(chat.id);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Good to see you again'), findsOneWidget);
  });

  testWidgets('agent replies render Markdown without overflowing a phone', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    ProviderScope.containerOf(tester.element(find.byType(App)))
        .read(routerProvider)
        .push(AppRoutes.agent('a4'));
    await _pumpChat(tester);

    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('Hides real bugs'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('```'), findsNothing);
  });

  testWidgets('new task page creates a queued task for the chosen agent', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    await tester.tap(find.byTooltip('New task'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NewTaskScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Choose agent'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(MenuItemButton, 'Codex'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).first, 'Add rate limiting');
    await tester.enterText(find.byType(TextField).last, 'Use a token bucket');
    await tester.pump();
    await tester.tap(find.byTooltip('Create task'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NewTaskScreen), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    final task = container
        .read(tasksProvider)
        .value!
        .singleWhere((t) => t.title == 'Add rate limiting');
    expect(task.state, TaskState.waiting);
    expect(task.description, 'Use a token bucket');
    expect(container.read(agentProvider(task.agentId!))!.name, 'Codex');
  });

  testWidgets('the chat title lists project chats and switches between them', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    ProviderScope.containerOf(tester.element(find.byType(App)))
        .read(routerProvider)
        .push(AppRoutes.agent('a1'));
    await _pumpChat(tester);
    expect(find.textContaining('Route and signature'), findsOneWidget);

    await tester.tap(find.text('shop-api · Stripe webhooks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Chats with Claude #1'), findsOneWidget);
    expect(find.text('General'), findsWidgets);

    await tester.tap(find.text('Router review'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Every route has'), findsOneWidget);
    expect(find.textContaining('Route and signature'), findsNothing);
  });

  testWidgets('a project chat opens empty and is created on the first prompt', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    container.read(routerProvider).push(AppRoutes.agent('a5', projectId: 'p3'));
    await _pumpChat(tester);
    expect(find.textContaining('in portfolio-site?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Add a sitemap');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final chat = container.read(
      latestChatProvider((agentId: 'a5', projectId: 'p3')),
    );
    expect(chat?.title, 'Add a sitemap');
    expect(find.text('portfolio-site · Add a sitemap'), findsOneWidget);
  });

  testWidgets('header button toggles between light and dark theme', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(DashboardScreen))).brightness;

    expect(brightness(), Brightness.light);
    await tester.tap(find.byType(ThemeToggleButton));
    await _pumpThemeChange(tester);
    expect(brightness(), Brightness.dark);

    await tester.tap(find.byType(ThemeToggleButton));
    await _pumpThemeChange(tester);
    expect(brightness(), Brightness.light);
  });

  testWidgets('sheets show a drag handle on phones', (tester) async {
    await _pumpApp(tester, physicalSize: const Size(1080, 2340), pixelRatio: 3);
    expect((await _openNewListSheet(tester)).showDragHandle, isTrue);
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('sheets swap the drag handle for a close button on desktop', (
    tester,
  ) async {
    await _pumpApp(tester, physicalSize: const Size(1440, 900), pixelRatio: 1);
    expect((await _openNewListSheet(tester)).showDragHandle, isFalse);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BottomSheet), findsNothing);
  });
}
