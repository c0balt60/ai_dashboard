import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'push/push_notifier.dart';

/// The server's HTTP entry point.
///
/// Exposes [backend] under `/api` as described in `protocol.dart`, guarded by
/// [token], and serves the built web app from [webRoot] for every other path,
/// falling back to `index.html` so the app's path URLs survive a reload.
/// Phones register for notifications with [push]; without it they are told
/// the PC can't send any.
Handler buildHandler(
  AgentBackend backend, {
  required String token,
  String? webRoot,
  List<String> corsOrigins = const [],
  PushNotifier? push,
}) {
  final api = _apiRouter(backend, push);
  final socket = webSocketHandler(
    (WebSocketChannel channel, String? _) => _serveSocket(backend, channel),
    pingInterval: const Duration(seconds: 20),
  );

  FutureOr<Response> handleApi(Request request) {
    if ('/${request.url.path}' == ApiPaths.ws) return socket(request);
    return api.call(request);
  }

  final guarded = const Pipeline()
      .addMiddleware(_cors(corsOrigins))
      .addMiddleware(_auth(token))
      .addHandler(handleApi);

  final web = webRoot != null && Directory(webRoot).existsSync()
      ? _webApp(webRoot)
      : null;

  return (request) {
    final path = request.url.path;
    if (path == 'api' || path.startsWith('api/')) return guarded(request);
    return web?.call(request) ?? Response.notFound('Web app not built.');
  };
}

Router _apiRouter(AgentBackend backend, PushNotifier? push) {
  Future<Response> action(
    Request request,
    FutureOr<Object?> Function(Json body) run,
  ) async {
    try {
      final text = await request.readAsString();
      final body = text.isEmpty ? const <String, Object?>{} : jsonDecode(text);
      final result = await run(body as Json);
      return _json(result ?? const {'ok': true});
    } on FormatException catch (e) {
      return _json({'error': e.message}, status: 400);
    } on TypeError catch (e) {
      return _json({'error': 'Bad request body: $e'}, status: 400);
    } on ArgumentError catch (e) {
      return _json({'error': '${e.message}'}, status: 400);
    } catch (e) {
      return _json({'error': '$e'}, status: 500);
    }
  }

  return Router(
      notFoundHandler: (_) => _json({'error': 'Not found'}, status: 404),
    )
    ..get(ApiPaths.ping, (Request r) => _json({'ok': true}))
    ..post(
      ApiPaths.simulation,
      (Request r) => action(r, (b) {
        backend.setSimulationEnabled(b['enabled'] as bool);
        return null;
      }),
    )
    ..post(
      ApiPaths.chats,
      (Request r) => action(r, (b) async {
        final chat = await backend.createChat(
          b['agentId'] as String,
          projectId: b['projectId'] as String?,
          title: b['title'] as String? ?? '',
        );
        return chat.toJson();
      }),
    )
    ..patch(
      ApiPaths.chat('<id>'),
      (Request r, String id) =>
          action(r, (b) => backend.renameChat(id, b['title'] as String)),
    )
    ..delete(
      ApiPaths.chat('<id>'),
      (Request r, String id) => action(r, (_) => backend.deleteChat(id)),
    )
    ..post(
      ApiPaths.prompt('<id>'),
      (Request r, String id) =>
          action(r, (b) => backend.sendPrompt(id, b['text'] as String)),
    )
    ..put(
      ApiPaths.agentProjects('<id>'),
      (Request r, String id) => action(
        r,
        (b) => backend.setAgentProjects(id, decodeStrings(b['projectIds'])),
      ),
    )
    ..post(
      ApiPaths.assign('<id>'),
      (Request r, String id) => action(
        r,
        (b) => backend.assignAgent(
          id,
          projectId: b['projectId'] as String,
          workingDir: b['workingDir'] as String,
          taskId: b['taskId'] as String?,
        ),
      ),
    )
    ..post(
      ApiPaths.stop('<id>'),
      (Request r, String id) => action(r, (_) => backend.stopAgent(id)),
    )
    ..delete(
      ApiPaths.clearMessages('<id>'),
      (Request r, String id) => action(r, (_) => backend.clearMessages(id)),
    )
    ..post(
      ApiPaths.tasks,
      (Request r) => action(r, (b) async {
        final task = await backend.createTask(
          b['title'] as String,
          b['projectId'] as String,
          agentId: b['agentId'] as String?,
          description: b['description'] as String? ?? '',
          todo: switch (b['todo']) {
            final Json link => TodoLink.fromJson(link),
            _ => null,
          },
        );
        return task.toJson();
      }),
    )
    ..put(
      ApiPaths.taskState('<id>'),
      (Request r, String id) => action(
        r,
        (b) => backend.updateTaskState(
          id,
          TaskState.values.byName(b['state'] as String),
        ),
      ),
    )
    ..post(
      ApiPaths.todoLists,
      (Request r) => action(r, (b) async {
        final list = await backend.createTodoList(b['title'] as String);
        return list.toJson();
      }),
    )
    ..patch(
      ApiPaths.todoList('<id>'),
      (Request r, String id) =>
          action(r, (b) => backend.renameTodoList(id, b['title'] as String)),
    )
    ..delete(
      ApiPaths.todoList('<id>'),
      (Request r, String id) => action(r, (_) => backend.deleteTodoList(id)),
    )
    ..post(
      ApiPaths.todoItems('<id>'),
      (Request r, String id) => action(r, (b) async {
        final item = await backend.addTodoItem(
          id,
          title: b['title'] as String,
          note: b['note'] as String? ?? '',
          projectIds: decodeStrings(b['projectIds']),
          agentIds: decodeStrings(b['agentIds']),
          startDate: decodeDayOrNull(b['startDate']),
          dueDate: decodeDayOrNull(b['dueDate']),
        );
        return item.toJson();
      }),
    )
    ..put(
      ApiPaths.todoItem('<id>', '<itemId>'),
      (Request r, String id, String itemId) =>
          action(r, (b) => backend.updateTodoItem(id, TodoItem.fromJson(b))),
    )
    ..delete(
      ApiPaths.todoItem('<id>', '<itemId>'),
      (Request r, String id, String itemId) =>
          action(r, (_) => backend.deleteTodoItem(id, itemId)),
    )
    ..post(
      ApiPaths.runCommand('<id>'),
      (Request r, String id) => action(r, (b) async {
        final output = await backend.runCommand(id, b['command'] as String);
        return {'output': output};
      }),
    )
    ..put(
      ApiPaths.pushDevice,
      (Request r) => action(r, (b) {
        push?.register(PushDevice.fromJson(b));
        return {'enabled': push?.canSend ?? false};
      }),
    )
    ..post(ApiPaths.pushTest, (Request r) {
      if (push == null || !push.canSend) {
        return _json({
          'error': PushNotifier.notConfiguredMessage,
        }, status: HttpStatus.serviceUnavailable);
      }
      return action(r, (b) => push.sendTest(b['token'] as String));
    });
}

/// Serves one WebSocket client: each subscribed topic streams snapshots until
/// the client unsubscribes or disconnects.
void _serveSocket(AgentBackend backend, WebSocketChannel channel) {
  final subscriptions = <String, StreamSubscription<List<Json>>>{};
  void send(Frame frame) => channel.sink.add(jsonEncode(frame.toJson()));

  channel.stream.listen(
    (raw) {
      final Frame frame;
      try {
        frame = Frame.fromJson(jsonDecode(raw as String) as Json);
      } catch (e) {
        send(ErrorFrame('Bad frame: $e'));
        return;
      }
      switch (frame) {
        case SubscribeFrame(:final topic):
          subscriptions.remove(topic)?.cancel();
          final stream = watchTopicJson(backend, topic);
          if (stream == null) {
            send(ErrorFrame('Unknown topic', topic: topic));
            return;
          }
          subscriptions[topic] = stream.listen(
            (data) => send(SnapshotFrame(topic, data)),
          );
        case UnsubscribeFrame(:final topic):
          subscriptions.remove(topic)?.cancel();
        case SnapshotFrame() || ErrorFrame():
          send(const ErrorFrame('Clients may only subscribe or unsubscribe'));
      }
    },
    onDone: () {
      for (final s in subscriptions.values) {
        s.cancel();
      }
      subscriptions.clear();
    },
  );
}

Middleware _auth(String token) {
  final expected = utf8.encode(token);

  bool matches(String? given) {
    if (given == null) return false;
    final bytes = utf8.encode(given);
    if (bytes.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < bytes.length; i++) {
      diff |= bytes[i] ^ expected[i];
    }
    return diff == 0;
  }

  return (inner) => (request) {
    if (request.method == 'OPTIONS') return inner(request);
    final header = request.headers[HttpHeaders.authorizationHeader];
    final given = header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : request.url.queryParameters[ApiPaths.tokenQuery];
    if (!matches(given)) return _json({'error': 'Unauthorized'}, status: 401);
    return inner(request);
  };
}

Middleware _cors(List<String> origins) {
  if (origins.isEmpty) return (inner) => inner;

  Map<String, String> headersFor(String? origin) => {
    if (origin != null && (origins.contains(origin) || origins.contains('*')))
      'access-control-allow-origin': origin,
    'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'vary': 'origin',
  };

  return (inner) => (request) async {
    final headers = headersFor(request.headers['origin']);
    if (request.method == 'OPTIONS') return Response.ok(null, headers: headers);
    final response = await inner(request);
    return response.change(headers: headers);
  };
}

Handler _webApp(String root) {
  final files = createStaticHandler(root, defaultDocument: 'index.html');
  final index = File(p.join(root, 'index.html'));
  return (request) async {
    final response = await files(request);
    if (response.statusCode != 404 || !index.existsSync()) return response;
    return Response.ok(
      index.openRead(),
      headers: {
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-cache',
      },
    );
  };
}

Response _json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {HttpHeaders.contentTypeHeader: 'application/json'},
);
