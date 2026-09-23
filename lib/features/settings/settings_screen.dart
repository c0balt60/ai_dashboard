import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_version.dart';
import '../../providers/backend_providers.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/layout.dart';
import '../../widgets/page.dart';
import '../../widgets/status/status_dot.dart';
import '../../widgets/status/status_visuals.dart';

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
  late final _tokenController = TextEditingController(
    text: ref.read(settingsProvider).authToken,
  );
  bool _testing = false;
  bool _showToken = false;
  String? _urlError;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Saves the URL and token fields. Returns false, flagging the URL field,
  /// when the URL isn't usable.
  bool _saveServer() {
    final notifier = ref.read(settingsProvider.notifier);
    try {
      notifier.setServerUrl(_urlController.text);
    } on FormatException catch (e) {
      setState(() => _urlError = e.message);
      return false;
    }
    notifier.setAuthToken(_tokenController.text);
    setState(() => _urlError = null);
    return true;
  }

  void _setMode(ConnectionMode mode) {
    if (mode == ConnectionMode.server && !_saveServer()) return;
    ref.read(settingsProvider.notifier).setConnectionMode(mode);
  }

  void _saveAndConnect() {
    if (!_saveServer()) return;
    FocusScope.of(context).unfocus();
    _snack(switch (ref.read(settingsProvider).connectionMode) {
      ConnectionMode.server => 'Saved. Connecting to your PC…',
      ConnectionMode.mock => 'Saved. Choose My PC to connect.',
    });
  }

  /// In PC mode, saves the fields first so the test uses what was typed.
  Future<void> _testConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    final mode = ref.read(settingsProvider).connectionMode;
    if (mode == ConnectionMode.server && !_saveServer()) return;
    final target = switch (mode) {
      ConnectionMode.mock => 'the demo backend',
      ConnectionMode.server => 'your PC',
    };
    setState(() => _testing = true);
    String message;
    try {
      final rtt = await ref.read(backendProvider).ping();
      message = 'Connected to $target · ${rtt.inMilliseconds} ms';
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

    final isServer = settings.connectionMode == ConnectionMode.server;
    final link = ref.watch(connectionStatusProvider).value?.visual(context);
    final testButton = FilledButton.tonalIcon(
      onPressed: _testing ? null : _testConnection,
      icon: _testing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.network_ping),
      label: const Text('Test connection'),
    );

    final server = _SettingsSection(
      title: 'Server',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ConnectionMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ConnectionMode.mock,
                  icon: Icon(Icons.science_outlined),
                  label: Text('Demo data'),
                ),
                ButtonSegment(
                  value: ConnectionMode.server,
                  icon: Icon(Icons.computer),
                  label: Text('My PC'),
                ),
              ],
              selected: {settings.connectionMode},
              onSelectionChanged: (modes) => _setMode(modes.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'PC URL',
                hintText: 'https://my-pc.tailnet.ts.net',
                prefixIcon: const Icon(Icons.dns_outlined),
                errorText: _urlError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              obscureText: !_showToken,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Access token',
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  tooltip: _showToken ? 'Hide token' : 'Show token',
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
              onSubmitted: (_) => _saveAndConnect(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _saveAndConnect,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
                testButton,
              ],
            ),
            if (isServer && link != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  StatusDot(link),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      link.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: link.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
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
                      isServer
                          ? 'Run the server on your PC and reach it through '
                                'Tailscale. The token is the one in the '
                                "server's config.json."
                          : 'Showing built-in demo data. Choose My PC to '
                                'connect to the agents on your computer.',
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
                      if (!isServer) simulation,
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
                        children: [
                          if (!isServer) simulation,
                          notifications,
                          about,
                        ],
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
