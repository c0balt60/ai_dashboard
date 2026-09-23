import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard/data/backend/http_backend.dart';
import 'package:ai_dashboard_server/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:web_socket_channel/web_socket_channel.dart';

const token = 'test-token-0123456789abcdef';

void main() {
  late MockAgentBackend mock;
  late Handler handler;
  late HttpServer server;
  late HttpAgentBackend backend;
  late List<WebSocketChannel> sockets;

  setUp(() async {
    mock = MockAgentBackend(simulate: false, latency: Duration.zero);
    handler = buildHandler(mock, token: token);
    server = await shelf_io.serve(handler, '127.0.0.1', 0);
    sockets = [];
    backend = HttpAgentBackend(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      token: token,
      connect: (uri) {
        final socket = WebSocketChannel.connect(uri);
        sockets.add(socket);
        return socket;
      },
    );
  });

  tearDown(() async {
    backend.dispose();
    await server.close(force: true);
    mock.dispose();
  });

  Future<void> waitFor(ConnectionStatus status) => backend.connection
      .firstWhere((s) => s == status)
      .timeout(const Duration(seconds: 10));

  test('streams and actions round-trip through the PC server', () async {
    await waitFor(ConnectionStatus.connected);

    final agents = await backend.watchAgents().first;
    final mockAgents = await mock.watchAgents().first;
    expect(agents.map((a) => a.id), mockAgents.map((a) => a.id));

    final task = await backend.createTask('Ship it', 'p1', agentId: 'a1');
    expect(task.state, TaskState.waiting);
    await backend
        .watchTasks()
        .firstWhere((tasks) => tasks.any((t) => t.id == task.id))
        .timeout(const Duration(seconds: 5));

    final list = await backend.createTodoList('Release');
    final item = await backend.addTodoItem(
      list.id,
      title: 'Changelog',
      dueDate: DateTime(2030, 1, 15),
    );
    expect(item.dueDate, DateTime(2030, 1, 15));

    expect(await backend.runCommand('p1', 'git status'), isNotEmpty);
    expect(await backend.ping(), isA<Duration>());
  });

  test('a wrong token fails requests with the server message', () async {
    final intruder = HttpAgentBackend(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      token: 'wrong',
    );
    addTearDown(intruder.dispose);
    await expectLater(
      intruder.ping(),
      throwsA(
        isA<BackendException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Unauthorized'),
      ),
    );
  });

  test('reconnects and re-subscribes after the connection drops', () async {
    final snapshots = <List<Agent>>[];
    final subscription = backend.watchAgents().listen(snapshots.add);
    addTearDown(subscription.cancel);
    await waitFor(ConnectionStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final before = snapshots.length;
    expect(before, greaterThan(0));

    final offline = waitFor(ConnectionStatus.offline);
    await sockets.single.sink.close();
    await offline;

    await waitFor(ConnectionStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(sockets, hasLength(2));
    expect(snapshots.length, greaterThan(before));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
