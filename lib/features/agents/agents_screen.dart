import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../widgets/agent_card.dart';
import '../../widgets/common.dart';
import '../../widgets/layout.dart';
import '../../widgets/page.dart';
import '../../widgets/status/status_visuals.dart';

/// Agents tab: every agent on the PC, filterable by status.
class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});

  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> {
  static const _filters = <AgentStatus?>[
    null,
    AgentStatus.running,
    AgentStatus.waiting,
    AgentStatus.idle,
    AgentStatus.failed,
    AgentStatus.completed,
  ];

  AgentStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(agentsProvider);
    final agents = agentsAsync.value;

    return AppPage(
      title: 'Agents',
      icon: Icons.smart_toy_outlined,
      slivers: agents == null
          ? [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: AsyncValueView(
                    agentsAsync,
                    data: (_) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ]
          : _content(context, agents),
    );
  }

  List<Widget> _content(BuildContext context, List<Agent> agents) {
    final shown = _filter == null
        ? agents
        : agents.where((a) => a.status == _filter).toList();
    return [
      SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              for (final status in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    status: status,
                    count: status == null
                        ? agents.length
                        : agents.where((a) => a.status == status).length,
                    selected: _filter == status,
                    onSelected: () => setState(() => _filter = status),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (shown.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyState(
              icon: Icons.smart_toy_outlined,
              message: _filter == null
                  ? 'No agents are running on your PC.'
                  : 'No ${_filter!.visual(context).label.toLowerCase()} agents.',
            ),
          ),
        )
      else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ResponsiveGrid(
              children: [for (final agent in shown) AgentCard(agent)],
            ),
          ),
        ),
    ];
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.status,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final AgentStatus? status;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final visual = status?.visual(context);
    return ChoiceChip(
      avatar: visual == null
          ? null
          : Icon(
              visual.icon,
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.onInverseSurface
                  : visual.color,
            ),
      label: Text('${visual?.label ?? 'All'} · $count'),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
