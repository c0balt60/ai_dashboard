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

  /// The user's own to-do lists. Agents never act on these directly.
  Stream<List<TodoList>> watchTodoLists();

  Future<TodoList> createTodoList(String title);
  Future<void> renameTodoList(String listId, String title);
  Future<void> deleteTodoList(String listId);

  /// Appends an item to a list.
  Future<TodoItem> addTodoItem(
    String listId, {
    required String title,
    String note = '',
    List<String> projectIds = const [],
    List<String> agentIds = const [],
    DateTime? startDate,
    DateTime? dueDate,
  });

  /// Replaces an item's fields. Flipping [TodoItem.done] stamps or clears
  /// [TodoItem.completedAt].
  Future<void> updateTodoItem(String listId, TodoItem item);

  Future<void> deleteTodoItem(String listId, String itemId);

  Future<String> runCommand(String projectId, String command);

  Future<Duration> ping();

  void setSimulationEnabled(bool enabled);

  void dispose();
}
