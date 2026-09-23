import 'package:ai_dashboard/data/backend/mock_backend.dart';
import 'package:ai_dashboard/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sendPrompt runs the agent, then posts a reply and waits', () async {
    final backend = MockAgentBackend(simulate: false, latency: Duration.zero);
    addTearDown(backend.dispose);

    Future<Agent> aider() async =>
        (await backend.watchAgents().first).firstWhere((a) => a.id == 'a5');

    final sending = backend.sendPrompt('a5', 'Run the tests');
    expect((await aider()).status, AgentStatus.running);

    await sending;
    final messages = await backend.watchMessages('a5').first;
    expect(messages.map((m) => m.role), [MessageRole.user, MessageRole.agent]);
    expect((await aider()).status, AgentStatus.waiting);
  });
}
