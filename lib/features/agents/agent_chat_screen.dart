import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/common.dart';
import '../../widgets/layout.dart';
import '../../widgets/prompt_bar.dart';
import '../../widgets/sheets/app_sheet.dart';
import '../../widgets/sheets/assign_agent_sheet.dart';
import '../../widgets/status/agent_avatar.dart';
import '../../widgets/status/status_badge.dart';
import '../../widgets/status/status_visuals.dart';
import 'chat_markdown.dart';

const _chatMaxWidth = 820.0;

/// Full-screen chat with one agent: what it is working on, a greeting with
/// suggestions while the chat is empty, the conversation, and a composer for
/// new prompts.
///
/// An agent has a general chat plus any number of chats per project. The
/// screen opens [chatId], else the agent's latest chat in [projectId] (or a
/// new one there, created on the first prompt), else its latest chat overall.
/// Tapping the title lists the agent's chats and switches agent.
class AgentChatScreen extends ConsumerStatefulWidget {
  const AgentChatScreen({
    super.key,
    required this.agentId,
    this.chatId,
    this.projectId,
  });

  final String agentId;
  final String? chatId;
  final String? projectId;

  @override
  ConsumerState<AgentChatScreen> createState() => _AgentChatScreenState();
}

enum _ChatAction { newChat, assign, openProject, rename, stop, clear, delete }

class _AgentChatScreenState extends ConsumerState<AgentChatScreen> {
  final _scroll = ScrollController();
  bool _bannerExpanded = false;

  late String? _chatId = widget.chatId;
  late String? _projectId = widget.projectId;

  /// A new chat in [_projectId] that is created on the first prompt.
  bool _draft = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The chat on screen, or null for a draft. While chats are still loading
  /// the agent's general chat stands in, since every agent has one.
  AgentChat? _resolveChat({bool listen = true}) {
    T get<T>(ProviderListenable<T> provider) =>
        listen ? ref.watch(provider) : ref.read(provider);
    if (_chatId case final id?) return get(chatProvider(id));
    if (_draft) return null;
    return get(
      latestChatProvider((agentId: widget.agentId, projectId: _projectId)),
    );
  }

  String? _chatIdOf(AgentChat? chat) =>
      chat?.id ??
      (_chatId == null && _projectId == null && !_draft
          ? widget.agentId
          : null);

  void _openChat(String chatId) => setState(() {
    _chatId = chatId;
    _draft = false;
    _bannerExpanded = false;
  });

  void _startDraft(String? projectId) => setState(() {
    _chatId = null;
    _projectId = projectId;
    _draft = true;
  });

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final backend = ref.read(backendProvider);
    var chatId = _chatIdOf(_resolveChat(listen: false));
    if (chatId == null) {
      final chat = await backend.createChat(
        widget.agentId,
        projectId: _projectId,
      );
      if (!mounted) return;
      _openChat(chat.id);
      chatId = chat.id;
    }
    backend.sendPrompt(chatId, trimmed);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _onAction(
    _ChatAction action,
    Agent agent,
    AgentChat? chat,
  ) async {
    final backend = ref.read(backendProvider);
    final projectId = chat == null ? _projectId : chat.projectId;
    switch (action) {
      case _ChatAction.newChat:
        _startDraft(projectId);
      case _ChatAction.assign:
        await showAssignAgentSheet(
          context,
          agentId: agent.id,
          projectId: projectId,
        );
      case _ChatAction.openProject:
        if (projectId ?? agent.projectId case final id?) {
          context.push(AppRoutes.project(id));
        }
      case _ChatAction.rename:
        if (chat == null) return;
        final title = await showDialog<String>(
          context: context,
          builder: (context) => _RenameChatDialog(chat.displayTitle),
        );
        if (title != null && title.trim().isNotEmpty) {
          await backend.renameChat(chat.id, title.trim());
        }
      case _ChatAction.delete:
        if (chat == null) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete "${chat.displayTitle}"?'),
            content: const Text('Its messages are deleted too.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        setState(() {
          _chatId = null;
          _projectId = chat.projectId;
          _draft = false;
        });
        await backend.deleteChat(chat.id);
      case _ChatAction.stop:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Stop ${agent.name}?'),
            content: Text(
              agent.currentTaskId != null
                  ? 'The agent goes idle and its current task moves back to '
                        'the backlog.'
                  : 'The agent goes idle.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Stop'),
              ),
            ],
          ),
        );
        if (confirmed == true) await backend.stopAgent(agent.id);
      case _ChatAction.clear:
        if (_chatIdOf(chat) case final id?) await backend.clearMessages(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(agentProvider(widget.agentId));
    if (agent == null) {
      return AppBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Agent')),
          body: AsyncValueView(
            ref.watch(agentsProvider),
            data: (_) => const Center(
              child: EmptyState(
                icon: Icons.smart_toy_outlined,
                message: 'This agent is no longer available on your PC.',
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final chat = _resolveChat();
    final chatId = _chatIdOf(chat);
    final projectId = chat == null ? _projectId : chat.projectId;
    final project = projectId == null
        ? null
        : ref.watch(projectProvider(projectId));
    final chatLabel = [
      ?project?.name,
      switch (chat) {
        null when chatId == null => 'New chat',
        null => 'General',
        AgentChat(isDefault: true) => 'General',
        AgentChat c => c.displayTitle,
      },
    ].join(' · ');
    final messagesAsync = chatId == null
        ? const AsyncValue<List<ChatMessage>>.data([])
        : ref.watch(messagesProvider(chatId));
    // With the keyboard up or in landscape there is no room for the banner
    // details and the quick prompts next to the messages.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final cramped = keyboardOpen || MediaQuery.sizeOf(context).height < 600;

    void showChats() => _showChatSwitcher(
      context,
      agent: agent,
      currentChatId: chatId,
      onOpen: _openChat,
      onNew: _startDraft,
      projectId: projectId,
    );

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: true,
          titleSpacing: 0,
          title: Semantics(
            button: true,
            label: 'Chatting with ${agent.name} in $chatLabel. Switch chat',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: showChats,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AgentAvatar(agent, radius: 11),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            agent.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    Text(
                      chatLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            StatusBadge(agent.status.visual(context)),
            PopupMenuButton<_ChatAction>(
              tooltip: 'More',
              icon: const Icon(Icons.short_text),
              onSelected: (action) => _onAction(action, agent, chat),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _ChatAction.newChat,
                  child: _MenuRow(Icons.add_comment_outlined, 'New chat'),
                ),
                const PopupMenuItem(
                  value: _ChatAction.assign,
                  child: _MenuRow(
                    Icons.drive_file_move,
                    'Assign to folder / task',
                  ),
                ),
                if ((projectId ?? agent.projectId) != null)
                  const PopupMenuItem(
                    value: _ChatAction.openProject,
                    child: _MenuRow(Icons.folder_open, 'Open project'),
                  ),
                if (chat != null)
                  const PopupMenuItem(
                    value: _ChatAction.rename,
                    child: _MenuRow(Icons.edit_outlined, 'Rename chat'),
                  ),
                const PopupMenuItem(
                  value: _ChatAction.stop,
                  child: _MenuRow(Icons.stop_circle_outlined, 'Stop agent'),
                ),
                if (chatId != null)
                  const PopupMenuItem(
                    value: _ChatAction.clear,
                    child: _MenuRow(Icons.delete_sweep_outlined, 'Clear chat'),
                  ),
                if (chat != null && !chat.isDefault)
                  const PopupMenuItem(
                    value: _ChatAction.delete,
                    child: _MenuRow(Icons.delete_outline, 'Delete chat'),
                  ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              ContentWidth(
                maxWidth: _chatMaxWidth,
                child: _WorkingBanner(
                  agent: agent,
                  expanded: _bannerExpanded && !cramped,
                  onToggle: () =>
                      setState(() => _bannerExpanded = !_bannerExpanded),
                ),
              ),
              Expanded(
                child: AsyncValueView(
                  messagesAsync,
                  data: (messages) => messages.isEmpty
                      ? _Greeting(
                          agent: agent,
                          project: project,
                          onSend: _send,
                        )
                      : _MessageList(
                          agent: agent,
                          messages: messages,
                          controller: _scroll,
                        ),
                ),
              ),
              _Composer(
                hint: project == null
                    ? 'Ask ${agent.name} anything…'
                    : 'Ask ${agent.name} about ${project.name}…',
                onSend: _send,
                onSwitchAgent: () =>
                    _showAgentSwitcher(context, agent.id, projectId: projectId),
                onAssign: () => showAssignAgentSheet(
                  context,
                  agentId: agent.id,
                  projectId: projectId,
                ),
                showQuickPrompts: !keyboardOpen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

/// Rounded pastel card showing the agent's folder, branch and current task,
/// or an Assign prompt when it has no project yet.
class _WorkingBanner extends ConsumerWidget {
  const _WorkingBanner({
    required this.agent,
    required this.expanded,
    required this.onToggle,
  });

  final Agent agent;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaces = AppSurfaces.of(context);
    final project = agent.projectId == null
        ? null
        : ref.watch(projectProvider(agent.projectId!));
    final task = agent.currentTaskId == null
        ? null
        : ref.watch(taskProvider(agent.currentTaskId!));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final accent = task?.state.visual(context).color ?? scheme.primary;

    Widget card(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: surfaces.tint(accent, theme.brightness),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );

    if (project == null) {
      return card(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Icon(Icons.folder_off, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Not assigned to a project folder yet',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              FilledButton.tonal(
                onPressed: () =>
                    showAssignAgentSheet(context, agentId: agent.id),
                child: const Text('Assign'),
              ),
            ],
          ),
        ),
      );
    }

    final summary = task == null
        ? project.name
        : '${project.name} · ${task.title}';

    return card(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.work_outline, size: 20, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Currently working on',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            expanded ? project.name : summary,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(48, 0, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agent.workingDir ?? project.path,
                          style: muted?.copyWith(fontFamily: 'monospace'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (agent.branch != null) ...[
                          const SizedBox(height: 6),
                          InfoChip(agent.branch!, icon: Icons.call_split),
                        ],
                        if (task != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            task.title,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: task.progress,
                                    minHeight: 6,
                                    color: accent,
                                    backgroundColor: accent.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${(task.progress * 100).round()}%',
                                style: theme.textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          agent.activity,
                          style: muted,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Lists the agent's chats grouped into General and one section per project
/// (every project the agent belongs to, even without chats yet), each with a
/// button for a new chat there. The header switches to another agent.
Future<void> _showChatSwitcher(
  BuildContext context, {
  required Agent agent,
  required String? currentChatId,
  required ValueChanged<String> onOpen,
  required ValueChanged<String?> onNew,
  String? projectId,
}) {
  final screenContext = context;
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        final chats = ref.watch(agentChatsProvider(agent.id));
        final projectIds = {
          ...agent.projectIds,
          for (final c in chats) ?c.projectId,
        };
        final general = [
          ...chats.where((c) => c.isDefault),
          ...chats.where((c) => c.projectId == null && !c.isDefault),
        ];

        void pick(VoidCallback action) {
          Navigator.pop(sheetContext);
          action();
        }

        Widget section(String title, {required VoidCallback onAdd}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'New chat in $title',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: () => pick(onAdd),
              ),
            ],
          ),
        );

        Widget tile(AgentChat chat) => ListTile(
          selected: chat.id == currentChatId,
          leading: Icon(
            chat.isDefault ? Icons.home_outlined : Icons.forum_outlined,
          ),
          title: Text(
            chat.isDefault ? 'General' : chat.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('Active ${timeAgo(chat.updatedAt)}'),
          trailing: chat.id == currentChatId ? const Icon(Icons.check) : null,
          onTap: () => pick(() => onOpen(chat.id)),
        );

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                'Chats with ${agent.name}',
                padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
                trailing: TextButton.icon(
                  onPressed: () => pick(
                    () => _showAgentSwitcher(
                      screenContext,
                      agent.id,
                      projectId: projectId,
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Agent'),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  children: [
                    section('General', onAdd: () => onNew(null)),
                    for (final c in general) tile(c),
                    for (final id in projectIds) ...[
                      section(
                        ref.watch(projectProvider(id))?.name ?? 'Project',
                        onAdd: () => onNew(id),
                      ),
                      for (final c in chats.where((c) => c.projectId == id))
                        tile(c),
                      if (!chats.any((c) => c.projectId == id))
                        ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: const Text('Start a chat here'),
                          onTap: () => pick(() => onNew(id)),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _RenameChatDialog extends StatefulWidget {
  const _RenameChatDialog(this.initial);

  final String initial;

  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  late final _title = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename chat'),
      content: TextField(
        controller: _title,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Title'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _title.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Lets the owner move this chat to another agent; the new chat replaces
/// this one so back still returns to where the chat was opened from. Inside
/// a project chat the other agent opens on its chat for the same project.
Future<void> _showAgentSwitcher(
  BuildContext context,
  String currentId, {
  String? projectId,
}) {
  final router = GoRouter.of(context);
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final agents = ref.watch(agentsProvider).value ?? const [];
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(
                'Chat with',
                padding: EdgeInsets.fromLTRB(24, 0, 16, 8),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  children: [
                    for (final agent in agents)
                      ListTile(
                        selected: agent.id == currentId,
                        leading: AgentAvatar(agent, radius: 16),
                        title: Text(
                          agent.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${agent.type.label} · ${agent.activity}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: agent.id == currentId
                            ? const Icon(Icons.check)
                            : StatusBadge(
                                agent.status.visual(context),
                                dense: true,
                              ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          if (agent.id != currentId) {
                            router.pushReplacement(
                              AppRoutes.agent(agent.id, projectId: projectId),
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Empty-chat welcome: a large greeting and tappable suggestion pills that
/// send their prompt straight away.
class _Greeting extends ConsumerWidget {
  const _Greeting({
    required this.agent,
    required this.project,
    required this.onSend,
  });

  final Agent agent;

  /// The chat's project, or null in a general chat.
  final Project? project;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = agent.currentTaskId == null
        ? null
        : ref.watch(taskProvider(agent.currentTaskId!));
    final project = this.project;
    final suggestions = project == null
        ? const [
            ('💡', 'Explain a concept I keep forgetting'),
            ('📝', 'Draft a commit message style guide'),
            ('🧭', 'Help me plan my next feature'),
          ]
        : [
            if (task != null && task.projectId == project.id)
              ('▶️', 'Continue with "${task.title}"'),
            ('🧪', 'Run the tests and fix any failures'),
            ('📋', "Summarize what you've done so far"),
            ('🔍', 'Review the latest changes for bugs'),
            ('🌿', 'Commit your changes on a new branch'),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final column = math.min(constraints.maxWidth, _chatMaxWidth);
        final side = 24 + (constraints.maxWidth - column) / 2;
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 32, side, 16),
          children: [
            PromptGreeting(
              project == null
                  ? 'Good to see you again! What can ${agent.name} help with?'
                  : 'Good to see you again! What should ${agent.name} work on '
                        'in ${project.name}?',
            ),
            const SizedBox(height: 24),
            for (final (emoji, prompt) in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SuggestionPill.emoji(
                    emoji,
                    label: prompt,
                    onTap: () => onSend(prompt),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.agent,
    required this.messages,
    required this.controller,
  });

  final Agent agent;
  final List<ChatMessage> messages;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final typing =
        agent.status == AgentStatus.running &&
        messages.isNotEmpty &&
        messages.last.role == MessageRole.user;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The list spans the full width so the wheel and scrollbar work
        // anywhere, while side padding centers a column of _chatMaxWidth.
        final column = math.min(constraints.maxWidth, _chatMaxWidth);
        final side = 12 + (constraints.maxWidth - column) / 2;
        final bubbleWidth = math.min(column * 0.78, 560.0);
        // The list is reversed so it sticks to the newest message; index 0 is
        // the bottom of the screen (the typing indicator, when shown).
        final offset = typing ? 1 : 0;
        return ListView.builder(
          controller: controller,
          reverse: true,
          padding: EdgeInsets.fromLTRB(side, 12, side, 8),
          itemCount: messages.length + offset,
          itemBuilder: (context, i) {
            if (typing && i == 0) return _TypingIndicator(agent.type);
            final index = messages.length - 1 - (i - offset);
            final message = messages[index];
            final newer = index + 1 < messages.length
                ? messages[index + 1]
                : null;
            final older = index > 0 ? messages[index - 1] : null;
            return Padding(
              padding: EdgeInsets.only(
                top: older?.role == message.role ? 2 : 10,
              ),
              child: _MessageBubble(
                message: message,
                agentType: agent.type,
                showAvatar: newer?.role != message.role,
                maxWidth: bubbleWidth,
              ),
            );
          },
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.agentType,
    required this.showAvatar,
    required this.maxWidth,
  });

  final ChatMessage message;
  final AgentType agentType;
  final bool showAvatar;
  final double maxWidth;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Message copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaces = AppSurfaces.of(context);

    if (message.role == MessageRole.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: surfaces.card,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${message.text} · ${clockTime(message.at)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final isUser = message.role == MessageRole.user;
    final background = isUser ? scheme.primary : surfaces.card;
    final foreground = isUser ? scheme.onPrimary : scheme.onSurface;
    const radius = Radius.circular(20);
    const tail = Radius.circular(4);

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: radius,
          topRight: radius,
          bottomLeft: !isUser && showAvatar ? tail : radius,
          bottomRight: isUser && showAvatar ? tail : radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onLongPress: () => _copy(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            // The time sits beside short texts and wraps to its own
            // right-aligned line under longer ones.
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              runSpacing: 2,
              children: [
                if (isUser)
                  Text(
                    message.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  )
                else
                  ChatMarkdown(message.text, color: foreground),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    clockTime(message.at),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isUser) {
      return Align(alignment: AlignmentDirectional.centerEnd, child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _AgentIcon(agentType, visible: showAvatar),
        const SizedBox(width: 8),
        Flexible(child: bubble),
      ],
    );
  }
}

class _AgentIcon extends StatelessWidget {
  const _AgentIcon(this.type, {this.visible = true});

  final AgentType type;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Visibility.maintain(
      visible: visible,
      child: CircleAvatar(
        radius: 14,
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(type.icon, size: 16),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator(this.type);

  final AgentType type;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Each dot rises and falls during its own slice of the cycle, staggered by
  /// a fifth of a cycle so the bounce travels left to right.
  double _lift(int dot) {
    final t = (_controller.value - dot * 0.2) % 1.0;
    return t < 0.5 ? math.sin(t / 0.5 * math.pi) : 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _AgentIcon(widget.type),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppSurfaces.of(context).card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Semantics(
              label: 'Agent is typing',
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Transform.translate(
                          offset: Offset(0, -4 * _lift(i)),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.4 + 0.6 * _lift(i),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick-prompt chips above a large rounded composer card: the message field
/// on top, a round assign button and the send button below. On desktop and
/// web, Enter sends and Shift+Enter inserts a newline; on phones Enter always
/// inserts a newline.
class _Composer extends StatefulWidget {
  const _Composer({
    required this.hint,
    required this.onSend,
    required this.onSwitchAgent,
    required this.onAssign,
    required this.showQuickPrompts,
  });

  final String hint;
  final ValueChanged<String> onSend;
  final VoidCallback onSwitchAgent;
  final VoidCallback onAssign;
  final bool showQuickPrompts;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  static const _quickPrompts = [
    'Run tests',
    'Summarize progress',
    'Commit changes',
    'Continue',
  ];

  final _controller = TextEditingController();
  late final _focus = FocusNode(
    onKeyEvent: submitOnEnter(_controller, _submit),
  );

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chipLabel = theme.textTheme.titleSmall?.copyWith(
      color: scheme.onSurface,
    );
    final outlined = IconButton.styleFrom(
      side: BorderSide(color: scheme.outlineVariant),
    );

    return SafeArea(
      top: false,
      child: ContentWidth(
        maxWidth: _chatMaxWidth,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showQuickPrompts) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      ActionChip(
                        tooltip: 'Switch agent',
                        padding: const EdgeInsets.all(10),
                        label: Icon(
                          Icons.auto_awesome_outlined,
                          size: 20,
                          color: scheme.onSurface,
                        ),
                        onPressed: widget.onSwitchAgent,
                      ),
                      for (final label in _quickPrompts)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ActionChip(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            label: Text(label, style: chipLabel),
                            onPressed: () => widget.onSend(label),
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
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _controller,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.fromLTRB(
                            12,
                            12,
                            12,
                            8,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton.outlined(
                            style: outlined,
                            tooltip: 'Assign to folder / task',
                            onPressed: widget.onAssign,
                            icon: const Icon(Icons.add),
                          ),
                          const Spacer(),
                          ValueListenableBuilder(
                            valueListenable: _controller,
                            builder: (context, value, _) {
                              final tooltip = enterSubmitsPrompt
                                  ? 'Send (Enter)'
                                  : 'Send';
                              const icon = Icon(Icons.arrow_upward);
                              return value.text.trim().isEmpty
                                  ? IconButton.outlined(
                                      style: outlined,
                                      tooltip: tooltip,
                                      onPressed: null,
                                      icon: icon,
                                    )
                                  : IconButton.filled(
                                      tooltip: tooltip,
                                      onPressed: _submit,
                                      icon: icon,
                                    );
                            },
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
