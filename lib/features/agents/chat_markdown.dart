import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders an agent reply as GitHub-flavored Markdown, styled to sit inside a
/// chat bubble drawn in [color]. Wide code blocks and tables scroll sideways
/// instead of overflowing, and tapping a link copies it.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown(this.data, {super.key, required this.color});

  final String data;
  final Color color;

  void _copyLink(BuildContext context, String href) {
    Clipboard.setData(ClipboardData(text: href));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Link copied: $href')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final body = text.bodyMedium!.copyWith(color: color);
    final codeBackground = scheme.surfaceContainerHighest;
    final divider = scheme.outlineVariant;

    TextStyle? heading(TextStyle? style) =>
        style?.copyWith(color: color, fontWeight: FontWeight.w700);

    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      a: body.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      ),
      code: body.copyWith(
        fontFamily: 'monospace',
        fontSize: body.fontSize! * 0.9,
        backgroundColor: codeBackground,
      ),
      h1: heading(text.titleLarge),
      h2: heading(text.titleMedium),
      h3: heading(text.titleSmall),
      h4: heading(text.bodyMedium),
      h5: heading(text.bodyMedium),
      h6: heading(text.bodyMedium),
      h1Padding: const EdgeInsets.only(top: 4),
      h2Padding: const EdgeInsets.only(top: 4),
      blockquote: body.copyWith(color: color.withValues(alpha: 0.8)),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      listBullet: body,
      listIndent: 20,
      checkbox: body.copyWith(color: scheme.primary),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBody: body,
      tableHeadAlign: TextAlign.start,
      tableBorder: TableBorder.all(color: divider),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: divider)),
      ),
    );

    return MarkdownBody(
      data: data,
      styleSheet: styleSheet,
      // Agents often put one item per line without a blank line in between,
      // so single newlines stay line breaks, as in most chat apps.
      softLineBreak: true,
      onTapLink: (_, href, _) {
        if (href != null) _copyLink(context, href);
      },
    );
  }
}
