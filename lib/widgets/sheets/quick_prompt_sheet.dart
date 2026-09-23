import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../common.dart';
import '../prompt_bar.dart';
import '../status/agent_avatar.dart';

/// Sends a prompt to any agent from outside its chat, then opens that chat.
Future<void> showQuickPromptSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => const _QuickPromptSheet(),
  );
}

class _QuickPromptSheet extends ConsumerStatefulWidget {
  const _QuickPromptSheet();

  @override
  ConsumerState<_QuickPromptSheet> createState() => _QuickPromptSheetState();
}

class _QuickPromptSheetState extends ConsumerState<_QuickPromptSheet> {
  static const _quickPrompts = [
    'Run tests',
    'Summarize progress',
    'Commit changes',
    'Continue',
  ];

  final _text = TextEditingController();
  String? _agentId;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The explicit pick if it still exists, else the busiest agent: first
  /// running, then waiting, then whichever comes first.
  Agent? _selected(List<Agent> agents) =>
      agents.where((a) => a.id == _agentId).firstOrNull ??
      agents.where((a) => a.status == AgentStatus.running).firstOrNull ??
      agents.where((a) => a.status == AgentStatus.waiting).firstOrNull ??
      agents.firstOrNull;

  void _fill(String prompt) {
    setState(() {
      _text.value = TextEditingValue(
        text: prompt,
        selection: TextSelection.collapsed(offset: prompt.length),
      );
    });
  }

  void _send(Agent? agent) {
    final text = _text.text.trim();
    if (agent == null || text.isEmpty || _sending) return;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    // Not awaited: the backend resolves only once the agent has replied, and
    // the chat screen shows the typing indicator meanwhile.
    unawaited(ref.read(backendProvider).sendPrompt(agent.id, text));
    navigator.pop();
    router.push(AppRoutes.agent(agent.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agents = ref.watch(agentsProvider).value;
    final selected = agents == null ? null : _selected(agents);
    final canSend = selected != null && _text.text.trim().isNotEmpty;

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
                child: Row(
                  children: [
                    const AiOrb(size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ask an agent',
                        style: theme.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (agents == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (agents.isEmpty)
                const EmptyState(
                  icon: Icons.smart_toy_outlined,
                  message: 'No agents are connected yet.',
                )
              else ...[
                _AgentChips(
                  agents: agents,
                  selectedId: selected?.id,
                  onSelected: (id) => setState(() => _agentId = id),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): () =>
                          _send(selected),
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): () =>
                          _send(selected),
                    },
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: selected == null
                            ? 'What should the agent do?'
                            : 'What should ${selected.name} do?',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final (i, prompt) in _quickPrompts.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        ActionChip(
                          label: Text(prompt),
                          onPressed: () => _fill(prompt),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: canSend && !_sending
                        ? () => _send(selected)
                        : null,
                    icon: const Icon(Icons.arrow_upward),
                    label: const Text('Send'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentChips extends StatelessWidget {
  const _AgentChips({
    required this.agents,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Agent> agents;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (i, agent) in agents.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            ChoiceChip(
              showCheckmark: false,
              avatar: AgentAvatar(agent, radius: 10),
              label: Text(agent.name),
              selected: agent.id == selectedId,
              onSelected: (_) => onSelected(agent.id),
            ),
          ],
        ],
      ),
    );
  }
}
