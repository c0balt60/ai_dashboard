import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/layout.dart';
import '../../widgets/prompt_bar.dart';
import '../../widgets/status/agent_avatar.dart';
import '../../widgets/status/status_badge.dart';
import '../../widgets/status/status_visuals.dart';

const _maxWidth = 820.0;

/// Full-screen, assistant-style page for creating a task: describe the work
/// in the composer and pick its project and optional agent from the dropdown
/// buttons inside it. The description becomes the task's title. It can be
/// prefilled, e.g. when handing off one of the user's to-dos.
class NewTaskScreen extends ConsumerStatefulWidget {
  const NewTaskScreen({super.key, this.projectId, this.title, this.agentId});

  /// Preselected project; defaults to the most recently active one.
  final String? projectId;
  final String? title;
  final String? agentId;

  @override
  ConsumerState<NewTaskScreen> createState() => _NewTaskScreenState();
}

class _NewTaskScreenState extends ConsumerState<NewTaskScreen> {
  static const _templates = [
    ('Fix a bug', 'Fix the bug where '),
    ('Add a feature', 'Add '),
    ('Write tests', 'Write tests for '),
    ('Refactor', 'Refactor '),
    ('Update docs', 'Update the docs for '),
  ];

  late final _description = TextEditingController(text: widget.title);
  late final _focus = FocusNode(
    onKeyEvent: submitOnEnter(_description, _create),
  );
  late String? _projectId = widget.projectId;
  late String? _agentId = widget.agentId;
  bool _submitting = false;

  @override
  void dispose() {
    _description.dispose();
    _focus.dispose();
    super.dispose();
  }

  Project? _selectedProject(List<Project> projects) =>
      projects.where((p) => p.id == _projectId).firstOrNull ??
      projects.fold<Project?>(
        null,
        (best, p) => best == null || p.lastActivity.isAfter(best.lastActivity)
            ? p
            : best,
      );

  void _fill(String text) {
    _description.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  /// Proposes a task from the selected project's state, e.g. its failing
  /// tests.
  void _suggest() {
    final project = _selectedProject(ref.read(projectsProvider).value ?? []);
    final run = project?.latestTestRun;
    _fill(switch (run) {
      TestRun(failed: > 0) =>
        'Fix the ${run.failed} failing tests in ${run.suite}',
      null => 'Set up a test suite covering the main flows',
      _ => 'Review the latest changes and clean up anything risky',
    });
  }

  Future<void> _create() async {
    final title = _description.text.trim();
    final project = _selectedProject(ref.read(projectsProvider).value ?? []);
    if (title.isEmpty || project == null || _submitting) return;
    final agent = _agentId == null ? null : ref.read(agentProvider(_agentId!));
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    await ref
        .read(backendProvider)
        .createTask(title, project.id, agentId: agent?.id);
    if (!mounted) return;
    // Opened from a deep link there is nothing to pop back to.
    context.canPop() ? context.pop() : context.go(AppRoutes.tasks);
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
    final projectsAsync = ref.watch(projectsProvider);
    final projects = projectsAsync.value ?? const <Project>[];
    final agents = ref.watch(agentsProvider).value ?? const <Agent>[];
    final project = _selectedProject(projects);
    final agent = agents.where((a) => a.id == _agentId).firstOrNull;
    final outcome = (agent == null ? TaskState.backlog : TaskState.waiting)
        .visual(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AiOrb(size: 26),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'New task',
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [StatusBadge(outcome), const SizedBox(width: 12)],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: projectsAsync.value == null
                    ? AsyncValueView(
                        projectsAsync,
                        data: (_) => const SizedBox.shrink(),
                      )
                    : _Intro(hasProjects: projects.isNotEmpty, agent: agent),
              ),
              _Composer(
                controller: _description,
                focusNode: _focus,
                projects: projects,
                agents: agents,
                project: project,
                agent: agent,
                onProject: (id) => setState(() => _projectId = id),
                onAgent: (id) => setState(() => _agentId = id),
                templates: _templates,
                showChips: !keyboardOpen,
                canCreate: project != null && !_submitting,
                submitting: _submitting,
                onTemplate: _fill,
                onSuggest: _suggest,
                onCreate: _create,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Greeting and what will happen to the task, centered on wide screens.
class _Intro extends StatelessWidget {
  const _Intro({required this.hasProjects, required this.agent});

  final bool hasProjects;
  final Agent? agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final column = math.min(constraints.maxWidth, _maxWidth);
        final side = 24 + (constraints.maxWidth - column) / 2;
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 32, side, 16),
          children: [
            const PromptGreeting('What should your agents work on next?'),
            const SizedBox(height: 16),
            Text(
              !hasProjects
                  ? 'Add a project folder on your PC first.'
                  : agent == null
                  ? 'Describe the task below and pick its project and agent in '
                        'the bar. Without an agent it waits in the backlog.'
                  : 'Queued for ${agent!.name}. It starts as soon as the '
                        'agent is free.',
              style: muted,
            ),
          ],
        );
      },
    );
  }
}

/// Compact "icon · label ▾" button that opens a dropdown menu of options,
/// for the pickers inside the composer card.
class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.tooltip,
    required this.leading,
    required this.label,
    required this.menuChildren,
  });

  final String tooltip;
  final Widget leading;
  final String label;
  final List<Widget> menuChildren;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MenuAnchor(
      menuChildren: menuChildren,
      builder: (context, controller, _) => Tooltip(
        message: tooltip,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurface,
            backgroundColor: controller.isOpen
                ? scheme.surfaceContainerHighest
                : scheme.surfaceContainerHigh,
            padding: const EdgeInsets.only(left: 10, right: 6),
            minimumSize: const Size(0, 40),
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small muted heading inside a picker menu.
class _MenuHeader extends StatelessWidget {
  const _MenuHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Template chips above the description card. The card's bottom row holds
/// the project and agent pickers and the Create button.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.projects,
    required this.agents,
    required this.project,
    required this.agent,
    required this.onProject,
    required this.onAgent,
    required this.templates,
    required this.showChips,
    required this.canCreate,
    required this.submitting,
    required this.onTemplate,
    required this.onSuggest,
    required this.onCreate,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Project> projects;
  final List<Agent> agents;
  final Project? project;
  final Agent? agent;
  final ValueChanged<String> onProject;
  final ValueChanged<String?> onAgent;
  final List<(String, String)> templates;
  final bool showChips;
  final bool canCreate;
  final bool submitting;
  final ValueChanged<String> onTemplate;
  final VoidCallback onSuggest;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chipLabel = theme.textTheme.titleSmall?.copyWith(
      color: scheme.onSurface,
    );
    Widget? check(bool selected) =>
        selected ? Icon(Icons.check, size: 18, color: scheme.primary) : null;

    final projectPicker = _PickerButton(
      tooltip: 'Choose project',
      leading: const Icon(Icons.folder_outlined, size: 18),
      label: project?.name ?? 'No project',
      menuChildren: [
        const _MenuHeader('Project'),
        for (final p in projects)
          MenuItemButton(
            leadingIcon: const Icon(Icons.folder_outlined),
            trailingIcon: check(p.id == project?.id),
            onPressed: () => onProject(p.id),
            child: Text(p.name),
          ),
      ],
    );

    final agentPicker = _PickerButton(
      tooltip: 'Choose agent',
      leading: agent == null
          ? const Icon(Icons.inbox_outlined, size: 18)
          : Icon(agent!.type.icon, size: 18),
      label: agent?.name ?? 'Backlog',
      menuChildren: [
        const _MenuHeader('Agent'),
        MenuItemButton(
          leadingIcon: const Icon(Icons.inbox_outlined),
          trailingIcon: check(agent == null),
          onPressed: () => onAgent(null),
          child: const Text('Backlog · no agent'),
        ),
        for (final a in agents)
          MenuItemButton(
            leadingIcon: AgentAvatar(a, radius: 10),
            trailingIcon:
                check(a.id == agent?.id) ??
                Text(
                  a.status.visual(context).label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: a.status.visual(context).color,
                  ),
                ),
            onPressed: () => onAgent(a.id),
            child: Text(a.name),
          ),
      ],
    );

    return SafeArea(
      top: false,
      child: ContentWidth(
        maxWidth: _maxWidth,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showChips) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      ActionChip(
                        tooltip: 'Suggest a task',
                        padding: const EdgeInsets.all(10),
                        label: Icon(
                          Icons.auto_awesome_outlined,
                          size: 20,
                          color: scheme.onSurface,
                        ),
                        onPressed: onSuggest,
                      ),
                      for (final (label, starter) in templates)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ActionChip(
                            padding: const EdgeInsets.all(10),
                            label: Text(label, style: chipLabel),
                            onPressed: () => onTemplate(starter),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PromptBarFrame(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 2,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyLarge,
                        decoration: const InputDecoration(
                          hintText: 'Describe the task…',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(child: projectPicker),
                                const SizedBox(width: 6),
                                Flexible(child: agentPicker),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder(
                            valueListenable: controller,
                            builder: (context, value, _) => IconButton.filled(
                              tooltip: enterSubmitsPrompt
                                  ? 'Create task (Enter)'
                                  : 'Create task',
                              onPressed:
                                  canCreate && value.text.trim().isNotEmpty
                                  ? onCreate
                                  : null,
                              icon: submitting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_upward),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
