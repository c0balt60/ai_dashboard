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

  /// Every agent's chats, including each agent's default chat.
  Stream<List<AgentChat>> watchChats();

  Stream<List<ChatMessage>> watchMessages(String chatId);

  /// Runs a turn in the chat's project folder (the agent's current folder for
  /// its default chat). The first prompt of an untitled chat names it.
  Future<void> sendPrompt(String chatId, String text);

  /// Starts a chat with [agentId], in [projectId] or general purpose.
  Future<AgentChat> createChat(
    String agentId, {
    String? projectId,
    String title = '',
  });

  Future<void> renameChat(String chatId, String title);

  /// Deletes a chat and its messages. An agent's default chat can't be
  /// deleted, only cleared.
  Future<void> deleteChat(String chatId);

  /// Starting over also starts a fresh CLI conversation.
  Future<void> clearMessages(String chatId);

  /// Points an agent at a project folder, optionally handing it a task. The
  /// project joins the agent's projects.
  Future<void> assignAgent(
    String agentId, {
    required String projectId,
    required String workingDir,
    String? taskId,
  });

  /// Replaces the projects the agent belongs to without interrupting it.
  /// Leaving its current project unassigns it from that folder.
  Future<void> setAgentProjects(String agentId, List<String> projectIds);

  Future<void> stopAgent(String agentId);

  /// Creates a task. With an [agentId] it goes straight to `waiting` for that
  /// agent, otherwise to the backlog. A [todo] link keeps that to-do item's
  /// checkbox in step with the task.
  Future<AgentTask> createTask(
    String title,
    String projectId, {
    String? agentId,
    String description = '',
    TodoLink? todo,
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
