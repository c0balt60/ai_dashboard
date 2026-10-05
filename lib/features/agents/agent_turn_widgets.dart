import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/backend/http_backend.dart' show BackendException;
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import 'chat_markdown.dart';

/// A collapsed bubble standing in for everything an agent did on its way to
/// a reply: its reasoning, its remarks between tool calls and the tools it
/// used. While [live] it shows the latest step; tapping it lists them all.
class ThinkingBubble extends StatefulWidget {
  const ThinkingBubble({super.key, required this.steps, required this.live});

  final List<String> steps;
  final bool live;

  @override
  State<ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final steps = widget.steps;
    final count = '${steps.length} step${steps.length == 1 ? '' : 's'}';

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: widget.live
                            ? Padding(
                                padding: const EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.primary,
                                ),
                              )
                            : Icon(
                                Icons.psychology_outlined,
                                size: 18,
                                color: muted,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.live
                                  ? 'Thinking… · $count'
                                  : 'Thought · $count',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.live && !_expanded && steps.isNotEmpty)
                              Text(
                                steps.last,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, step) in steps.indexed)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 7,
                                    left: 6,
                                    right: 14,
                                  ),
                                  child: CircleAvatar(
                                    radius: 3,
                                    backgroundColor: scheme.outline,
                                  ),
                                ),
                                Expanded(
                                  child: ChatMarkdown(step, color: muted),
                                ),
                              ],
                            ),
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

/// The questions an agent asked, laid out the way Claude Code asks them: one
/// question at a time with a tab per question, numbered options (several
/// when it allows it), an "Other" choice for an answer in the owner's own
/// words and a Submit button. Once answered it sums up the answers.
class QuestionCard extends ConsumerStatefulWidget {
  const QuestionCard({super.key, required this.chatId, required this.message});

  final String chatId;
  final ChatMessage message;

  @override
  ConsumerState<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<QuestionCard> {
  late final _picked = [for (final _ in widget.message.questions) <int>{}];
  late final _other = [
    for (final _ in widget.message.questions) TextEditingController(),
  ];

  /// The index past the options that stands for "Other".
  int _otherIndex(int question) =>
      widget.message.questions[question].options.length;

  int _current = 0;
  bool _sending = false;

  @override
  void dispose() {
    for (final c in _other) {
      c.dispose();
    }
    super.dispose();
  }

  /// The answer to question [i]: the picked labels, plus the typed text when
  /// "Other" is picked.
  String _answer(int i) {
    final q = widget.message.questions[i];
    return [
      for (final (j, o) in q.options.indexed)
        if (_picked[i].contains(j)) o.label,
      if (_picked[i].contains(_otherIndex(i)) && _other[i].text.trim() != '')
        _other[i].text.trim(),
    ].join(', ');
  }

  bool get _complete =>
      [for (var i = 0; i < _picked.length; i++) _answer(i)]
          .every((a) => a.isNotEmpty);

  void _pick(int option) {
    final q = widget.message.questions[_current];
    final picked = _picked[_current];
    final isOther = option == _otherIndex(_current);
    setState(() {
      if (q.multiSelect) {
        picked.contains(option) ? picked.remove(option) : picked.add(option);
      } else {
        picked
          ..clear()
          ..add(option);
        // Like Claude Code, a single choice moves on to the next question.
        if (!isOther && _current < _picked.length - 1) _current++;
      }
    });
  }

  Future<void> _submit() async {
    final questions = widget.message.questions;
    setState(() => _sending = true);
    try {
      await ref.read(backendProvider).answerQuestion(
        widget.chatId,
        widget.message.id,
        {for (final (i, q) in questions.indexed) q.question: _answer(i)},
      );
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Not sent: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaces = AppSurfaces.of(context);
    final message = widget.message;
    final questions = message.questions;
    final answers = message.answers;

    Widget card(List<Widget> children) => Material(
      color: surfaces.card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );

    Widget heading(IconData icon, String text, Color color) => Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (answers != null || questions.isEmpty) {
      final muted = scheme.onSurfaceVariant;
      return card([
        answers == null || answers.isEmpty
            ? heading(Icons.help_outline, 'Not answered here', muted)
            : heading(Icons.check_circle_outline, 'Answered', muted),
        for (final q in questions) ...[
          const SizedBox(height: 10),
          Text(q.question, style: theme.textTheme.bodyMedium),
          if (answers?[q.question] case final answer? when answer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '→ $answer',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ]);
    }

    final q = questions[_current];
    final picked = _picked[_current];
    final last = _current == questions.length - 1;

    Widget option(int index, String label, String description) {
      final selected = picked.contains(index);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Material(
          color: selected
              ? surfaces.tint(scheme.primary, theme.brightness)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _sending ? null : () => _pick(index),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: q.multiSelect
                          ? Icon(
                              selected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 20,
                              color: selected ? scheme.primary : null,
                            )
                          : Text(
                              '${index + 1}.',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (description.isNotEmpty)
                            Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selected && !q.multiSelect)
                      Icon(Icons.check, size: 20, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final otherIndex = _otherIndex(_current);
    return card([
      heading(
        Icons.help_outline,
        questions.length == 1
            ? 'Question'
            : 'Question ${_current + 1} of ${questions.length}',
        scheme.primary,
      ),
      if (questions.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, other) in questions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: i == _current,
                      avatar: Icon(
                        _answer(i).isNotEmpty
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                      ),
                      showCheckmark: false,
                      label: Text(
                        other.header.isEmpty ? 'Q${i + 1}' : other.header,
                      ),
                      onSelected: (_) => setState(() => _current = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 10),
      Text(q.question, style: theme.textTheme.titleSmall),
      Text(
        q.multiSelect ? 'Pick any that apply' : 'Pick one',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      for (final (i, o) in q.options.indexed) option(i, o.label, o.description),
      option(otherIndex, 'Other', 'Type your own answer'),
      if (picked.contains(otherIndex))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            key: ValueKey(_current),
            controller: _other[_current],
            autofocus: true,
            enabled: !_sending,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Your answer'),
            onChanged: (_) => setState(() {}),
          ),
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          if (_current > 0)
            TextButton(
              onPressed: _sending ? null : () => setState(() => _current--),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (!last)
            OutlinedButton(
              onPressed: _sending ? null : () => setState(() => _current++),
              child: const Text('Next'),
            ),
          if (!last) const SizedBox(width: 8),
          FilledButton(
            onPressed: _complete && !_sending ? _submit : null,
            child: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit'),
          ),
        ],
      ),
    ]);
  }
}
