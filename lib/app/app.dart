import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/push_provider.dart';
import '../providers/settings_provider.dart';
import 'router.dart';
import 'theme.dart';

/// Shows snackbars from outside the widget tree, such as backend errors that
/// no screen awaited.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps this phone's push registration in step with the settings.
    ref.listen(pushProvider, (_, _) {});
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Agent Dashboard',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      scrollBehavior: const _AppScrollBehavior(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Lets a mouse drag scroll lists too, so horizontal chip rows and carousels
/// work in a desktop browser without a trackpad.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
