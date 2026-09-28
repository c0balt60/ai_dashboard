import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import 'app_sheet.dart';

/// Lets the owner pick the model and effort level an agent runs on, from
/// what its CLI offers. A pick applies straight away: a running Claude Code
/// turn switches from its next step, other CLIs from their next turn.
Future<void> showModelSheet(BuildContext context, {required String agentId}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _ModelSheet(agentId),
  );
}

class _ModelSheet extends ConsumerStatefulWidget {
  const _ModelSheet(this.agentId);

  final String agentId;

  @override
  ConsumerState<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends ConsumerState<_ModelSheet> {
  /// The owner's latest pick, shown until the agent's snapshot catches up,
  /// so a quick second tap doesn't send the settings from before the first.
  ({String? model, EffortLevel? effort})? _picked;

  @override
  Widget build(BuildContext context) {
    final agentId = widget.agentId;
    final live = ref.watch(agentProvider(agentId));
    if (live == null) {
      return const SheetNotice(
        'Model and effort',
        'This agent is no longer on your PC.',
      );
    }
    final picked = _picked;
    final agent = picked == null
        ? live
        : live.copyWith(model: () => picked.model, effort: () => picked.effort);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final options = ref.watch(agentOptionsProvider(agentId));
    final optionsFailed = ref.watch(agentOptionsListProvider).hasError;
    final models = options?.models ?? const <ModelOption>[];
    final selected = options?.model(agent.model);
    final efforts =
        selected?.efforts ??
        (agent.type == AgentType.claudeCode
            ? EffortLevel.values
            : const <EffortLevel>[]);

    // Read when tapped: two quick taps can land before the sheet rebuilds.
    ({String? model, EffortLevel? effort}) current() {
      final now = ref.read(agentProvider(agentId));
      return _picked ?? (model: now?.model, effort: now?.effort);
    }

    void pick(String? model, EffortLevel? effort) {
      setState(() => _picked = (model: model, effort: effort));
      ref
          .read(backendProvider)
          .setAgentModel(agentId, model: model, effort: effort);
    }

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            'Model and effort',
            padding: EdgeInsets.fromLTRB(24, 0, 16, 0),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Text(
              agent.status == AgentStatus.running
                  ? agent.type == AgentType.claudeCode
                        ? '${agent.name} is working and switches from its next '
                              'step.'
                        : '${agent.name} is working and switches from its next '
                              'turn.'
                  : '${agent.name} uses this from its next turn.',
              style: muted,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                section('Model'),
                if (models.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(
                      optionsFailed
                          ? "The PC can't list models"
                          : options == null
                          ? 'Waiting for the PC to list the models'
                          : '${agent.type.label} lists no models',
                    ),
                    subtitle: optionsFailed
                        ? const Text(
                            'Check the connection, or update the server on your PC.',
                          )
                        : options == null
                        ? null
                        : const Text(
                            'Add them as "models" for this agent in '
                            'server/config.json.',
                          ),
                  ),
                for (final m in models)
                  ListTile(
                    selected: identical(m, selected),
                    leading: Icon(
                      identical(m, selected)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(
                      m.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: m.description.isEmpty
                        ? null
                        : Text(
                            m.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => pick(
                      m.isDefault ? null : m.value,
                      m.efforts.isEmpty ? null : current().effort,
                    ),
                  ),
                if (efforts.isNotEmpty) ...[
                  section('Effort'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final level in [null, ...efforts])
                          ChoiceChip(
                            label: Text(level?.label ?? 'Auto'),
                            selected: agent.effort == level,
                            onSelected: (_) => pick(current().model, level),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      'Higher effort thinks longer and uses more of your '
                      'usage limits.',
                      style: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
