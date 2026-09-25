import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

/// Server settings, read from a JSON file (see `config.example.json`).
///
/// Relative paths resolve against the config file's folder. The auth token
/// can come from the `AI_DASHBOARD_TOKEN` environment variable instead of the
/// file.
class ServerConfig {
  const ServerConfig({
    required this.token,
    this.host = '127.0.0.1',
    this.port = 8787,
    this.webRoot,
    required this.dataDir,
    this.corsOrigins = const [],
    this.commandTimeout = const Duration(minutes: 2),
    this.shell = const [],
    this.projects = const [],
    this.agents = const [],
    this.firebaseServiceAccount,
  });

  factory ServerConfig.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ConfigException(
        'No config at ${file.absolute.path}. '
        'Copy config.example.json to config.json and edit it.',
      );
    }
    final json = jsonDecode(file.readAsStringSync()) as Json;
    final base = p.dirname(file.absolute.path);
    String resolve(String path) => p.normalize(p.join(base, path));

    final token =
        Platform.environment['AI_DASHBOARD_TOKEN'] ?? json['token'] as String?;
    if (token == null || token.length < 24 || token.startsWith('CHANGE-ME')) {
      throw ConfigException(
        'Set "token" (or AI_DASHBOARD_TOKEN) to a random string of at least '
        '24 characters.',
      );
    }

    return ServerConfig(
      token: token,
      host: json['host'] as String? ?? '127.0.0.1',
      port: json['port'] as int? ?? 8787,
      webRoot: switch (json['webRoot']) {
        final String root => resolve(root),
        _ => null,
      },
      dataDir: switch (json['dataDir']) {
        final String dir => resolve(dir),
        _ => _defaultDataDir(),
      },
      corsOrigins: decodeStrings(json['corsOrigins']),
      firebaseServiceAccount: switch (json['firebaseServiceAccount']) {
        final String path => resolve(path),
        _ => null,
      },
      commandTimeout: Duration(
        seconds: json['commandTimeoutSeconds'] as int? ?? 120,
      ),
      shell: decodeStrings(json['shell']),
      projects: [
        for (final e in json['projects'] as List? ?? const [])
          ProjectConfig.fromJson(e as Json, resolve),
      ],
      agents: [
        for (final e in json['agents'] as List? ?? const [])
          AgentConfig.fromJson(e as Json, resolve),
      ],
    );
  }

  final String token;
  final String host;
  final int port;

  /// The built Flutter web app (`flutter build web`), or null to serve only
  /// the API.
  final String? webRoot;

  /// Where the server keeps its state between restarts.
  final String dataDir;

  /// Browser origins allowed to call the API cross-origin, e.g. a
  /// `flutter run -d edge` dev server. Empty when the app is served by this
  /// server.
  final List<String> corsOrigins;

  final Duration commandTimeout;

  /// Program and leading arguments that run a project command, e.g.
  /// `["powershell", "-NoProfile", "-Command"]`. Empty uses the system shell.
  final List<String> shell;

  final List<ProjectConfig> projects;
  final List<AgentConfig> agents;

  /// The Firebase service-account key the server sends push notifications
  /// with, or null to send none. Keep it out of git like this file.
  final String? firebaseServiceAccount;

  static String _defaultDataDir() {
    final env = Platform.environment;
    final root = Platform.isWindows
        ? env['APPDATA'] ?? env['USERPROFILE'] ?? '.'
        : p.join(env['HOME'] ?? '.', '.local', 'share');
    return p.join(root, 'ai_dashboard');
  }
}

class ProjectConfig {
  const ProjectConfig({
    required this.id,
    required this.name,
    required this.path,
    this.testCommand,
  });

  factory ProjectConfig.fromJson(Json json, String Function(String) resolve) {
    final path = resolve(json['path'] as String);
    final name = json['name'] as String? ?? p.basename(path);
    return ProjectConfig(
      id: json['id'] as String? ?? slug(name),
      name: name,
      path: path,
      testCommand: json['testCommand'] as String?,
    );
  }

  final String id;
  final String name;
  final String path;

  /// Run after each successful agent turn to record a test run.
  final String? testCommand;
}

class AgentConfig {
  const AgentConfig({
    required this.id,
    required this.name,
    required this.type,
    this.executable,
    this.extraArgs = const [],
    this.projectId,
  });

  factory AgentConfig.fromJson(Json json, String Function(String) resolve) {
    final type = AgentType.values.byName(json['type'] as String);
    final name = json['name'] as String? ?? type.label;
    return AgentConfig(
      id: json['id'] as String? ?? slug(name),
      name: name,
      type: type,
      executable: json['executable'] as String?,
      extraArgs: decodeStrings(json['extraArgs']),
      projectId: json['projectId'] as String?,
    );
  }

  final String id;
  final String name;
  final AgentType type;

  /// Overrides the CLI program, e.g. a full path to `claude.exe`.
  final String? executable;

  /// Extra CLI flags for every turn, e.g. Claude Code's permission flags.
  final List<String> extraArgs;

  /// The project the agent starts out in.
  final String? projectId;
}

class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

String slug(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'item' : s;
}
