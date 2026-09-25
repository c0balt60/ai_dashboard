import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/push_provider.dart';
import '../../providers/settings_provider.dart';

/// The Notifications card on Android: where push stands, a toggle per event
/// and a button that asks the PC for a test notification.
class PushSettings extends ConsumerStatefulWidget {
  const PushSettings({super.key});

  @override
  ConsumerState<PushSettings> createState() => _PushSettingsState();
}

class _PushSettingsState extends ConsumerState<PushSettings> {
  bool _testing = false;

  static const _toggles = [
    (
      PushEvent.failed,
      Icons.error_outline,
      'Agent or task failed',
      'A task or a chat turn ends with an error',
    ),
    (
      PushEvent.completed,
      Icons.task_alt,
      'Task completed',
      'An agent finishes a task',
    ),
    (
      PushEvent.replied,
      Icons.chat_bubble_outline,
      'Chat replies',
      'An agent answers you in a chat',
    ),
    (
      PushEvent.waiting,
      Icons.hourglass_empty,
      'Waiting for you',
      'An agent is free for its next instruction',
    ),
  ];

  Future<void> _sendTest() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    String message;
    try {
      await ref.read(pushProvider.notifier).sendTest();
      message = 'Sent. It should arrive in a few seconds.';
    } catch (e) {
      message = 'Test failed: $e';
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
    final push = ref.watch(pushProvider);
    final notifyOn = ref.watch(settingsProvider.select((s) => s.notifyOn));
    final notifier = ref.read(settingsProvider.notifier);

    final (statusIcon, color, text) = switch (push.status) {
      PushStatus.on => (
        Icons.notifications_active_outlined,
        scheme.primary,
        'On. Your PC sends updates to this phone.',
      ),
      PushStatus.off => (
        Icons.notifications_off_outlined,
        scheme.onSurfaceVariant,
        'Off. Turn on an event below to get notifications.',
      ),
      PushStatus.demo => (
        Icons.notifications_off_outlined,
        scheme.onSurfaceVariant,
        'Choose My PC above to get notifications from your agents.',
      ),
      PushStatus.offline => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        'Waiting for the connection to your PC.',
      ),
      PushStatus.starting || PushStatus.unsupported => (
        Icons.notifications_none,
        scheme.onSurfaceVariant,
        'Setting up notifications…',
      ),
      PushStatus.noFirebase => (
        Icons.warning_amber_rounded,
        scheme.error,
        'This build has no Firebase config, so it can\'t receive '
            'notifications.',
      ),
      PushStatus.denied => (
        Icons.block,
        scheme.error,
        'Notifications are blocked. Allow them for this app in Android '
            'settings.',
      ),
      PushStatus.pcCantSend => (
        Icons.warning_amber_rounded,
        scheme.error,
        "Your PC can't send notifications yet. Set firebaseServiceAccount "
            "in the server's config.json.",
      ),
      PushStatus.failed => (
        Icons.error_outline,
        scheme.error,
        "Couldn't set up notifications: ${push.error ?? 'unknown error'}",
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(statusIcon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
          if (push.status == PushStatus.on)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  onPressed: _testing ? null : _sendTest,
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Send a test'),
                ),
              ),
            ),
          for (final (i, (event, icon, title, subtitle))
              in _toggles.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 72, endIndent: 16),
            SwitchListTile(
              secondary: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              value: notifyOn.contains(event),
              onChanged: (value) => notifier.setNotify(event, value),
            ),
          ],
        ],
      ),
    );
  }
}
