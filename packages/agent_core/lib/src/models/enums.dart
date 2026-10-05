/// Lifecycle status of a coding agent running on the host PC.
enum AgentStatus { running, waiting, completed, failed, idle }

/// The CLI agent implementation behind an [Agent].
enum AgentType {
  claudeCode('Claude Code', 'Claude'),
  codex('Codex', 'Codex'),
  geminiCli('Gemini CLI', 'Gemini'),
  aider('Aider', 'Aider');

  const AgentType(this.label, this.shortLabel);

  final String label;
  final String shortLabel;
}

/// How hard the model thinks before answering, as Claude Code's `--effort`
/// names it. Higher levels are slower and use more of the usage limits.
enum EffortLevel {
  low('Low'),
  medium('Medium'),
  high('High'),
  xhigh('Extra high'),
  max('Max');

  const EffortLevel(this.label);

  final String label;

  /// The level named [name], or null for one this version doesn't know.
  static EffortLevel? tryParse(Object? name) => values.asNameMap()[name];
}

/// Position of a task in the queue.
enum TaskState { active, waiting, backlog, completed, failed }

enum TestStatus { running, passed, failed }

/// Who a chat message is from. [thinking] holds an agent's steps between
/// replies and [question] a question it waits on.
enum MessageRole { user, agent, system, thinking, question }

enum LogLevel { info, success, warning, error }
