import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/layout.dart';
import '../../widgets/page.dart';
import '../../widgets/project_card.dart';

/// Projects tab: every project folder, with the ones that have busy agents
/// listed first.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  bool _activeOnly = false;

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);
    final activeIds = ref.watch(activeProjectIdsProvider);

    return AppPage(
      title: 'Projects',
      icon: Icons.folder_outlined,
      slivers: [
        SliverToBoxAdapter(
          child: _ScopeTabs(
            activeOnly: _activeOnly,
            activeCount: activeIds.length,
            onChanged: (activeOnly) => setState(() => _activeOnly = activeOnly),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: projectsAsync.value == null ? 48 : 0),
            child: AsyncValueView(
              projectsAsync,
              data: (projects) => _ProjectList(
                projects: [...projects]
                  ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity)),
                activeIds: activeIds,
                activeOnly: _activeOnly,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Large "All / Active · N" text tabs in place of filter chips.
class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({
    required this.activeOnly,
    required this.activeCount,
    required this.onChanged,
  });

  final bool activeOnly;
  final int activeCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Flexible(
            child: _ScopeTab(
              label: 'All',
              selected: !activeOnly,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: _ScopeTab(
              label: 'Active · $activeCount',
              selected: activeOnly,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeTab extends StatelessWidget {
  const _ScopeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.titleLarge?.copyWith(
      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
    );

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: style ?? const TextStyle(),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList({
    required this.projects,
    required this.activeIds,
    required this.activeOnly,
  });

  final List<Project> projects;
  final Set<String> activeIds;
  final bool activeOnly;

  @override
  Widget build(BuildContext context) {
    final active = projects.where((p) => activeIds.contains(p.id)).toList();
    final other = projects.where((p) => !activeIds.contains(p.id)).toList();

    if (projects.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_off_outlined,
        message: 'No projects yet.',
      );
    }
    if (activeOnly && active.isEmpty) {
      return const EmptyState(
        icon: Icons.bedtime_outlined,
        message: 'No project has a running agent right now.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (activeOnly)
          const SizedBox(height: 12)
        else if (active.isNotEmpty)
          SectionHeader('Running agents', count: active.length),
        if (active.isNotEmpty) _grid(active),
        if (!activeOnly && other.isNotEmpty) ...[
          SectionHeader('Other projects', count: other.length),
          _grid(other),
        ],
      ],
    );
  }

  Widget _grid(List<Project> projects) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: ResponsiveGrid(
      children: [
        for (final project in projects)
          ProjectCard(project, key: ValueKey(project.id)),
      ],
    ),
  );
}
