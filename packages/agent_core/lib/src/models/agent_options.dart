import 'agent.dart';
import 'enums.dart';
import 'json.dart';

/// A model an agent's CLI can run on, e.g. Claude Code's `opus` alias.
class ModelOption {
  const ModelOption({
    required this.value,
    required this.label,
    this.description = '',
    this.resolved,
    this.efforts = const [],
  });

  factory ModelOption.fromJson(Json json) => ModelOption(
    value: json['value'] as String,
    label: json['label'] as String? ?? json['value'] as String,
    description: json['description'] as String? ?? '',
    resolved: json['resolved'] as String?,
    efforts: [
      for (final name in decodeStrings(json['efforts']))
        ?EffortLevel.tryParse(name),
    ],
  );

  /// The CLI's own default, which [Agent.model] stores as null.
  static const defaultValue = 'default';

  /// What the CLI's `--model` flag takes.
  final String value;
  final String label;
  final String description;

  /// The full model id [value] stands for, e.g. `claude-opus-5-5[1m]`.
  final String? resolved;

  /// The effort levels the model supports; empty when it has no such setting.
  final List<EffortLevel> efforts;

  bool get isDefault => value == defaultValue;

  /// A short name such as "Opus 5.5", falling back to [label].
  String get shortName => modelDisplayName(resolved ?? value) ?? label;

  Json toJson() => {
    'value': value,
    'label': label,
    if (description.isNotEmpty) 'description': description,
    'resolved': ?resolved,
    if (efforts.isNotEmpty) 'efforts': [for (final e in efforts) e.name],
  };
}

/// A command the agent's CLI runs when a prompt starts with `/name`.
class SlashCommand {
  const SlashCommand(
    this.name, {
    this.description = '',
    this.argumentHint = '',
  });

  factory SlashCommand.fromJson(Json json) => SlashCommand(
    json['name'] as String,
    description: json['description'] as String? ?? '',
    argumentHint: json['argumentHint'] as String? ?? '',
  );

  final String name;
  final String description;

  /// How the arguments look, e.g. `<model>`; empty when it takes none.
  final String argumentHint;

  Json toJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    if (argumentHint.isNotEmpty) 'argumentHint': argumentHint,
  };
}

/// What an agent's CLI offers: the models it can switch between and the
/// slash commands it accepts. These change rarely, so they travel apart from
/// the [Agent] snapshots.
class AgentOptions {
  const AgentOptions({
    required this.agentId,
    this.models = const [],
    this.commands = const [],
  });

  factory AgentOptions.fromJson(Json json) => AgentOptions(
    agentId: json['agentId'] as String,
    models: decodeList(json['models'], ModelOption.fromJson),
    commands: decodeList(json['commands'], SlashCommand.fromJson),
  );

  final String agentId;
  final List<ModelOption> models;
  final List<SlashCommand> commands;

  /// The option stored as [value], where null is the CLI's default.
  ModelOption? model(String? value) {
    final wanted = value ?? ModelOption.defaultValue;
    return models.where((m) => m.value == wanted).firstOrNull;
  }

  /// The option the words of a `/model` command name, by value or label.
  ModelOption? findModel(String words) {
    final w = words.trim().toLowerCase();
    return models
        .where((m) => m.value.toLowerCase() == w)
        .followedBy(models.where((m) => m.label.toLowerCase() == w))
        .followedBy(models.where((m) => m.shortName.toLowerCase() == w))
        .firstOrNull;
  }

  Json toJson() => {
    'agentId': agentId,
    'models': [for (final m in models) m.toJson()],
    'commands': [for (final c in commands) c.toJson()],
  };

  AgentOptions copyWith({
    List<ModelOption>? models,
    List<SlashCommand>? commands,
  }) => AgentOptions(
    agentId: agentId,
    models: models ?? this.models,
    commands: commands ?? this.commands,
  );
}

/// A readable name for a Claude model id, e.g. `claude-opus-5-5[1m]` becomes
/// "Opus 5.5 (1M)" and `claude-haiku-4-5-20251001` becomes "Haiku 4.5". Null
/// for ids that don't look like Claude's.
String? modelDisplayName(String id) {
  final match = RegExp(
    r'^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?(\[1m\])?$',
  ).firstMatch(id.toLowerCase());
  if (match == null) return null;
  final family = match[1]!;
  final version = [match[2], ?match[3]].join('.');
  final name = '${family[0].toUpperCase()}${family.substring(1)} $version';
  return match[4] == null ? name : '$name (1M)';
}

/// A prompt that runs a slash command: the command's name and the rest of
/// the prompt.
typedef SlashInvocation = ({String name, String args});

/// Splits `/name args` into its parts, or returns null when [prompt] isn't a
/// slash command (a path such as `/usr/bin` isn't one).
SlashInvocation? parseSlashCommand(String prompt) {
  final match = RegExp(r'^/([A-Za-z0-9][\w:.-]*)(?:\s+([\s\S]*))?$')
      .firstMatch(prompt.trim());
  if (match == null) return null;
  return (name: match[1]!, args: (match[2] ?? '').trim());
}

/// A short name for the model stored as [value] (null for the CLI's
/// default), e.g. "Opus 5.5". The default reads as the model it stands for
/// when [options] or [activeModel] tell which one that is.
String modelName(String? value, AgentOptions? options, {String? activeModel}) {
  final option = options?.model(value);
  if (option != null) return option.shortName;
  if (value != null) return modelDisplayName(value) ?? value;
  return modelDisplayName(activeModel ?? '') ?? activeModel ?? 'Default model';
}

/// The model and effort [agent] runs on, e.g. "Opus 5.5 · High".
String describeModel(Agent agent, AgentOptions? options) => [
  modelName(agent.model, options, activeModel: agent.activeModel),
  ?agent.effort?.label,
].join(' · ');
