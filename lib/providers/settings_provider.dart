/// In-memory app settings. Not persisted yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_providers.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.serverUrl = 'http://192.168.1.10:8787',
    this.simulate = true,
    this.notifyOnFailure = true,
    this.notifyOnComplete = false,
  });

  final ThemeMode themeMode;
  final String serverUrl;
  final bool simulate;
  final bool notifyOnFailure;
  final bool notifyOnComplete;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? serverUrl,
    bool? simulate,
    bool? notifyOnFailure,
    bool? notifyOnComplete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      serverUrl: serverUrl ?? this.serverUrl,
      simulate: simulate ?? this.simulate,
      notifyOnFailure: notifyOnFailure ?? this.notifyOnFailure,
      notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setServerUrl(String url) => state = state.copyWith(serverUrl: url);

  void setSimulate(bool value) {
    ref.read(backendProvider).setSimulationEnabled(value);
    state = state.copyWith(simulate: value);
  }

  void setNotifyOnFailure(bool value) =>
      state = state.copyWith(notifyOnFailure: value);

  void setNotifyOnComplete(bool value) =>
      state = state.copyWith(notifyOnComplete: value);
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
