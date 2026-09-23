import 'package:ai_dashboard/app/app.dart';
import 'package:ai_dashboard/app/router.dart';
import 'package:ai_dashboard/data/backend/mock_backend.dart';
import 'package:ai_dashboard/features/agents/agent_chat_screen.dart';
import 'package:ai_dashboard/features/agents/agents_screen.dart';
import 'package:ai_dashboard/features/dashboard/dashboard_screen.dart';
import 'package:ai_dashboard/features/projects/project_dashboard_screen.dart';
import 'package:ai_dashboard/features/projects/projects_screen.dart';
import 'package:ai_dashboard/features/settings/settings_screen.dart';
import 'package:ai_dashboard/features/tasks/tasks_screen.dart';
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

/// Visits every tab through [navigation] and then pushes both detail routes.
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

  router.push(AppRoutes.agent('a1'));
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(AgentChatScreen), findsOneWidget);

  router.push(AppRoutes.project('p2'));
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(ProjectDashboardScreen), findsOneWidget);
}

/// MaterialApp animates theme changes: one frame starts the animation, the
/// next lands after it has finished.
Future<void> _pumpThemeChange(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
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
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AgentChatScreen), findsOneWidget);

    // An empty chat greets the owner with suggestions instead of bubbles.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    final agentId = container.read(defaultChatAgentProvider)!.id;
    await container.read(backendProvider).clearMessages(agentId);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Good to see you again'), findsOneWidget);
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
}
