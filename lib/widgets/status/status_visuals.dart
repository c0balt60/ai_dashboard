/// Single source of truth for how each agent status, task state, test status,
/// to-do due date, PC connection state and usage level looks (label, icon,
/// color).
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/backend/http_backend.dart';
import '../../data/models/models.dart';
import '../../utils/time_format.dart';

class StatusVisual {
  const StatusVisual(
    this.label,
    this.icon,
    this.color, {
    this.animated = false,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Whether indicators should pulse to show ongoing work.
  final bool animated;
}

extension AgentStatusVisual on AgentStatus {
  StatusVisual visual(BuildContext context) {
    final c = StatusColors.of(context);
    return switch (this) {
      AgentStatus.running => StatusVisual(
        'Running',
        Icons.play_circle_fill,
        c.running,
        animated: true,
      ),
      AgentStatus.waiting => StatusVisual(
        'Waiting',
        Icons.hourglass_top,
        c.waiting,
      ),
      AgentStatus.completed => StatusVisual(
        'Completed',
        Icons.check_circle,
        c.completed,
      ),
      AgentStatus.failed => StatusVisual('Failed', Icons.error, c.failed),
      AgentStatus.idle => StatusVisual('Idle', Icons.pause_circle, c.idle),
    };
  }
}

extension ConnectionStatusVisual on ConnectionStatus {
  StatusVisual visual(BuildContext context) {
    final c = StatusColors.of(context);
    return switch (this) {
      ConnectionStatus.connected => StatusVisual(
        'Connected',
        Icons.link,
        c.completed,
      ),
      ConnectionStatus.connecting => StatusVisual(
        'Connecting…',
        Icons.sync,
        c.waiting,
        animated: true,
      ),
      ConnectionStatus.offline => StatusVisual(
        'Offline',
        Icons.link_off,
        c.failed,
      ),
    };
  }
}

extension TaskStateVisual on TaskState {
  StatusVisual visual(BuildContext context) {
    final c = StatusColors.of(context);
    return switch (this) {
      TaskState.active => StatusVisual(
        'Active',
        Icons.bolt,
        c.running,
        animated: true,
      ),
      TaskState.waiting => StatusVisual('Waiting', Icons.schedule, c.waiting),
      TaskState.backlog => StatusVisual('Backlog', Icons.inbox, c.idle),
      TaskState.completed => StatusVisual(
        'Completed',
        Icons.check_circle,
        c.completed,
      ),
      TaskState.failed => StatusVisual('Failed', Icons.error, c.failed),
    };
  }
}

extension TestStatusVisual on TestStatus {
  StatusVisual visual(BuildContext context) {
    final c = StatusColors.of(context);
    return switch (this) {
      TestStatus.running => StatusVisual(
        'Running',
        Icons.autorenew,
        c.running,
        animated: true,
      ),
      TestStatus.passed => StatusVisual(
        'Passed',
        Icons.check_circle,
        c.completed,
      ),
      TestStatus.failed => StatusVisual('Failed', Icons.cancel, c.failed),
    };
  }
}

extension LogLevelVisual on LogLevel {
  StatusVisual visual(BuildContext context) {
    final c = StatusColors.of(context);
    return switch (this) {
      LogLevel.info => StatusVisual('Info', Icons.circle, c.idle),
      LogLevel.success => StatusVisual(
        'Success',
        Icons.check_circle,
        c.completed,
      ),
      LogLevel.warning => StatusVisual(
        'Warning',
        Icons.warning_amber,
        c.waiting,
      ),
      LogLevel.error => StatusVisual('Error', Icons.error, c.failed),
    };
  }
}

extension TodoItemDueVisual on TodoItem {
  /// Overdue items read as failed and items due within a day as waiting.
  /// Null when the item is done or has no due date.
  StatusVisual? dueVisual(BuildContext context) {
    final due = dueDate;
    if (due == null || done) return null;
    final c = StatusColors.of(context);
    return switch (daysUntil(due)) {
      < 0 => StatusVisual(dueLabel(due), Icons.event_busy, c.failed),
      <= 1 => StatusVisual(dueLabel(due), Icons.event, c.waiting),
      _ => StatusVisual(dueLabel(due), Icons.event_outlined, c.idle),
    };
  }
}

extension AgentTypeVisual on AgentType {
  IconData get icon => switch (this) {
    AgentType.claudeCode => Icons.auto_awesome,
    AgentType.codex => Icons.code,
    AgentType.geminiCli => Icons.diamond_outlined,
    AgentType.aider => Icons.terminal,
  };
}

/// How a context window or usage limit that is [fraction] used up (0 to 1)
/// looks: calm while plenty is left, a warning from 70% and failed from 90%.
StatusVisual usageVisual(BuildContext context, double fraction) {
  final c = StatusColors.of(context);
  return switch (fraction) {
    >= 0.9 => StatusVisual('Almost used up', Icons.error_outline, c.failed),
    >= 0.7 => StatusVisual('Running low', Icons.warning_amber, c.waiting),
    _ => StatusVisual('Plenty left', Icons.check_circle_outline, c.completed),
  };
}
