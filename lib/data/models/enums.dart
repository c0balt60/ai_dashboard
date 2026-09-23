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

/// Position of a task in the queue.
enum TaskState { active, waiting, backlog, completed, failed }

enum TestStatus { running, passed, failed }

enum MessageRole { user, agent, system }

enum LogLevel { info, success, warning, error }
