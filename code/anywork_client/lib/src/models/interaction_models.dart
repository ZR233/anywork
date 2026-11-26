import 'dart:convert';

import 'studio_enums.dart';

const agentSessionPlanConfirmationQuestionId = 'plan_confirmation';
const agentSessionPlanApproveAnswer = 'Approve';
const agentSessionPlanReviseAnswer = 'Revise';

sealed class InteractionPayload {
  const InteractionPayload();
}

class UnknownInteractionPayload extends InteractionPayload {
  const UnknownInteractionPayload();
}

class UserInputInteractionPayload extends InteractionPayload {
  const UserInputInteractionPayload({required this.questions});

  final List<UserQuestionView> questions;
}

class ToolApprovalInteractionPayload extends InteractionPayload {
  const ToolApprovalInteractionPayload({
    required this.toolName,
    this.arguments,
    required this.workingDirectory,
    this.parentAgentId,
  });

  final String toolName;
  final Object? arguments;
  final String workingDirectory;
  final String? parentAgentId;
}

class UserQuestionView {
  const UserQuestionView({
    required this.id,
    required this.header,
    required this.question,
    required this.isSecret,
    required this.options,
  });

  final String id;
  final String header;
  final String question;
  final bool isSecret;
  final List<UserQuestionOptionView> options;
}

class UserQuestionOptionView {
  const UserQuestionOptionView({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}

class PendingInteraction {
  const PendingInteraction({
    required this.id,
    required this.threadId,
    required this.turnId,
    required this.kind,
    required this.title,
    required this.body,
    this.payload = const UnknownInteractionPayload(),
    this.revision = 0,
  });

  factory PendingInteraction.fromPayload({
    required String id,
    required String threadId,
    required String turnId,
    required InteractionKind kind,
    required InteractionPayload payload,
    required int revision,
  }) => PendingInteraction(
    id: id,
    threadId: threadId,
    turnId: turnId,
    kind: kind,
    payload: payload,
    revision: revision,
    title: switch (payload) {
      ToolApprovalInteractionPayload(:final toolName) =>
        toolName.isEmpty ? 'Tool approval' : toolName,
      UserInputInteractionPayload() => 'User input requested',
      UnknownInteractionPayload() => switch (kind) {
        InteractionKind.toolApproval => 'Tool approval',
        InteractionKind.userInput => 'User input requested',
      },
    },
    body: switch (payload) {
      ToolApprovalInteractionPayload(arguments: null) => '',
      ToolApprovalInteractionPayload(arguments: final String text) => text,
      ToolApprovalInteractionPayload(:final arguments) =>
        const JsonEncoder.withIndent('  ').convert(arguments),
      UserInputInteractionPayload(:final questions) =>
        questions
            .map((question) => question.question)
            .where((question) => question.isNotEmpty)
            .join('\n'),
      UnknownInteractionPayload() => '',
    },
  );

  final String id;
  final String threadId;
  final String turnId;
  final InteractionKind kind;
  final String title;
  final String body;
  final InteractionPayload payload;

  /// 规范交互版本；决议请求的 CAS 基线。
  ///
  /// `0` 表示发布方未携带版本（例如本地演示数据），调用方据此不做版本前提。
  final int revision;

  /// 计划确认沿用通用 `UserInput` 载荷，但它是根会话自有的诊断事实。
  ///
  /// 子会话的计划请求既不进入主会话的可决议投影，也不能经该投影决议；判别只依据载荷里的
  /// 计划确认问题身份，不依赖标题或正文措辞。
  bool get isPlanConfirmation => switch (payload) {
    UserInputInteractionPayload(:final questions) => questions.any(
      (question) => question.id == agentSessionPlanConfirmationQuestionId,
    ),
    _ => false,
  };
}

/// Decodes the producer's canonical Current interaction without exposing a
/// lifecycle resolution or continuation as a new command authority.
({PendingInteraction interaction, bool pending}) decodeCurrentInteraction(
  Object? value, {
  required String expectedId,
  required String threadId,
}) {
  const invalid = FormatException('Invalid Current interaction');
  Map<String, Object?> object(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw invalid;
  }

  String string(Object? value) {
    if (value is String) return value;
    throw invalid;
  }

  int integer(Object? value) {
    if (value is int && value >= 0) return value;
    throw invalid;
  }

  List<Object?> list(Object? value) {
    if (value is List<Object?>) return value;
    throw invalid;
  }

  bool flag(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    throw invalid;
  }

  final request = object(value);
  final scope = object(request['scope']);
  if (string(request['interactionId']) != expectedId ||
      string(scope['threadId']) != threadId)
    throw invalid;
  final turnId = string(scope['turnId']);
  final revision = integer(request['revision']);
  if (request['createdAt'] is! int || request['updatedAt'] is! int)
    throw invalid;
  final content = object(request['content']);
  final data = object(content['data']);
  final status = string(object(data['state'])['kind']);
  if (!const {'pending', 'resolved', 'cancelled', 'expired'}.contains(status)) {
    throw invalid;
  }
  final InteractionKind kind;
  final InteractionPayload payload;
  switch (content['kind']) {
    case 'userInput':
      kind = InteractionKind.userInput;
      payload = UserInputInteractionPayload(
        questions: [
          for (final raw in list(data['questions']))
            (() {
              final question = object(raw);
              return UserQuestionView(
                id: string(question['id']),
                header: string(question['header']),
                question: string(question['question']),
                isSecret: flag(question['isSecret']),
                options: [
                  for (final raw
                      in question['options'] == null
                          ? const []
                          : list(question['options']))
                    (() {
                      final option = object(raw);
                      return UserQuestionOptionView(
                        label: string(option['label']),
                        description: string(option['description']),
                      );
                    })(),
                ],
              );
            })(),
        ],
      );
    case 'toolApproval':
      kind = InteractionKind.toolApproval;
      final approval = object(data['request']);
      if (!approval.containsKey('arguments')) throw invalid;
      payload = ToolApprovalInteractionPayload(
        toolName: string(approval['name']),
        arguments: approval['arguments'],
        workingDirectory: approval['workingDirectory'] == null
            ? ''
            : string(approval['workingDirectory']),
        parentAgentId: approval['parentAgentId'] == null
            ? null
            : string(approval['parentAgentId']),
      );
    default:
      throw invalid;
  }
  return (
    interaction: PendingInteraction.fromPayload(
      id: expectedId,
      threadId: threadId,
      turnId: turnId,
      kind: kind,
      payload: payload,
      revision: revision,
    ),
    pending: status == 'pending',
  );
}

class PlanConfirmationView {
  const PlanConfirmationView({
    required this.interaction,
    required this.question,
  });

  final PendingInteraction interaction;
  final UserQuestionView question;

  String get interactionId => interaction.id;

  String get questionId => question.id;

  String get markdown => question.question;

  String get title => planDocumentTitle(markdown, fallback: question.header);

  String get summary {
    for (final line in markdown.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      return trimmed
          .replaceFirst(RegExp(r'^[-*+]\s+'), '')
          .replaceFirst(RegExp(r'^\d+[.)]\s+'), '')
          .trim();
    }
    return '';
  }

  @override
  bool operator ==(Object other) {
    return other is PlanConfirmationView &&
        other.interactionId == interactionId &&
        other.questionId == questionId &&
        other.markdown == markdown;
  }

  @override
  int get hashCode => Object.hash(interactionId, questionId, markdown);
}

extension PendingInteractionPlanPresentation on PendingInteraction {
  PlanConfirmationView? get planConfirmation {
    if (kind != InteractionKind.userInput ||
        payload is! UserInputInteractionPayload) {
      return null;
    }
    final questions = (payload as UserInputInteractionPayload).questions;
    final matches = questions
        .where(
          (question) => question.id == agentSessionPlanConfirmationQuestionId,
        )
        .toList(growable: false);
    if (matches.length != 1) return null;
    return PlanConfirmationView(interaction: this, question: matches.single);
  }
}

/// 计划文档标题：第一个一级标题，缺失时退回 [fallback]。
///
/// 待确认的 canonical 问题正文与历史回执里的同一问题正文共用这一处提取，
/// 使摘要卡的标题与已回答回执的标题不可能来自两套规则。
String planDocumentTitle(String markdown, {String fallback = ''}) {
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('# ')) {
      final value = trimmed.substring(2).trim();
      if (value.isNotEmpty) return value;
    }
  }
  return fallback.trim();
}

class UserInputAnswerCommand {
  const UserInputAnswerCommand({
    required this.questionId,
    required this.answers,
  });

  final String questionId;
  final List<String> answers;
}

sealed class InteractionResolutionCommand {
  const InteractionResolutionCommand();
}

class UserInputResolutionCommand extends InteractionResolutionCommand {
  const UserInputResolutionCommand({required this.answers});

  final List<UserInputAnswerCommand> answers;
}

enum ToolApprovalDecision { approved, denied }

class ToolApprovalResolutionCommand extends InteractionResolutionCommand {
  const ToolApprovalResolutionCommand({required this.decision, this.reason});

  final ToolApprovalDecision decision;
  final String? reason;
}

int interactionPriority(InteractionKind kind) {
  return switch (kind) {
    InteractionKind.toolApproval => 0,
    InteractionKind.userInput => 1,
  };
}
