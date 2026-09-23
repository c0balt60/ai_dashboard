import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../widgets/common.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: !_activeOnly,
                    onSelected: (_) => setState(() => _activeOnly = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Active (${activeIds.length})'),
                    selected: _activeOnly,
                    onSelected: (_) => setState(() => _activeOnly = true),
                  ),
                ],
              ),
            ),
            Expanded(
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
          ],
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (activeOnly)
          const SizedBox(height: 8)
        else if (active.isNotEmpty)
          SectionHeader('Running agents', count: active.length),
        ..._cards(active),
        if (!activeOnly && other.isNotEmpty) ...[
          SectionHeader('Other projects', count: other.length),
          ..._cards(other),
        ],
      ],
    );
  }

  List<Widget> _cards(List<Project> projects) => [
    for (final project in projects)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ProjectCard(project),
      ),
  ];
}
