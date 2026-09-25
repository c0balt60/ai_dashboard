import 'json.dart';

/// Something the PC can send a push notification about, most important
/// first: when one agent update matches several, the first one wins.
enum PushEvent {
  /// A task or a chat turn failed.
  failed,

  /// An agent finished a task.
  completed,

  /// An agent answered in a chat.
  replied,

  /// An agent is free and waiting for its next instruction.
  waiting,
}

/// A phone registered for push notifications: its FCM registration token and
/// the events it wants to hear about.
class PushDevice {
  const PushDevice({required this.token, required this.events});

  factory PushDevice.fromJson(Json json) => PushDevice(
    token: json['token'] as String,
    events: {
      for (final name in decodeStrings(json['events']))
        ?PushEvent.values.asNameMap()[name],
    },
  );

  final String token;
  final Set<PushEvent> events;

  Json toJson() => {
    'token': token,
    'events': [for (final e in events) e.name],
  };
}
