import 'package:flutter/material.dart';

import '../layout.dart';

/// Opens a modal bottom sheet the way every sheet in the app expects: over
/// the nav bar, keyboard-aware and inside the safe area. Phones get a drag
/// handle; desktop windows drop it and rely on the close button in
/// [SheetHeader].
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: !Breakpoints.isDesktop(context),
    builder: builder,
  );
}

/// Title row at the top of a sheet, with an optional [trailing] widget. On
/// desktop, where sheets have no drag handle, it ends in a close button.
class SheetHeader extends StatelessWidget {
  const SheetHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final desktop = Breakpoints.isDesktop(context);
    Widget heading = Text(title, style: Theme.of(context).textTheme.titleLarge);
    if (trailing case final trailing?) {
      heading = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 12),
          trailing,
        ],
      );
    }
    if (!desktop) return Padding(padding: padding, child: heading);

    return Padding(
      padding: const EdgeInsets.only(top: 12).add(padding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // Lines the first row of the title up with the close button.
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: heading,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
    );
  }
}
