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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every tab and detail screen renders on a phone-sized screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
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

    const tabs = {
      'Projects': ProjectsScreen,
      'Agents': AgentsScreen,
      'Tasks': TasksScreen,
      'Settings': SettingsScreen,
      'Dashboard': DashboardScreen,
    };
    for (final MapEntry(key: label, value: screen) in tabs.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
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
  });
}
