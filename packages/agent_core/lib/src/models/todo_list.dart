import 'json.dart';

/// A user-written reminder, tagged with the projects and agents it concerns.
///
/// Unlike an [AgentTask] it is never run on the PC; it is a note to self that
/// can later be handed to an agent. Dates are whole days (local midnight).
class TodoItem {
  const TodoItem({
    required this.id,
    required this.title,
    required this.createdAt,
    this.note = '',
    this.done = false,
    this.projectIds = const [],
    this.agentIds = const [],
    this.startDate,
    this.dueDate,
    this.completedAt,
  });

  factory TodoItem.fromJson(Json json) => TodoItem(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: decodeTime(json['createdAt']),
    note: json['note'] as String? ?? '',
    done: json['done'] as bool? ?? false,
    projectIds: decodeStrings(json['projectIds']),
    agentIds: decodeStrings(json['agentIds']),
    startDate: decodeDayOrNull(json['startDate']),
    dueDate: decodeDayOrNull(json['dueDate']),
    completedAt: decodeTimeOrNull(json['completedAt']),
  );

  final String id;
  final String title;
  final String note;
  final bool done;
  final List<String> projectIds;
  final List<String> agentIds;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool isOverdue(DateTime now) =>
      !done &&
      dueDate != null &&
      dueDate!.isBefore(DateTime(now.year, now.month, now.day));

  Json toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'done': done,
    'projectIds': projectIds,
    'agentIds': agentIds,
    if (startDate case final d?) 'startDate': encodeDay(d),
    if (dueDate case final d?) 'dueDate': encodeDay(d),
    'createdAt': encodeTime(createdAt),
    if (completedAt case final t?) 'completedAt': encodeTime(t),
  };

  TodoItem copyWith({
    String? title,
    String? note,
    bool? done,
    List<String>? projectIds,
    List<String>? agentIds,
    DateTime? Function()? startDate,
    DateTime? Function()? dueDate,
    DateTime? Function()? completedAt,
  }) {
    return TodoItem(
      id: id,
      createdAt: createdAt,
      title: title ?? this.title,
      note: note ?? this.note,
      done: done ?? this.done,
      projectIds: projectIds ?? this.projectIds,
      agentIds: agentIds ?? this.agentIds,
      startDate: startDate != null ? startDate() : this.startDate,
      dueDate: dueDate != null ? dueDate() : this.dueDate,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
    );
  }
}

/// A named list of [TodoItem]s, e.g. the features planned for a release.
class TodoList {
  const TodoList({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  factory TodoList.fromJson(Json json) => TodoList(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: decodeTime(json['createdAt']),
    updatedAt: decodeTime(json['updatedAt']),
    items: decodeList(json['items'], TodoItem.fromJson),
  );

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// In insertion order.
  final List<TodoItem> items;

  int get doneCount => items.where((i) => i.done).length;

  /// Earliest start (or due) date across the items, or null when none is set.
  DateTime? get timelineStart => _extreme(
    items.map((i) => i.startDate ?? i.dueDate),
    (a, b) => a.isBefore(b),
  );

  /// Latest due (or start) date across the items, or null when none is set.
  DateTime? get timelineEnd => _extreme(
    items.map((i) => i.dueDate ?? i.startDate),
    (a, b) => a.isAfter(b),
  );

  Json toJson() => {
    'id': id,
    'title': title,
    'createdAt': encodeTime(createdAt),
    'updatedAt': encodeTime(updatedAt),
    'items': [for (final i in items) i.toJson()],
  };

  TodoList copyWith({
    String? title,
    DateTime? updatedAt,
    List<TodoItem>? items,
  }) {
    return TodoList(
      id: id,
      createdAt: createdAt,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }

  static DateTime? _extreme(
    Iterable<DateTime?> dates,
    bool Function(DateTime a, DateTime b) better,
  ) {
    DateTime? result;
    for (final d in dates) {
      if (d != null && (result == null || better(d, result))) result = d;
    }
    return result;
  }
}
