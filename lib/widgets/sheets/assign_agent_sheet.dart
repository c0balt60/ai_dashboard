import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../status/agent_avatar.dart';
import '../status/status_badge.dart';
import '../status/status_visuals.dart';

/// Lets the user point an agent at a project folder and optionally a task.
/// Any of [agentId], [projectId] and [taskId] can be preselected.
Future<void> showAssignAgentSheet(
  BuildContext context, {
  String? agentId,
  String? projectId,
  String? taskId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => _AssignAgentSheet(
      agentId: agentId,
      projectId: projectId,
      taskId: taskId,
    ),
  );
}

class _AssignAgentSheet extends ConsumerStatefulWidget {
  const _AssignAgentSheet({this.agentId, this.projectId, this.taskId});

  final String? agentId;
  final String? projectId;
  final String? taskId;

  @override
  ConsumerState<_AssignAgentSheet> createState() => _AssignAgentSheetState();
}

class _AssignAgentSheetState extends ConsumerState<_AssignAgentSheet> {
  /// Dropdown value standing in for "no task", since a null item value would
  /// render as the hint rather than as a selected entry.
  static const _noTask = '';

  final _folder = TextEditingController();
  String? _agentId;
  String? _projectId;
  String? _taskId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _agentId = widget.agentId;
    _taskId = widget.taskId;
    final agent = _agentId == null ? null : ref.read(agentProvider(_agentId!));
    final task = _taskId == null ? null : ref.read(taskProvider(_taskId!));
    _projectId = widget.projectId ?? task?.projectId ?? agent?.projectId;

    final project = _projectId == null
        ? null
        : ref.read(projectProvider(_projectId!));
    final workingDir = agent?.projectId == _projectId
        ? agent?.workingDir
        : null;
    _folder.text = workingDir ?? project?.path ?? '';
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  void _selectProject(Project project) {
    setState(() {
      _projectId = project.id;
      _folder.text = project.path;
      final task = _taskId == null ? null : ref.read(taskProvider(_taskId!));
      if (task?.projectId != project.id) _taskId = null;
    });
  }

  Future<void> _assign(Agent agent, Project project) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _submitting = true);
    await ref
        .read(backendProvider)
        .assignAgent(
          agent.id,
          projectId: project.id,
          workingDir: _folder.text.trim(),
          taskId: _taskId,
        );
    if (mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('${agent.name} assigned to ${project.name}')),
    );
  }

  /// Free agents first, busy ones last, so the likely pick is on top.
  static int _rank(AgentStatus status) => switch (status) {
    AgentStatus.idle || AgentStatus.completed => 0,
    AgentStatus.waiting => 1,
    AgentStatus.failed => 2,
    AgentStatus.running => 3,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final agents = [...ref.watch(agentsProvider).value ?? const <Agent>[]]
      ..sort((a, b) => _rank(a.status).compareTo(_rank(b.status)));
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final tasks = ref.watch(tasksProvider).value ?? const <AgentTask>[];

    final agent = agents.where((a) => a.id == _agentId).firstOrNull;
    final project = projects.where((p) => p.id == _projectId).firstOrNull;
    final taskOptions = [
      for (final t in tasks)
        if (t.projectId == _projectId &&
            (t.state == TaskState.backlog ||
                t.state == TaskState.waiting ||
                t.id == _taskId))
          t,
    ];
    final taskValue = taskOptions.any((t) => t.id == _taskId)
        ? _taskId!
        : _noTask;
    final currentTaskId = agent?.currentTaskId;
    final pausesCurrentTask = currentTaskId != null && currentTaskId != _taskId;
    final canAssign =
        agent != null &&
        project != null &&
        _folder.text.trim().isNotEmpty &&
        !_submitting;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.agentId != null && agent != null
                      ? 'Assign ${agent.name}'
                      : 'Assign agent',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.agentId == null)
                _AgentPicker(
                  agents: agents,
                  selectedId: _agentId,
                  onChanged: (id) => setState(() => _agentId = id),
                )
              else if (agent != null)
                ListTile(
                  leading: AgentAvatar(agent, radius: 18),
                  title: Text(agent.type.label),
                  subtitle: Text(
                    agent.activity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusBadge(agent.status.visual(context)),
                ),
              if (pausesCurrentTask)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Its current task will be paused and moved back to waiting.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: project?.id,
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
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        final picked = projects
                            .where((p) => p.id == id)
                            .firstOrNull;
                        if (picked != null) _selectProject(picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _folder,
                      enabled: project != null,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Working folder',
                        helperText: 'Folder on your PC the agent works in',
                        prefixIcon: Icon(Icons.folder_open),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      // Rebuilt per project so the value always matches an item.
                      key: ValueKey(_projectId),
                      initialValue: taskValue,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Task (optional)',
                        prefixIcon: Icon(Icons.checklist),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: _noTask,
                          child: Text('No task'),
                        ),
                        for (final t in taskOptions)
                          DropdownMenuItem(
                            value: t.id,
                            child: Text(
                              t.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: project == null
                          ? null
                          : (id) => setState(
                              () => _taskId = id == _noTask ? null : id,
                            ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: canAssign
                          ? () => _assign(agent, project)
                          : null,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Assign'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentPicker extends StatelessWidget {
  const _AgentPicker({
    required this.agents,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Agent> agents;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      groupValue: selectedId,
      onChanged: onChanged,
      child: Column(
        children: [
          for (final a in agents)
            RadioListTile<String>(
              value: a.id,
              controlAffinity: ListTileControlAffinity.trailing,
              secondary: AgentAvatar(a, radius: 18),
              title: Text(a.name),
              subtitle: Row(
                children: [
                  StatusBadge(a.status.visual(context), dense: true),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(a.type.label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
