import 'attachment.dart';
import 'enums.dart';
import 'json.dart';

/// One chat entry. Besides plain text, a [MessageRole.thinking] message
/// gathers the [steps] an agent worked through on its way to a reply, and a
/// [MessageRole.question] message holds the [questions] it asked, with the
/// owner's [answers] once given. A prompt carries the files the owner
/// attached to it.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.agentId,
    required this.role,
    required this.text,
    required this.at,
    this.steps = const [],
    this.questions = const [],
    this.answers,
    this.attachments = const [],
  });

  factory ChatMessage.fromJson(Json json) => ChatMessage(
    id: json['id'] as String,
    agentId: json['agentId'] as String,
    role: MessageRole.values.byName(json['role'] as String),
    text: json['text'] as String,
    at: decodeTime(json['at']),
    steps: decodeStrings(json['steps']),
    questions: decodeList(json['questions'], AgentQuestion.fromJson),
    answers: switch (json['answers']) {
      final Json answers => {
        for (final e in answers.entries) e.key: e.value as String,
      },
      _ => null,
    },
    attachments: decodeList(json['attachments'], Attachment.fromJson),
  );

  final String id;
  final String agentId;
  final MessageRole role;
  final String text;
  final DateTime at;
  final List<String> steps;
  final List<AgentQuestion> questions;

  /// The answer to each question, keyed by its [AgentQuestion.question].
  /// Null while the agent waits for them; empty when the turn ended without
  /// them, or when the owner replied in their own words instead.
  final Map<String, String>? answers;
  final List<Attachment> attachments;

  bool get isOpenQuestion => role == MessageRole.question && answers == null;

  ChatMessage copyWith({
    List<String>? steps,
    Map<String, String>? Function()? answers,
  }) => ChatMessage(
    id: id,
    agentId: agentId,
    role: role,
    text: text,
    at: at,
    steps: steps ?? this.steps,
    questions: questions,
    answers: answers == null ? this.answers : answers(),
    attachments: attachments,
  );

  Json toJson() => {
    'id': id,
    'agentId': agentId,
    'role': role.name,
    'text': text,
    'at': encodeTime(at),
    if (steps.isNotEmpty) 'steps': steps,
    if (questions.isNotEmpty)
      'questions': [for (final q in questions) q.toJson()],
    'answers': ?answers,
    if (attachments.isNotEmpty)
      'attachments': [for (final a in attachments) a.toJson()],
  };
}

/// A multiple-choice question an agent asks, as Claude Code's
/// `AskUserQuestion` tool shapes it: 2–4 [options], and the owner may always
/// answer in their own words instead.
class AgentQuestion {
  const AgentQuestion({
    required this.question,
    this.header = '',
    required this.options,
    this.multiSelect = false,
  });

  factory AgentQuestion.fromJson(Json json) => AgentQuestion(
    question: json['question'] as String,
    header: json['header'] as String? ?? '',
    options: decodeList(json['options'], QuestionOption.fromJson),
    multiSelect: json['multiSelect'] as bool? ?? false,
  );

  final String question;

  /// A short label for the question, such as "Database".
  final String header;
  final List<QuestionOption> options;
  final bool multiSelect;

  Json toJson() => {
    'question': question,
    'header': header,
    'options': [for (final o in options) o.toJson()],
    'multiSelect': multiSelect,
  };
}

class QuestionOption {
  const QuestionOption(this.label, {this.description = ''});

  factory QuestionOption.fromJson(Json json) => QuestionOption(
    json['label'] as String,
    description: json['description'] as String? ?? '',
  );

  final String label;
  final String description;

  Json toJson() => {'label': label, 'description': description};
}

/// A one-line summary of [questions] for notifications and previews, e.g.
/// "Which database should I use? Options: Postgres or SQLite (+1 more
/// question)".
String describeQuestions(List<AgentQuestion> questions) {
  if (questions.isEmpty) return 'It needs your input';
  final first = questions.first;
  final labels = [for (final o in first.options) o.label];
  final choices = switch (labels) {
    [] => '',
    [final only] => ' Option: $only',
    [...final rest, final last] => ' Options: ${rest.join(', ')} or $last',
  };
  final more = questions.length - 1;
  return '${first.question}$choices'
      '${more > 0 ? ' (+$more more question${more == 1 ? '' : 's'})' : ''}';
}
