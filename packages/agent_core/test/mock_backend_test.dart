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

  test('project chats keep their own history and move the agent', () async {
    final backend = MockAgentBackend(simulate: false, latency: Duration.zero);
    addTearDown(backend.dispose);

    final chat = await backend.createChat('a5', projectId: 'p3');
    await backend.sendPrompt(chat.id, 'Explain the build setup');

    final chats = await backend.watchChats().first;
    expect(
      chats.singleWhere((c) => c.id == chat.id).title,
      'Explain the build setup',
      reason: 'the first prompt names an untitled chat',
    );
    expect(await backend.watchMessages(chat.id).first, hasLength(2));
    expect(await backend.watchMessages('a5').first, isEmpty);
    final aider = (await backend.watchAgents().first).firstWhere(
      (a) => a.id == 'a5',
    );
    expect((aider.projectId, aider.projectIds), ('p3', ['p3']));

    await backend.setAgentProjects('a5', ['p1', 'p2']);
    final moved = (await backend.watchAgents().first).firstWhere(
      (a) => a.id == 'a5',
    );
    expect((moved.projectId, moved.projectIds), (null, ['p1', 'p2']));

    await backend.deleteChat('a5');
    await backend.deleteChat(chat.id);
    final left = await backend.watchChats().first;
    expect(left.where((c) => c.agentId == 'a5').map((c) => c.id), ['a5']);
  });

  test('a task from a to-do carries its notes and ticks the to-do off', () async {
    final backend = MockAgentBackend(simulate: false, latency: Duration.zero);
    addTearDown(backend.dispose);

    Future<TodoItem> item() async => (await backend.watchTodoLists().first)
        .firstWhere((l) => l.id == 'l1')
        .items
        .firstWhere((i) => i.id == 'i4');

    final task = await backend.createTask(
      'Write release notes',
      'p1',
      agentId: 'a5',
      description: 'Cover chats per project.',
      todo: const TodoLink(listId: 'l1', itemId: 'i4'),
    );
    expect(task.brief, contains('Cover chats per project.'));

    await backend.updateTaskState(task.id, TaskState.completed);
    expect((await item()).done, isTrue);
    expect((await item()).completedAt, isNotNull);

    await backend.updateTaskState(task.id, TaskState.waiting);
    expect((await item()).done, isFalse);
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
