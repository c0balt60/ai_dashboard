import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../status/status_visuals.dart';

/// Creates a task, optionally preselecting its project.
Future<void> showNewTaskSheet(BuildContext context, {String? projectId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => _NewTaskSheet(projectId: projectId),
  );
}

class _NewTaskSheet extends ConsumerStatefulWidget {
  const _NewTaskSheet({this.projectId});

  final String? projectId;

  @override
  ConsumerState<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends ConsumerState<_NewTaskSheet> {
  /// Dropdown value for "no agent"; a null item value would show as the hint.
  static const _unassigned = '';

  final _title = TextEditingController();
  late String? _projectId = widget.projectId;
  String? _agentId;
  bool _submitting = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _title.text.trim().isNotEmpty && _projectId != null && !_submitting;

  Future<void> _create(List<Agent> agents) async {
    if (!_canCreate) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final agent = agents.where((a) => a.id == _agentId).firstOrNull;
    setState(() => _submitting = true);
    await ref
        .read(backendProvider)
        .createTask(_title.text.trim(), _projectId!, agentId: agent?.id);
    if (mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          agent == null
              ? 'Task added to the backlog'
              : 'Task queued for ${agent.name}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final agents = ref.watch(agentsProvider).value ?? const <Agent>[];
    final projectValue = projects.any((p) => p.id == _projectId)
        ? _projectId
        : null;
    final agentValue = agents.any((a) => a.id == _agentId)
        ? _agentId!
        : _unassigned;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New task', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'What should be done?',
                  hintText: 'e.g. Add rate limiting to the API',
                  prefixIcon: Icon(Icons.edit_note),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _create(agents),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: projectValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  prefixIcon: Icon(Icons.folder),
                ),
                hint: const Text('Choose a project'),
                items: [
                  for (final p in projects)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() => _projectId = id),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: agentValue,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Agent (optional)',
                  prefixIcon: const Icon(Icons.smart_toy_outlined),
                  helperText: _agentId == null
                      ? 'Unassigned tasks go to the backlog'
                      : 'Queued as waiting until the agent is free',
                ),
                items: [
                  const DropdownMenuItem(
                    value: _unassigned,
                    child: Text('Unassigned → backlog'),
                  ),
                  for (final a in agents)
                    DropdownMenuItem(
                      value: a.id,
                      child: Row(
                        children: [
                          Icon(a.type.icon, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${a.name} · ${a.status.visual(context).label}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (id) =>
                    setState(() => _agentId = id == _unassigned ? null : id),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _canCreate ? () => _create(agents) : null,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
