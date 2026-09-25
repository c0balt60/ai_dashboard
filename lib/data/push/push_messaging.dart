import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// A notification from the PC, as the app sees it.
class IncomingPush {
  const IncomingPush({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;

  /// What to open: `agentId`, `chatId` and `projectId`, as the server's
  /// PushNotifier sends them.
  final Map<String, Object?> data;
}

/// The phone's push channel. [FirebasePushMessaging] in the app, a fake in
/// tests.
abstract interface class PushMessaging {
  /// Starts the push service once. False when this build has no Firebase
  /// config (`android/app/google-services.json`).
  Future<bool> init();

  /// Asks for permission to show notifications if it hasn't been granted.
  /// False when the user blocked them.
  Future<bool> requestPermission();

  Future<String?> getToken();

  Stream<String> get onTokenRefresh;

  /// Notifications that arrive while the app is in the foreground, which
  /// Android doesn't show by itself.
  Stream<IncomingPush> get onForeground;

  /// Notifications tapped while the app was running in the background.
  Stream<IncomingPush> get onOpened;

  /// The notification whose tap launched the app, if any.
  Future<IncomingPush?> initialOpened();
}

class FirebasePushMessaging implements PushMessaging {
  Future<bool>? _ready;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> init() => _ready ??= _init();

  Future<bool> _init() async {
    try {
      await Firebase.initializeApp();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional => true,
      _ => false,
    };
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<IncomingPush> get onForeground =>
      FirebaseMessaging.onMessage.map(_toPush);

  @override
  Stream<IncomingPush> get onOpened =>
      FirebaseMessaging.onMessageOpenedApp.map(_toPush);

  @override
  Future<IncomingPush?> initialOpened() async =>
      switch (await _messaging.getInitialMessage()) {
        final message? => _toPush(message),
        null => null,
      };

  static IncomingPush _toPush(RemoteMessage message) => IncomingPush(
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );
}
