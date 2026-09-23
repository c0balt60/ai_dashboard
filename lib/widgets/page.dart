/// The frame shared by the tab screens: a large title header with round
/// action buttons and the theme toggle, content centered on wide screens,
/// optional pull-to-refresh, and an optional floating bottom bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../providers/settings_provider.dart';
import 'layout.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.slivers,
    this.icon,
    this.actions = const [],
    this.floatingActionButton,
    this.bottomBar,
    this.onRefresh,
  });

  final String title;
  final IconData? icon;

  /// Extra [HeaderAction]s shown before the theme toggle.
  final List<Widget> actions;
  final List<Widget> slivers;
  final Widget? floatingActionButton;

  /// Floats over the bottom of the content, e.g. a prompt bar.
  final Widget? bottomBar;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final clearance = floatingActionButton != null || bottomBar != null
        ? 104.0
        : 24.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            Widget body = CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: pageGutter(constraints.maxWidth),
                  ),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: PageHeader(
                          title: title,
                          icon: icon,
                          actions: actions,
                        ),
                      ),
                      ...slivers,
                      SliverToBoxAdapter(child: SizedBox(height: clearance)),
                    ],
                  ),
                ),
              ],
            );
            if (onRefresh != null) {
              body = RefreshIndicator(onRefresh: onRefresh!, child: body);
            }
            if (bottomBar == null) return body;
            return Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: ContentWidth(maxWidth: 720, child: bottomBar!),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Large page title with trailing round actions and the theme toggle.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.icon,
    this.actions = const [],
    this.showThemeToggle = true,
  });

  final String title;
  final IconData? icon;
  final List<Widget> actions;
  final bool showThemeToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 30, color: theme.colorScheme.onSurface),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 4), action],
          if (showThemeToggle) ...[
            const SizedBox(width: 4),
            const ThemeToggleButton(),
          ],
        ],
      ),
    );
  }
}

ButtonStyle _headerActionStyle(BuildContext context) => IconButton.styleFrom(
  backgroundColor: AppSurfaces.of(context).card,
  foregroundColor: Theme.of(context).colorScheme.onSurface,
);

/// Round card-colored icon button for page headers.
class HeaderAction extends StatelessWidget {
  const HeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    style: _headerActionStyle(context),
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

/// Switches between light and dark theme; the icon shows the theme a tap
/// switches to.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    return IconButton(
      style: _headerActionStyle(context),
      tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
      onPressed: () =>
          ref.read(settingsProvider.notifier).toggleBrightness(brightness),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween(begin: 0.6, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          key: ValueKey(dark),
        ),
      ),
    );
  }
}
