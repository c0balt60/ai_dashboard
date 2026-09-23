import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard_server/api.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

const token = 'test-token-0123456789abcdef';

void main() {
  late MockAgentBackend backend;
  late HttpServer server;
  late Uri base;
  late Directory web;

  setUp(() async {
    backend = MockAgentBackend(simulate: false, latency: Duration.zero);
    web = await Directory.systemTemp.createTemp('web');
    File('${web.path}/index.html').writeAsStringSync('<html>app</html>');
    server = await shelf_io.serve(
      buildHandler(backend, token: token, webRoot: web.path),
      '127.0.0.1',
      0,
    );
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
    backend.dispose();
    await web.delete(recursive: true);
  });

  Map<String, String> auth([String t = token]) => {
    'authorization': 'Bearer $t',
    'content-type': 'application/json',
  };

  test('the API rejects requests without the token', () async {
    final none = await http.get(base.resolve(ApiPaths.ping));
    final wrong = await http.get(
      base.resolve(ApiPaths.ping),
      headers: auth('nope'),
    );
    final right = await http.get(base.resolve(ApiPaths.ping), headers: auth());
    expect(
      [none.statusCode, wrong.statusCode, right.statusCode],
      [401, 401, 200],
    );
  });

  test('actions reach the backend and return created models', () async {
    final created = await http.post(
      base.resolve(ApiPaths.tasks),
      headers: auth(),
      body: jsonEncode({'title': 'Write docs', 'projectId': 'p1'}),
    );
    expect(created.statusCode, 200);
    final task = AgentTask.fromJson(jsonDecode(created.body) as Json);
    expect(task.state, TaskState.backlog);

    final moved = await http.put(
      base.resolve(ApiPaths.taskState(task.id)),
      headers: auth(),
      body: jsonEncode({'state': 'completed'}),
    );
    expect(moved.statusCode, 200);
    final tasks = await backend.watchTasks().first;
    expect(tasks.firstWhere((t) => t.id == task.id).state, TaskState.completed);

    final bad = await http.post(
      base.resolve(ApiPaths.tasks),
      headers: auth(),
      body: jsonEncode({'title': 1}),
    );
    expect(bad.statusCode, 400);
  });

  test('the WebSocket streams snapshots for subscribed topics', () async {
    final channel = IOWebSocketChannel.connect(
      base.replace(
        scheme: 'ws',
        path: ApiPaths.ws,
        queryParameters: {ApiPaths.tokenQuery: token},
      ),
    );
    addTearDown(channel.sink.close);
    final frames = StreamIterator(
      channel.stream.map((raw) => Frame.fromJson(jsonDecode(raw) as Json)),
    );

    channel.sink.add(
      jsonEncode(SubscribeFrame(Topics.messages('a5')).toJson()),
    );
    expect(await frames.moveNext(), isTrue);
    final first = frames.current as SnapshotFrame;
    expect(first.topic, Topics.messages('a5'));

    await backend.sendPrompt('a5', 'hello');
    SnapshotFrame latest = first;
    while (latest.data.length < first.data.length + 2) {
      expect(await frames.moveNext(), isTrue);
      latest = frames.current as SnapshotFrame;
    }
    expect(ChatMessage.fromJson(latest.data.last).role, MessageRole.agent);
  });

  test('unknown paths fall back to the web app', () async {
    final deepLink = await http.get(base.resolve('/agent/a1'));
    expect(deepLink.statusCode, 200);
    expect(deepLink.body, contains('app'));
    final missingApi = await http.get(
      base.resolve('/api/nope'),
      headers: auth(),
    );
    expect(missingApi.statusCode, 404);
  });
}
