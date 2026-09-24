import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:agent_core/src/backend/mock_seed.dart';
import 'package:test/test.dart';

/// Encodes [value], sends it through a JSON string and decodes it again, then
/// compares the re-encoded form so every field is checked.
void expectRoundTrip<T>(
  T value,
  Json Function(T) toJson,
  T Function(Json) fromJson,
) {
  final encoded = jsonEncode(toJson(value));
  final decoded = fromJson(jsonDecode(encoded) as Json);
  expect(jsonEncode(toJson(decoded)), encoded);
}

void main() {
  final seed = MockSeed(DateTime(2030, 3, 14, 9, 30));

  test('every seeded model survives a JSON round trip', () {
    for (final a in seed.agents) {
      expectRoundTrip(a, (v) => v.toJson(), Agent.fromJson);
    }
    for (final p in seed.projects) {
      expectRoundTrip(p, (v) => v.toJson(), Project.fromJson);
    }
    for (final t in seed.tasks) {
      expectRoundTrip(t, (v) => v.toJson(), AgentTask.fromJson);
    }
    for (final c in seed.chats) {
      expectRoundTrip(c, (v) => v.toJson(), AgentChat.fromJson);
    }
    for (final list in seed.messages.values) {
      for (final m in list) {
        expectRoundTrip(m, (v) => v.toJson(), ChatMessage.fromJson);
      }
    }
    for (final l in seed.todoLists) {
      expectRoundTrip(l, (v) => v.toJson(), TodoList.fromJson);
    }
  });

  test('agents and tasks saved by older versions still load', () {
    final agent = Agent.fromJson({
      'id': 'a1',
      'name': 'Claude',
      'type': 'claudeCode',
      'status': 'idle',
      'lastActive': '2030-01-01T00:00:00.000Z',
      'projectId': 'p1',
    });
    expect(agent.projectIds, ['p1']);
    final task = AgentTask.fromJson({
      'id': 't1',
      'title': 'Ship',
      'projectId': 'p1',
      'state': 'backlog',
      'createdAt': '2030-01-01T00:00:00.000Z',
      'updatedAt': '2030-01-01T00:00:00.000Z',
    });
    expect((task.description, task.todo), ('', null));
    expect(task.brief, 'Task: Ship');
  });

  test(
    'to-do dates keep their calendar day and instants keep their moment',
    () {
      final item = TodoItem(
        id: 'i1',
        title: 'Ship',
        createdAt: DateTime(2030, 1, 2, 23, 59),
        dueDate: DateTime(2030, 1, 15),
      );
      final json = jsonDecode(jsonEncode(item.toJson())) as Json;
      expect(json['dueDate'], '2030-01-15');
      final back = TodoItem.fromJson(json);
      expect(back.dueDate, DateTime(2030, 1, 15));
      expect(back.createdAt, item.createdAt);
      expect(back.startDate, isNull);
    },
  );
}
