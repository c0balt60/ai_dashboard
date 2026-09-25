import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard_server/push/push_notifier.dart';
import 'package:test/test.dart';

class FakeSender implements PushSender {
  final sent = <(String, PushMessage)>[];
  final unregistered = <String>{};

  @override
  Future<bool> send(String token, PushMessage message) async {
    if (unregistered.contains(token)) return false;
    sent.add((token, message));
    return true;
  }

  @override
  void close() {}
}

void main() {
  late MockAgentBackend backend;
  late Directory dataDir;
  late FakeSender sender;
  late PushNotifier push;

  PushNotifier start({PushSender? via}) => PushNotifier(
    backend,
    dataDir: dataDir.path,
    sender: via,
    settle: const Duration(milliseconds: 20),
  );

  /// Lets the first snapshots arrive, or the settle window pass.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  setUp(() async {
    backend = MockAgentBackend(simulate: false, latency: Duration.zero);
    dataDir = await Directory.systemTemp.createTemp('push');
    sender = FakeSender();
    push = start(via: sender);
    await settle();
  });

  tearDown(() async {
    push.dispose();
    backend.dispose();
    await dataDir.delete(recursive: true);
  });

  List<PushMessage> sentTo(String token) => [
    for (final (t, m) in sender.sent)
      if (t == token) m,
  ];

  test('a chat reply sends each device the event it asked for', () async {
    push
      ..register(
        const PushDevice(
          token: 'replies',
          events: {PushEvent.replied, PushEvent.waiting},
        ),
      )
      ..register(
        const PushDevice(token: 'waiting', events: {PushEvent.waiting}),
      )
      ..register(
        const PushDevice(token: 'tasks', events: {PushEvent.completed}),
      );

    await backend.sendPrompt('a5', 'Hello there');
    await settle();

    final [reply] = sentTo('replies');
    expect(reply.title, 'Aider');
    expect(reply.data, {'agentId': 'a5', 'chatId': 'a5'});
    final [waiting] = sentTo('waiting');
    expect(waiting.title, 'Aider is waiting for you');
    expect(sentTo('tasks'), isEmpty);
  });

  test('only tasks an agent was working on notify', () async {
    push.register(
      const PushDevice(
        token: 'phone',
        events: {PushEvent.failed, PushEvent.completed, PushEvent.waiting},
      ),
    );

    await backend.updateTaskState('t1', TaskState.failed);
    final task = await backend.createTask('By hand', 'p1');
    await backend.updateTaskState(task.id, TaskState.completed);
    await settle();

    final [failed] = sentTo('phone');
    expect(failed.title, 'Claude #1 failed a task');
    expect(failed.body, startsWith('Implement Stripe webhook handler'));
    expect(failed.data, {'projectId': 'p2', 'agentId': 'a1'});
  });

  test('devices persist, unregister, and are dropped once FCM forgets '
      'them', () async {
    push
      ..register(const PushDevice(token: 'old', events: {PushEvent.waiting}))
      ..register(const PushDevice(token: 'gone', events: {PushEvent.waiting}))
      ..register(const PushDevice(token: 'kept', events: {PushEvent.waiting}))
      ..register(const PushDevice(token: 'old', events: {}));
    sender.unregistered.add('gone');

    await backend.sendPrompt('a5', 'Hi');
    await settle();
    expect(sender.sent.map((s) => s.$1), ['kept']);

    push.dispose();
    push = start();
    expect(push.devices.map((d) => d.token), ['kept']);
    expect(push.canSend, isFalse);
    expect(() => push.sendTest('kept'), throwsA(isA<PushException>()));
  });
}
