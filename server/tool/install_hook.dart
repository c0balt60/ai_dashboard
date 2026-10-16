/// Adds the hook that relays questions from Claude Code sessions on this PC
/// (terminal, VS Code, desktop app) to the dashboard to your global Claude
/// Code settings, so they can be answered from the phone.
///
/// Usage, from the `server` folder:
///   `dart run tool/install_hook.dart [--config config.json]`
///
/// Rerun after changing the server's port or token. The previous settings
/// are kept as `settings.json.bak`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard_server/config.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  final options =
      (ArgParser()..addOption('config', abbr: 'c', defaultsTo: 'config.json'))
          .parse(args);
  final config = ServerConfig.load(options.option('config')!);
  final host = config.host == '0.0.0.0' ? '127.0.0.1' : config.host;
  final url = 'http://$host:${config.port}${ApiPaths.desktopQuestion}';

  final env = Platform.environment;
  final file = File(
    p.join(
      env['CLAUDE_CONFIG_DIR'] ??
          p.join(env['USERPROFILE'] ?? env['HOME'] ?? '.', '.claude'),
      'settings.json',
    ),
  );
  final settings = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Json
      : <String, Object?>{};
  if (file.existsSync()) file.copySync('${file.path}.bak');

  final hooks = settings['hooks'] as Json? ?? {};
  final entries = [
    for (final e in hooks['PermissionRequest'] as List? ?? const [])
      if (!jsonEncode(e).contains(ApiPaths.desktopQuestion)) e,
    {
      'matcher': 'AskUserQuestion',
      'hooks': [
        {
          'type': 'http',
          'url': url,
          'headers': {'Authorization': 'Bearer ${config.token}'},
          // Held open until the question is answered on the phone or at the
          // PC; the dialog at the PC works all the while.
          'timeout': 86400,
        },
      ],
    },
  ];
  settings['hooks'] = {...hooks, 'PermissionRequest': entries};

  file
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(settings)}\n',
    );
  stdout.writeln(
    'Claude Code now relays its questions to $url (${file.path}).',
  );
}
