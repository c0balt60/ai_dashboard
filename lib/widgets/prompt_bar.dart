/// Building blocks for the assistant-style screens: the floating prompt bars,
/// the large greeting, suggestion pills and Enter-to-submit for prompt fields.
/// Used by the dashboard, agent chat and the new-task page.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import 'glow.dart';

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

/// Rounded card surface for prompt inputs that floats on a soft glow.
/// Tappable when [onTap] is given.
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
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    );
    return FloatingGlow(
      shape: shape,
      child: Material(
        color: AppSurfaces.of(context).card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Whether plain Enter submits a multi-line prompt. Only with a desktop OS; on
/// the web this reports the browser's OS, so phone browsers keep Enter as a
/// newline like the native app.
bool get enterSubmitsPrompt => switch (defaultTargetPlatform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Key handler for a multi-line prompt field's [FocusNode]. It claims plain
/// Enter before the platform text input sees it, so no newline is inserted,
/// and calls [onSubmit]. Shift+Enter and Enter that confirms an IME
/// composition are left alone.
FocusOnKeyEventCallback submitOnEnter(
  TextEditingController controller,
  VoidCallback onSubmit,
) {
  return (node, event) {
    if (!enterSubmitsPrompt) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed ||
        controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) onSubmit();
    return KeyEventResult.handled;
  };
}

/// Large, softly tinted greeting that opens an assistant-style screen.
class PromptGreeting extends StatelessWidget {
  const PromptGreeting(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.headlineMedium?.copyWith(
          color: Color.lerp(scheme.onSurfaceVariant, scheme.primary, 0.3),
        ),
      ),
    );
  }
}

/// Outlined card-colored pill with a leading emoji or avatar. When
/// [selected] is non-null it acts as a choice and fills in while selected.
class SuggestionPill extends StatelessWidget {
  const SuggestionPill({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
    this.caption,
    this.selected,
  });

  /// Shorthand for a pill led by an emoji.
  SuggestionPill.emoji(
    String emoji, {
    Key? key,
    required String label,
    required VoidCallback onTap,
    String? caption,
    bool? selected,
  }) : this(
         key: key,
         leading: ExcludeSemantics(
           child: Text(emoji, style: const TextStyle(fontSize: 20)),
         ),
         label: label,
         onTap: onTap,
         caption: caption,
         selected: selected,
       );

  final Widget leading;
  final String label;
  final String? caption;
  final VoidCallback onTap;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = selected ?? false;
    final foreground = on ? scheme.onInverseSurface : scheme.onSurface;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: on ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: on ? scheme.inverseSurface : AppSurfaces.of(context).card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: label,
                        children: [
                          if (caption != null)
                            TextSpan(
                              text: ' · $caption',
                              style: TextStyle(
                                color: foreground.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
