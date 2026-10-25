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
    required this.isOther,
    required this.isSecret,
    required this.options,
  });

  final String id;
  final String header;
  final String question;
  final bool isOther;
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
