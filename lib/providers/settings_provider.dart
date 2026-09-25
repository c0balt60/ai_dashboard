/// App settings, saved on the device with shared_preferences.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/models.dart';
import 'backend_providers.dart';

/// Where the app gets its data: the built-in demo data or the PC server.
enum ConnectionMode { mock, server }

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.connectionMode = ConnectionMode.mock,
    this.serverUrl = '',
    this.authToken = '',
    this.simulate = true,
    this.notifyOn = const {PushEvent.failed, PushEvent.replied},
  });

  /// The defaults for a fresh install. A release web build is normally served
  /// by the PC server itself, so it starts out pointed at its own origin.
  factory AppSettings.initial() => kIsWeb && kReleaseMode
      ? AppSettings(
          connectionMode: ConnectionMode.server,
          serverUrl: Uri.base.origin,
        )
      : const AppSettings();

  final ThemeMode themeMode;
  final ConnectionMode connectionMode;
  final String serverUrl;
  final String authToken;
  final bool simulate;

  /// What the PC should send this phone push notifications about.
  final Set<PushEvent> notifyOn;

  AppSettings copyWith({
    ThemeMode? themeMode,
    ConnectionMode? connectionMode,
    String? serverUrl,
    String? authToken,
    bool? simulate,
    Set<PushEvent>? notifyOn,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      connectionMode: connectionMode ?? this.connectionMode,
      serverUrl: serverUrl ?? this.serverUrl,
      authToken: authToken ?? this.authToken,
      simulate: simulate ?? this.simulate,
      notifyOn: notifyOn ?? this.notifyOn,
    );
  }
}

/// The device's preferences store. Loaded in `main` before the app starts;
/// null (as in tests) keeps settings in memory only.
final sharedPreferencesProvider = Provider<SharedPreferences?>((_) => null);

/// Whether [url] can be used as the PC server address.
bool isValidServerUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _prefix = 'settings.';

  /// One flag per event, named after the toggles that predate push.
  static const _notifyKeys = {
    PushEvent.failed: 'notifyOnFailure',
    PushEvent.completed: 'notifyOnComplete',
    PushEvent.replied: 'notifyOnReply',
    PushEvent.waiting: 'notifyOnWaiting',
  };

  SharedPreferences? get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final defaults = AppSettings.initial();
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs == null) return defaults;

    T byName<T extends Enum>(List<T> values, String key, T fallback) =>
        values.asNameMap()[prefs.getString('$_prefix$key')] ?? fallback;

    return AppSettings(
      themeMode: byName(ThemeMode.values, 'themeMode', defaults.themeMode),
      connectionMode: byName(
        ConnectionMode.values,
        'connectionMode',
        defaults.connectionMode,
      ),
      serverUrl: prefs.getString('${_prefix}serverUrl') ?? defaults.serverUrl,
      authToken: prefs.getString('${_prefix}authToken') ?? defaults.authToken,
      simulate: prefs.getBool('${_prefix}simulate') ?? defaults.simulate,
      notifyOn: {
        for (final event in PushEvent.values)
          if (prefs.getBool('$_prefix${_notifyKeys[event]}') ??
              defaults.notifyOn.contains(event))
            event,
      },
    );
  }

  void _save(String key, Object value) {
    final prefs = _prefs;
    if (prefs == null) return;
    switch (value) {
      case bool b:
        prefs.setBool('$_prefix$key', b);
      case Enum e:
        prefs.setString('$_prefix$key', e.name);
      default:
        prefs.setString('$_prefix$key', '$value');
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save('themeMode', mode);
  }

  /// Flips between light and dark based on what is showing now, so the first
  /// tap while following the system theme always changes something visible.
  void toggleBrightness(Brightness current) => setThemeMode(
    current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
  );

  void setConnectionMode(ConnectionMode mode) {
    state = state.copyWith(connectionMode: mode);
    _save('connectionMode', mode);
  }

  /// Saves the PC server address, dropping any trailing slash. Throws a
  /// [FormatException] for anything that isn't an http(s) URL.
  void setServerUrl(String url) {
    final trimmed = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!isValidServerUrl(trimmed)) {
      throw const FormatException('Enter an http:// or https:// address');
    }
    state = state.copyWith(serverUrl: trimmed);
    _save('serverUrl', trimmed);
  }

  void setAuthToken(String token) {
    state = state.copyWith(authToken: token.trim());
    _save('authToken', token.trim());
  }

  void setSimulate(bool value) {
    ref.read(backendProvider).setSimulationEnabled(value);
    state = state.copyWith(simulate: value);
    _save('simulate', value);
  }

  void setNotify(PushEvent event, bool value) {
    state = state.copyWith(
      notifyOn: value
          ? {...state.notifyOn, event}
          : state.notifyOn.difference({event}),
    );
    _save(_notifyKeys[event]!, value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
