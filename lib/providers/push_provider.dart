/// Push notifications from the PC server, on Android only.
///
/// [pushProvider] keeps the PC's registration of this phone in step with the
/// notification settings: whenever the link to the PC comes up, the events
/// change or FCM rotates the token, it sends the PC this phone's token and
/// the events it wants. Tapping a notification opens what it is about.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app.dart';
import '../app/router.dart';
import '../data/backend/http_backend.dart';
import '../data/models/models.dart';
import '../data/push/push_messaging.dart';
import 'backend_providers.dart';
import 'settings_provider.dart';

/// Push is for the phone app; web and desktop builds don't offer it.
bool get pushSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final pushMessagingProvider = Provider<PushMessaging?>(
  (_) => pushSupported ? FirebasePushMessaging() : null,
);

enum PushStatus {
  unsupported,
  demo,
  offline,
  off,
  starting,
  noFirebase,
  denied,
  pcCantSend,
  on,
  failed,
}

class PushState {
  const PushState(this.status, {this.error});

  final PushStatus status;
  final String? error;
}

class PushController extends Notifier<PushState> {
  String? _token;
  var _attached = false;

  @override
  PushState build() {
    final messaging = ref.watch(pushMessagingProvider);
    if (messaging == null) return const PushState(PushStatus.unsupported);
    final backend = ref.watch(backendProvider);
    if (backend is! HttpAgentBackend) return const PushState(PushStatus.demo);
    final events = ref.watch(settingsProvider.select((s) => s.notifyOn));
    _attach(messaging);

    final connected = ref.watch(
      connectionStatusProvider.select(
        (s) => s.value == ConnectionStatus.connected,
      ),
    );
    if (!connected) return const PushState(PushStatus.offline);

    var current = true;
    ref.onDispose(() => current = false);
    _register(messaging, backend, events, () => current);
    return PushState(events.isEmpty ? PushStatus.off : PushStatus.starting);
  }

  Future<void> _register(
    PushMessaging messaging,
    HttpAgentBackend backend,
    Set<PushEvent> events,
    bool Function() isCurrent,
  ) async {
    void report(PushStatus status, {String? error}) {
      if (isCurrent()) state = PushState(status, error: error);
    }

    if (!await messaging.init()) {
      return report(events.isEmpty ? PushStatus.off : PushStatus.noFirebase);
    }
    if (events.isNotEmpty && !await messaging.requestPermission()) {
      return report(PushStatus.denied);
    }
    try {
      final token = _token = await messaging.getToken();
      if (token == null) {
        return report(PushStatus.failed, error: 'FCM gave this phone no token');
      }
      final enabled = await backend.registerPushDevice(
        PushDevice(token: token, events: events),
      );
      report(switch ((events.isEmpty, enabled)) {
        (true, _) => PushStatus.off,
        (false, true) => PushStatus.on,
        (false, false) => PushStatus.pcCantSend,
      });
    } on Object catch (e) {
      report(events.isEmpty ? PushStatus.off : PushStatus.failed, error: '$e');
    }
  }

  /// Hooks up token refreshes and notification taps once per app run.
  Future<void> _attach(PushMessaging messaging) async {
    if (_attached) return;
    _attached = true;
    if (!await messaging.init()) return;
    messaging.onTokenRefresh.listen((_) => ref.invalidateSelf());
    messaging.onOpened.listen(_open);
    messaging.onForeground.listen(_showInApp);
    if (await messaging.initialOpened() case final push?) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(push));
    }
  }

  /// Asks the PC to send this phone a notification.
  Future<void> sendTest() async {
    final (backend, token) = (ref.read(backendProvider), _token);
    if (backend is! HttpAgentBackend || token == null) {
      throw BackendException('Notifications are not set up yet');
    }
    await backend.sendTestPush(token);
  }

  static String? routeFor(Map<String, Object?> data) => switch (data) {
    {'agentId': final String agent, 'chatId': final String chat} =>
      AppRoutes.agent(agent, chatId: chat),
    {'projectId': final String project} => AppRoutes.project(project),
    {'agentId': final String agent} => AppRoutes.agent(agent),
    _ => null,
  };

  void _open(IncomingPush push) {
    if (routeFor(push.data) case final route?) {
      ref.read(routerProvider).push(route);
    }
  }

  /// Android leaves foreground notifications to the app, so show a snackbar,
  /// unless the screen it points at is already open.
  void _showInApp(IncomingPush push) {
    final route = routeFor(push.data);
    final router = ref.read(routerProvider);
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (route != null && Uri.parse(route).path == here) return;
    final text = [?push.title, ?push.body].join(': ');
    if (text.isEmpty) return;
    rootMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
          action: route == null
              ? null
              : SnackBarAction(label: 'Open', onPressed: () => _open(push)),
        ),
      );
  }
}

final pushProvider = NotifierProvider<PushController, PushState>(
  PushController.new,
);
