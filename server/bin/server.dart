/// Starts the agent dashboard server on the PC.
///
/// Usage, from the `server` folder:
///   `dart run bin/server.dart [--config config.json] [--simulate]`
///
/// `--simulate` serves the in-memory mock instead of real agents, which is
/// handy for trying the app against a live server.
library;

import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard_server/api.dart';
import 'package:ai_dashboard_server/config.dart';
import 'package:args/args.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'config.json')
    ..addFlag('simulate', negatable: false, help: 'Serve the mock backend.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(args);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final ServerConfig config;
  try {
    config = ServerConfig.load(options.option('config')!);
  } on ConfigException catch (e) {
    stderr.writeln(e);
    exit(78);
  }

  final simulate = options.flag('simulate');
  final AgentBackend backend = simulate
      ? MockAgentBackend()
      : throw UnimplementedError('Real agents are not wired up yet.');

  final handler = const Pipeline()
      .addMiddleware(_logRequests)
      .addHandler(
        buildHandler(
          backend,
          token: config.token,
          webRoot: config.webRoot,
          corsOrigins: config.corsOrigins,
        ),
      );
  final server = await shelf_io.serve(handler, config.host, config.port);
  stdout.writeln(
    'Agent dashboard server on http://${server.address.host}:${server.port}'
    '${simulate ? ' (simulated agents)' : ''}',
  );
  if (config.webRoot == null || !Directory(config.webRoot!).existsSync()) {
    stdout.writeln('No built web app found: serving the API only.');
  }

  Future<void> shutdown(ProcessSignal _) async {
    backend.dispose();
    await server.close(force: true);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
}

/// Logs method, path and status, leaving out the query so the WebSocket token
/// never reaches the log.
Handler _logRequests(Handler inner) => (request) async {
  final watch = Stopwatch()..start();
  final response = await inner(request);
  stdout.writeln(
    '${DateTime.now().toIso8601String()}  ${request.method.padRight(6)} '
    '/${request.url.path}  ${response.statusCode}  '
    '${watch.elapsedMilliseconds}ms',
  );
  return response;
};
