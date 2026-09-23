import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

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
  test('to-do items keep their tags and dates, and ticking them off stamps '
      'completedAt', () async {
    final backend = MockAgentBackend(simulate: false, latency: Duration.zero);
    addTearDown(backend.dispose);

    Future<TodoList> list(String id) async =>
        (await backend.watchTodoLists().first).firstWhere((l) => l.id == id);

    final created = await backend.createTodoList('Launch');
    final due = DateTime(2030, 1, 15);
    final item = await backend.addTodoItem(
      created.id,
      title: 'Ship webhooks',
      projectIds: ['p2'],
      agentIds: ['a1', 'a3'],
      startDate: DateTime(2030, 1, 10),
      dueDate: due,
    );

    var stored = (await list(created.id)).items.single;
    expect(stored.projectIds, ['p2']);
    expect(stored.agentIds, ['a1', 'a3']);
    expect(stored.dueDate, due);
    expect((await list(created.id)).timelineEnd, due);

    await backend.updateTodoItem(created.id, item.copyWith(done: true));
    stored = (await list(created.id)).items.single;
    expect(stored.done, isTrue);
    expect(stored.completedAt, isNotNull);

    await backend.updateTodoItem(created.id, stored.copyWith(done: false));
    expect((await list(created.id)).items.single.completedAt, isNull);

    await backend.deleteTodoItem(created.id, item.id);
    expect((await list(created.id)).items, isEmpty);

    await backend.deleteTodoList(created.id);
    final lists = await backend.watchTodoLists().first;
    expect(lists.any((l) => l.id == created.id), isFalse);
  });
}
