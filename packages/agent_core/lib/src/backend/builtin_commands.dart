import '../models/models.dart';

/// Slash commands every backend answers itself instead of passing them to
/// the agent's CLI, so they also work while the agent is busy.
abstract final class BuiltinCommands {
  static const model = 'model';
  static const effort = 'effort';
  static const clear = 'clear';

  static const names = {model, effort, clear};

  /// The commands to offer for an agent whose CLI lists none of its own.
  static List<SlashCommand> fallback({required bool models}) => [
    const SlashCommand(
      clear,
      description: 'Start a new conversation with empty context',
    ),
    if (models)
      const SlashCommand(
        model,
        description: 'Switch the model',
        argumentHint: '<model>',
      ),
  ];
}

/// What a `/model` or `/effort` command asks for: the agent's new settings
/// when [changed], and a line to post in the chat either way.
typedef SettingsCommand = ({
  bool changed,
  String? model,
  EffortLevel? effort,
  String message,
});

/// Resolves a `/model` or `/effort` invocation against [agent]'s current
/// settings and [options], or returns null for any other command. A model the
/// options don't list is refused, unless the CLI lists no models at all.
SettingsCommand? resolveSettingsCommand(
  SlashInvocation command,
  Agent agent,
  AgentOptions? options,
) {
  final models = options?.models ?? const <ModelOption>[];
  final current = options?.model(agent.model);
  final name = modelName(agent.model, options, activeModel: agent.activeModel);
  SettingsCommand info(String message) => (
    changed: false,
    model: agent.model,
    effort: agent.effort,
    message: message,
  );

  switch (command.name) {
    case BuiltinCommands.model:
      final choices = models.map((m) => m.value).join(', ');
      if (command.args.isEmpty) {
        return info(
          choices.isEmpty
              ? '${agent.name} uses $name.'
              : '${agent.name} uses $name. Choose one of: $choices.',
        );
      }
      final option = options?.findModel(command.args);
      if (option == null && models.isNotEmpty) {
        return info('No model called "${command.args}". Try: $choices.');
      }
      final value = option?.value ?? command.args;
      final effort = option != null && option.efforts.isEmpty
          ? null
          : agent.effort;
      return (
        changed: true,
        model: value == ModelOption.defaultValue ? null : value,
        effort: effort,
        message: 'Switched to ${option?.shortName ?? value}',
      );
    case BuiltinCommands.effort:
      final levels = current?.efforts.isNotEmpty ?? false
          ? current!.efforts
          : EffortLevel.values;
      final names = levels.map((l) => l.name).join(', ');
      if (command.args.isEmpty) {
        return info(
          'Effort is ${agent.effort?.label.toLowerCase() ?? 'the default'}. '
          'Choose one of: $names, or auto.',
        );
      }
      final word = command.args.toLowerCase();
      if (word == 'auto' || word == 'default') {
        return (
          changed: true,
          model: agent.model,
          effort: null,
          message: 'Effort set to the default',
        );
      }
      final level = EffortLevel.tryParse(word);
      if (level == null || !levels.contains(level)) {
        return info('No effort level "${command.args}". Try: $names, or auto.');
      }
      return (
        changed: true,
        model: agent.model,
        effort: level,
        message: 'Effort set to ${level.label.toLowerCase()}',
      );
  }
  return null;
}
