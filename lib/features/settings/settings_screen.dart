import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/backend_providers.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';

/// Settings tab: PC connection, simulation, appearance and notifications.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _appName = 'AI Dashboard';
  static const _version = '1.0.0';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionHeader('Server'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
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
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
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
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
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
          ),
          const SectionHeader('Simulation'),
          SwitchListTile(
            secondary: const Icon(Icons.auto_mode),
            title: const Text('Simulate live activity'),
            subtitle: const Text(
              'Mock agents make progress and finish or fail tasks on their own',
            ),
            value: settings.simulate,
            onChanged: notifier.setSimulate,
          ),
          const SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
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
                onSelectionChanged: (modes) =>
                    notifier.setThemeMode(modes.first),
              ),
            ),
          ),
          const SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.error_outline),
            title: const Text('Agent or task failed'),
            subtitle: const Text('Push notifications are not wired up yet'),
            value: settings.notifyOnFailure,
            onChanged: notifier.setNotifyOnFailure,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.task_alt),
            title: const Text('Task completed'),
            subtitle: const Text('Push notifications are not wired up yet'),
            value: settings.notifyOnComplete,
            onChanged: notifier.setNotifyOnComplete,
          ),
          const SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.smart_toy_outlined),
            title: Text(_appName),
            subtitle: Text('Version $_version'),
          ),
        ],
      ),
    );
  }
}
