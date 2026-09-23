/// Starts the agent dashboard server on the PC.
///
/// Usage, from the `server` folder:
///   `dart run bin/server.dart [--config config.json] [--simulate] [--log file]`
///
/// `--simulate` serves the in-memory mock instead of real agents, which is
/// handy for trying the app against a live server. `--log` appends output to
/// a file instead of the console, for running without a window.
library;

import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard_server/api.dart';
import 'package:ai_dashboard_server/config.dart';
import 'package:ai_dashboard_server/local_backend.dart';
import 'package:args/args.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'config.json')
    ..addFlag('simulate', negatable: false, help: 'Serve the mock backend.')
    ..addOption('log', help: 'Append output to this file.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(args);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  if (options.option('log') case final path?) {
    _out = File(path).openWrite(mode: FileMode.append);
  }

  final ServerConfig config;
  try {
    config = ServerConfig.load(options.option('config')!);
  } on ConfigException catch (e) {
    stderr.writeln(e);
    _out.writeln(e);
    await _out.flush();
    exit(78);
  }

  final simulate = options.flag('simulate');
  final AgentBackend backend = simulate
      ? MockAgentBackend()
      : LocalAgentBackend(config);

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
  _out.writeln(
    '${DateTime.now().toIso8601String()}  Agent dashboard server on http://${server.address.host}:${server.port}'
    '${simulate ? ' (simulated agents)' : ''}',
  );
  if (!simulate) _out.writeln('State is kept in ${config.dataDir}');
  if (config.webRoot == null || !Directory(config.webRoot!).existsSync()) {
    _out.writeln('No built web app found: serving the API only.');
  }

  Future<void> shutdown(ProcessSignal _) async {
    backend.dispose();
    await server.close(force: true);
    await _out.flush();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
}

IOSink _out = stdout;

/// Logs method, path and status, leaving out the query so the WebSocket token
/// never reaches the log.
Handler _logRequests(Handler inner) => (request) async {
  final watch = Stopwatch()..start();
  final response = await inner(request);
  _out.writeln(
    '${DateTime.now().toIso8601String()}  ${request.method.padRight(6)} '
    '/${request.url.path}  ${response.statusCode}  '
    '${watch.elapsedMilliseconds}ms',
  );
  return response;
};
