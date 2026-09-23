import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/models.dart';
import '../providers/backend_providers.dart';
import '../widgets/layout.dart';
import '../widgets/prompt_bar.dart';
import 'theme.dart';

/// Shell hosting the five top-level tabs: a bottom navigation bar on phones
/// and a side rail on wide screens such as a desktop browser.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.folder_outlined, Icons.folder, 'Projects'),
    (Icons.smart_toy_outlined, Icons.smart_toy, 'Agents'),
    (Icons.checklist_outlined, Icons.checklist, 'Tasks'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];
  static const _agentsTab = 2;

  // Re-tapping the current tab pops it back to its root.
  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failedAgents =
        ref
            .watch(agentsProvider)
            .value
            ?.where((a) => a.status == AgentStatus.failed)
            .length ??
        0;

    Widget icon(int index, {required bool selected}) {
      final (outlined, filled, _) = _tabs[index];
      return Badge(
        isLabelVisible: index == _agentsTab && failedAgents > 0,
        child: Icon(selected ? filled : outlined),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    if (!Breakpoints.isDesktop(context)) {
      return Scaffold(
        body: AppBackdrop(child: shell),
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _select,
          destinations: [
            for (final (i, (_, _, label)) in _tabs.indexed)
              NavigationDestination(
                icon: icon(i, selected: false),
                selectedIcon: icon(i, selected: true),
                label: label,
                tooltip: '',
              ),
          ],
        ),
      );
    }

    final extended = width >= Breakpoints.extended;
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          right: false,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                child: Material(
                  color: AppSurfaces.of(context).card,
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: NavigationRail(
                    extended: extended,
                    scrollable: true,
                    minExtendedWidth: 232,
                    selectedIndex: shell.currentIndex,
                    onDestinationSelected: _select,
                    labelType: extended
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    groupAlignment: -1,
                    leading: _RailBrand(extended: extended),
                    destinations: [
                      for (final (i, (_, _, label)) in _tabs.indexed)
                        NavigationRailDestination(
                          icon: icon(i, selected: false),
                          selectedIcon: icon(i, selected: true),
                          label: Text(label),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: shell),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(extended ? 20 : 0, 20, 0, 24),
      child: extended
          ? SizedBox(
              width: 192,
              child: Row(
                children: [
                  const AiOrb(size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Agent Dashboard',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            )
          : const AiOrb(size: 28),
    );
  }
}
