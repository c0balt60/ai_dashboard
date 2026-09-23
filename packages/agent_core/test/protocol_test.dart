import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('frames round-trip and messages topics carry the agent id', () {
    for (final frame in [
      const SubscribeFrame('agents'),
      const UnsubscribeFrame('tasks'),
      SnapshotFrame(Topics.messages('a1'), const [
        {'id': 'm1'},
      ]),
      const ErrorFrame('nope', topic: 'x'),
    ]) {
      final json = jsonDecode(jsonEncode(frame.toJson())) as Json;
      expect(Frame.fromJson(json).toJson(), frame.toJson());
    }
    expect(Topics.messagesAgent(Topics.messages('a7')), 'a7');
    expect(Topics.messagesAgent(Topics.agents), isNull);
  });

  test('watchTopicJson serves each topic from the backend', () async {
    final backend = MockAgentBackend(simulate: false, latency: Duration.zero);
    addTearDown(backend.dispose);

    final agents = await watchTopicJson(backend, Topics.agents)!.first;
    expect(agents.map(Agent.fromJson).map((a) => a.id), contains('a1'));
    expect(
      await watchTopicJson(backend, Topics.messages('a1'))!.first,
      isNotEmpty,
    );
    expect(watchTopicJson(backend, 'bogus'), isNull);
  });
}
