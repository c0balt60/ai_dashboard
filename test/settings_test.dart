import 'package:ai_dashboard/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('settings persist across restarts and reject bad URLs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer start() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    final first = start();
    final notifier = first.read(settingsProvider.notifier)
      ..setServerUrl('https://my-pc.tailnet.ts.net/')
      ..setAuthToken(' secret ')
      ..setThemeMode(ThemeMode.dark)
      ..setConnectionMode(ConnectionMode.server);
    expect(() => notifier.setServerUrl('my-pc:8787'), throwsFormatException);
    first.dispose();

    final second = start();
    addTearDown(second.dispose);
    final settings = second.read(settingsProvider);
    expect(settings.serverUrl, 'https://my-pc.tailnet.ts.net');
    expect(settings.authToken, 'secret');
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.connectionMode, ConnectionMode.server);
  });
}
