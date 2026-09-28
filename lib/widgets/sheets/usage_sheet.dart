import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../status/status_visuals.dart';
import 'app_sheet.dart';

/// How full the chat's context is and how much of the account's usage
/// limits the agent has left. Commands the CLI offers, such as `/compact`,
/// are sent to the chat through [onSend].
Future<void> showUsageSheet(
  BuildContext context, {
  required String agentId,
  required String? chatId,
  required ValueChanged<String> onSend,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) =>
        _UsageSheet(agentId: agentId, chatId: chatId, onSend: onSend),
  );
}

class _UsageSheet extends ConsumerWidget {
  const _UsageSheet({
    required this.agentId,
    required this.chatId,
    required this.onSend,
  });

  final String agentId;
  final String? chatId;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(agentProvider(agentId));
    if (agent == null) {
      return const SheetNotice('Usage', 'This agent is no longer on your PC.');
    }
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final chatId = this.chatId;
    final chatContext = chatId == null
        ? null
        : ref.watch(chatProvider(chatId))?.context;
    final commands = {
      for (final c
          in ref.watch(agentOptionsProvider(agentId))?.commands ??
              const <SlashCommand>[])
        c.name,
    };
    final busy = agent.status == AgentStatus.running;
    final usage = agent.usage;

    void send(String command) {
      Navigator.pop(context);
      onSend(command);
    }

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
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
          SheetHeader(
            'Usage',
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
            trailing: agent.activeModel == null
                ? null
                : Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        modelDisplayName(agent.activeModel!) ??
                            agent.activeModel!,
                        style: muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                section('Context in this chat'),
                if (chatContext == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      chatId == null
                          ? 'Starts filling with the first prompt.'
                          : "Shows up after ${agent.name}'s next reply here.",
                      style: muted,
                    ),
                  )
                else
                  _Meter(
                    fraction: chatContext.fraction,
                    title:
                        '${formatTokens(chatContext.usedTokens)} of '
                        '${formatTokens(chatContext.maxTokens)} tokens',
                    detail:
                        '${formatTokens(chatContext.freeTokens)} free · '
                        'updated ${timeAgo(chatContext.updatedAt)}',
                  ),
                if (commands.contains('compact') ||
                    commands.contains('context'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (commands.contains('compact'))
                          FilledButton.tonalIcon(
                            onPressed: busy || chatContext == null
                                ? null
                                : () => send('/compact'),
                            icon: const Icon(Icons.compress),
                            label: const Text('Compact now'),
                          ),
                        if (commands.contains('context'))
                          OutlinedButton(
                            onPressed: busy ? null : () => send('/context'),
                            child: const Text('Details'),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    busy
                        ? '${agent.name} is working. Compacting is possible '
                              'once it is free.'
                        : 'Compacting keeps a summary of the conversation and '
                              'frees the rest. Claude Code also does it on its '
                              'own when the context is nearly full.',
                    style: muted,
                  ),
                ),
                section('Usage limits'),
                if (usage == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      agent.type == AgentType.claudeCode
                          ? 'Shows up once ${agent.name} has run a turn.'
                          : "${agent.type.label} doesn't report its usage "
                                'limits.',
                      style: muted,
                    ),
                  )
                else ...[
                  if (usage.limited)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Text(
                        'A limit is reached, so turns are refused until it '
                        'resets.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: StatusColors.of(context).failed,
                        ),
                      ),
                    ),
                  for (final w in usage.windows)
                    _Meter(
                      fraction: w.utilization,
                      title: w.label,
                      trailing: '${(w.utilization * 100).round()}% used',
                      detail: w.resetsAt == null
                          ? null
                          : 'Resets ${timeUntil(w.resetsAt!)}',
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Text(
                      'Shared by every agent on this account · updated '
                      '${timeAgo(usage.updatedAt)}',
                      style: muted,
                    ),
                  ),
                ],
                if (commands.contains('usage'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => send('/usage'),
                        icon: const Icon(Icons.insights_outlined),
                        label: const Text('Show plan usage'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled bar colored by how much of it is used up.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.fraction,
    required this.title,
    this.trailing,
    this.detail,
  });

  final double fraction;
  final String title;
  final String? trailing;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = usageVisual(context, fraction);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing ?? '${(fraction * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: visual.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            label: '$title, ${visual.label}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                color: visual.color,
                backgroundColor: visual.color.withValues(alpha: 0.18),
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
