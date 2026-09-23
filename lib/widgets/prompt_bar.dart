/// Building blocks for the floating "ask an agent" prompt bars on the
/// dashboard and in agent chat.
library;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Gradient ring used as the mark for prompting agents.
class AiOrb extends StatelessWidget {
  const AiOrb({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              scheme.primary,
              scheme.tertiary,
              scheme.error,
              scheme.secondary,
              scheme.primary,
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          width: size * 0.5,
          height: size * 0.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppSurfaces.of(context).card,
          ),
        ),
      ),
    );
  }
}

/// Raised, rounded card surface for prompt inputs. Tappable when [onTap] is
/// given.
class PromptBarFrame extends StatelessWidget {
  const PromptBarFrame({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(12, 6, 6, 6),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    );
    return Material(
      color: AppSurfaces.of(context).card,
      shape: shape,
      elevation: 6,
      shadowColor: scheme.shadow.withValues(alpha: 0.35),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
