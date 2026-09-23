import '../models/models.dart';

/// Contract between the app and the agent host running on the main PC.
///
/// The UI only talks to this interface. [MockAgentBackend] implements it
/// in-memory; a real implementation would map these calls onto REST +
/// WebSocket endpoints exposed by the PC.
abstract interface class AgentBackend {
  /// Each `watch*` stream emits the current snapshot immediately, then again
  /// on every change.
  Stream<List<Agent>> watchAgents();
  Stream<List<Project>> watchProjects();
  Stream<List<AgentTask>> watchTasks();

  Stream<List<ChatMessage>> watchMessages(String agentId);

  Future<void> sendPrompt(String agentId, String text);

  /// Points an agent at a project folder, optionally handing it a task.
  Future<void> assignAgent(
    String agentId, {
    required String projectId,
    required String workingDir,
    String? taskId,
  });

  Future<void> stopAgent(String agentId);
  Future<void> clearMessages(String agentId);

  /// Creates a task. With an [agentId] it goes straight to `waiting` for that
  /// agent, otherwise to the backlog.
  Future<AgentTask> createTask(
    String title,
    String projectId, {
    String? agentId,
  });

  Future<void> updateTaskState(String taskId, TaskState state);

  Future<String> runCommand(String projectId, String command);

  Future<Duration> ping();

  void setSimulationEnabled(bool enabled);

  void dispose();
}
