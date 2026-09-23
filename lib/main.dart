import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'data/backend/http_backend.dart';
import 'providers/settings_provider.dart';

Future<void> main() async {
  // Clean /dashboard style URLs on the web instead of /#/dashboard.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Most screens fire backend actions without awaiting them; surface failed
  // requests to the PC instead of dropping them silently.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is! BackendException) return false;
    rootMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const App(),
    ),
  );
}
