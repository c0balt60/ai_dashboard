import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_version.dart';
import '../../providers/backend_providers.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/layout.dart';
import '../../widgets/page.dart';

/// Settings tab: PC connection, simulation, appearance and notifications,
/// each grouped in its own rounded card. Wide screens split the cards into
/// two independent columns.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _appName = 'AI Dashboard';

  late final _urlController = TextEditingController(
    text: ref.read(settingsProvider).serverUrl,
  );
  bool _testing = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _saveUrl(String value) {
    ref.read(settingsProvider.notifier).setServerUrl(value.trim());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('PC URL saved')));
  }

  Future<void> _testConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    String message;
    try {
      final rtt = await ref.read(backendProvider).ping();
      message = 'Connected to the mock backend · ${rtt.inMilliseconds} ms';
    } catch (e) {
      message = 'Connection failed: $e';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final server = _SettingsSection(
      title: 'Server',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'PC URL',
                hintText: 'http://192.168.1.10:8787',
                prefixIcon: Icon(Icons.computer),
              ),
              onSubmitted: _saveUrl,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_ping),
                label: const Text('Test connection'),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Only the built-in mock backend is available for now. '
                      'The URL is saved but not used to connect yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final simulation = _SettingsSection(
      title: 'Simulation',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SwitchListTile(
          secondary: const Icon(Icons.auto_mode),
          title: const Text('Simulate live activity'),
          subtitle: const Text(
            'Mock agents make progress and finish or fail tasks on their own',
          ),
          value: settings.simulate,
          onChanged: notifier.setSimulate,
        ),
      ),
    );

    final appearance = _SettingsSection(
      title: 'Appearance',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Dark'),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (modes) => notifier.setThemeMode(modes.first),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.dark_mode_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The sun/moon button in each page header switches '
                    'between light and dark quickly.',
                    style: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final notifications = _SettingsSection(
      title: 'Notifications',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.error_outline),
              title: const Text('Agent or task failed'),
              subtitle: const Text('Push notifications are not wired up yet'),
              value: settings.notifyOnFailure,
              onChanged: notifier.setNotifyOnFailure,
            ),
            const Divider(height: 1, indent: 72, endIndent: 16),
            SwitchListTile(
              secondary: const Icon(Icons.task_alt),
              title: const Text('Task completed'),
              subtitle: const Text('Push notifications are not wired up yet'),
              value: settings.notifyOnComplete,
              onChanged: notifier.setNotifyOnComplete,
            ),
          ],
        ),
      ),
    );

    const about = _SettingsSection(
      title: 'About',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          leading: Icon(Icons.smart_toy_outlined),
          title: Text(_appName),
          subtitle: Text('Version $appVersion (build $appBuildNumber)'),
        ),
      ),
    );

    return AppPage(
      title: 'Settings',
      icon: Icons.settings_outlined,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < Breakpoints.wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      server,
                      simulation,
                      appearance,
                      notifications,
                      about,
                    ],
                  );
                }
                // Two independent columns instead of a grid, so a tall card
                // never stretches its neighbour.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [server, appearance],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [simulation, notifications, about],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A bold section title above a rounded card holding the section's controls.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title, padding: const EdgeInsets.fromLTRB(4, 24, 4, 8)),
        Card(child: child),
      ],
    );
  }
}
