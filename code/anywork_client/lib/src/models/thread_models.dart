import 'attachment_models.dart';
import 'composer_models.dart';
import 'interaction_models.dart';
import 'runtime_models.dart';
import 'studio_enums.dart';
import 'thread_activity_models.dart';
import 'thread_wait_models.dart';
import 'thread_directory_models.dart';
import 'timeline_models.dart';
import 'turn_models.dart';

enum ThreadItemKind {
  raw,
  userMessage,
  parentAgentMessage,
  agentMessage,
  reasoning,
  toolCall,
  agent,
  turn,
  inference,
  skill,
  file,
  contextCompaction,
}

enum AgentMessageChannel { commentary, finalAnswer }

enum ThreadTextChannel { user, parentAgent, commentary, finalAnswer }

class ThreadAttachmentView {
  const ThreadAttachmentView({
    required this.id,
    required this.modality,
    required this.mediaType,
    required this.byteSize,
    this.filename,
    this.width,
    this.height,
  });

  final String id;
  final AttachmentModalityView modality;
  final String mediaType;
  final String? filename;
  final int? width;
  final int? height;
  final int byteSize;
}

/// 内容字段身份（与后端 `BridgeContentField` 一一对应）。
///
/// 身份只由字段判别式决定，**不**从内容字符串推断：正文落在哪个 domain 字段完全由这里
/// 指定。推理分块用逻辑 `chunkIndex` 保持块身份，删除一块不会让其它块移动。
sealed class ThreadContentFieldView {
  const ThreadContentFieldView();

  /// 值语义键：判别分支 + 逻辑索引（分块、payload、问答位置与子字段）。
  ///
  /// 字段身份是**值**，不是对象实例：FRB 每帧解码出的参数化字段都是新实例，独立解码的
  /// 同值字段必须相等，否则详情引用表会随帧增长（design/26 §26.7）。
  Object get identityKey;

  @override
  bool operator ==(Object other) =>
      other is ThreadContentFieldView && other.identityKey == identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}

final class ThreadTextFieldView extends ThreadContentFieldView {
  const ThreadTextFieldView();

  @override
  Object get identityKey => (ThreadTextFieldView,);
}

final class ThreadThinkingSummaryFieldView extends ThreadContentFieldView {
  const ThreadThinkingSummaryFieldView(this.chunkIndex);
  final int chunkIndex;

  @override
  Object get identityKey => (ThreadThinkingSummaryFieldView, chunkIndex);
}

final class ThreadThinkingContentFieldView extends ThreadContentFieldView {
  const ThreadThinkingContentFieldView(this.chunkIndex);
  final int chunkIndex;

  @override
  Object get identityKey => (ThreadThinkingContentFieldView, chunkIndex);
}

final class ThreadToolArgumentsFieldView extends ThreadContentFieldView {
  const ThreadToolArgumentsFieldView();

  @override
  Object get identityKey => (ThreadToolArgumentsFieldView,);
}

final class ThreadToolResultFieldView extends ThreadContentFieldView {
  const ThreadToolResultFieldView();

  @override
  Object get identityKey => (ThreadToolResultFieldView,);
}

/// 工具一次执行附加的开放产物正文：只在 canonical 映射与详情查看边界编码。
///
/// 预览里的产物数组可以为空而原文仍然存在；只要本字段的详情引用还在，消费者就保留按需
/// 读取入口，不能按预览数组长度判断“没有产物”。
final class ThreadToolOutputArtifactsFieldView extends ThreadContentFieldView {
  const ThreadToolOutputArtifactsFieldView();

  @override
  Object get identityKey => (ThreadToolOutputArtifactsFieldView,);
}

/// 原始记录的一段正文：`payloadIndex` 是它在原记录里的顺序。
final class ThreadRawPayloadFieldView extends ThreadContentFieldView {
  const ThreadRawPayloadFieldView(this.payloadIndex);
  final int payloadIndex;

  @override
  Object get identityKey => (ThreadRawPayloadFieldView, payloadIndex);
}

/// 普通问答正文域：问题位置 + 该问题内的一段可展示正文。
///
/// 问答的标题、问题、选项与答案共享同一条内容预算，因此身份必须细到"哪一段"，而不是整条问答。
final class ThreadToolUserInputFieldView extends ThreadContentFieldView {
  const ThreadToolUserInputFieldView({
    required this.questionIndex,
    required this.part,
  });

  final int questionIndex;
  final ThreadUserInputFieldPartView part;

  @override
  Object get identityKey =>
      (ThreadToolUserInputFieldView, questionIndex, part.identityKey);
}

/// 普通问答投影里一段可展示正文的位置（与后端 `BridgeThreadUserInputFieldPart` 一一对应）。
sealed class ThreadUserInputFieldPartView {
  const ThreadUserInputFieldPartView();

  /// 值语义键：判别分支 + 选项/答案索引。
  Object get identityKey;

  @override
  bool operator ==(Object other) =>
      other is ThreadUserInputFieldPartView && other.identityKey == identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}

final class ThreadUserInputHeaderFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputHeaderFieldPartView();

  @override
  Object get identityKey => (ThreadUserInputHeaderFieldPartView,);
}

final class ThreadUserInputQuestionFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputQuestionFieldPartView();

  @override
  Object get identityKey => (ThreadUserInputQuestionFieldPartView,);
}

final class ThreadUserInputAnswerFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputAnswerFieldPartView(this.answerIndex);
  final int answerIndex;

  @override
  Object get identityKey => (ThreadUserInputAnswerFieldPartView, answerIndex);
}

final class ThreadUserInputOptionLabelFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputOptionLabelFieldPartView(this.optionIndex);
  final int optionIndex;

  @override
  Object get identityKey =>
      (ThreadUserInputOptionLabelFieldPartView, optionIndex);
}

final class ThreadUserInputOptionDescriptionFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputOptionDescriptionFieldPartView(this.optionIndex);
  final int optionIndex;

  @override
  Object get identityKey =>
      (ThreadUserInputOptionDescriptionFieldPartView, optionIndex);
}

/// 一个字段的 typed 变化（与后端 `BridgeFieldChange` 一一对应）。
///
/// [`Append`] 只在前缀仍有效时到达，追加到本地已交付末尾；[`Replace`] 是权威替换（含
/// 预览升级为完整正文）；[`Remove`] 丢弃该字段的本地副本；[`Unchanged`] 正文不动，但所属
/// 条目的 revision / omitted / 保存水位仍要在整组应用后提交。
sealed class ThreadFieldChangeView {
  const ThreadFieldChangeView();
}

final class UnchangedThreadFieldChangeView extends ThreadFieldChangeView {
  const UnchangedThreadFieldChangeView();
}

final class AppendThreadFieldChangeView extends ThreadFieldChangeView {
  const AppendThreadFieldChangeView(this.text);
  final String text;
}

final class ReplaceThreadFieldChangeView extends ThreadFieldChangeView {
  const ReplaceThreadFieldChangeView(this.text);
  final String text;
}

final class RemoveThreadFieldChangeView extends ThreadFieldChangeView {
  const RemoveThreadFieldChangeView();
}

/// 同一 item 的一个字段变化；一次 `UpdateItem` 携带整组，**原子应用后一次提交**版本。
class ThreadFieldUpdateView {
  const ThreadFieldUpdateView({required this.field, required this.change});

  final ThreadContentFieldView field;
  final ThreadFieldChangeView change;
}

sealed class ThreadContentLifecycleView {
  const ThreadContentLifecycleView();

  String get status => switch (this) {
    StreamingThreadContentView() => 'streaming',
    CompletedThreadContentView() => 'completed',
    FailedThreadContentView() => 'failed',
    CancelledThreadContentView() => 'cancelled',
  };

  bool get isTerminal => this is! StreamingThreadContentView;

  DateTime? get terminalAt => switch (this) {
    StreamingThreadContentView() => null,
    CompletedThreadContentView(:final completedAt) => completedAt,
    FailedThreadContentView(:final failedAt) => failedAt,
    CancelledThreadContentView(:final cancelledAt) => cancelledAt,
  };

  String? get failure => switch (this) {
    FailedThreadContentView(:final error) => error,
    StreamingThreadContentView() ||
    CompletedThreadContentView() ||
    CancelledThreadContentView() => null,
  };
}

final class StreamingThreadContentView extends ThreadContentLifecycleView {
  const StreamingThreadContentView();
}

final class CompletedThreadContentView extends ThreadContentLifecycleView {
  const CompletedThreadContentView(this.completedAt);
  final DateTime completedAt;
}

final class FailedThreadContentView extends ThreadContentLifecycleView {
  const FailedThreadContentView(this.failedAt, this.error);
  final DateTime failedAt;
  final String error;
}

final class CancelledThreadContentView extends ThreadContentLifecycleView {
  const CancelledThreadContentView(this.cancelledAt, this.reason);
  final DateTime cancelledAt;
  final String reason;
}

sealed class ThreadItemStateView {
  const ThreadItemStateView();
}

final class ThreadTextItemStateView extends ThreadItemStateView {
  const ThreadTextItemStateView({
    required this.channel,
    required this.text,
    required this.attachments,
    required this.lifecycle,
  });

  final ThreadTextChannel channel;
  final String text;
  final List<ThreadAttachmentView> attachments;
  final ThreadContentLifecycleView lifecycle;
}

final class ThreadThinkingItemStateView extends ThreadItemStateView {
  const ThreadThinkingItemStateView({
    required this.summary,
    required this.content,
    required this.lifecycle,
    this.summaryChunkBase = 0,
    this.contentChunkBase = 0,
  });

  final List<String> summary;
  final List<String> content;
  final ThreadContentLifecycleView lifecycle;

  /// 生产者 chunkIndex 是**逻辑**下标：本地列表因正文预算丢弃最旧整块后，下标整体
  /// 前移，必须靠 base 还原，后续 delta 才会写进正确的分块而不是错位或伪造缺口。
  final int summaryChunkBase;
  final int contentChunkBase;
}

final class ThreadSkillItemStateView extends ThreadItemStateView {
  const ThreadSkillItemStateView({
    required this.name,
    required this.source,
    required this.providerId,
    required this.resourceBase,
    required this.cause,
    required this.activatedAt,
  });

  final String name;
  final String source;
  final String providerId;
  final SkillResourceBaseView resourceBase;
  final SkillActivationCauseView cause;
  final DateTime activatedAt;
}

enum SkillResourceBaseKind { directory, url, opaque }

class SkillResourceBaseView {
  const SkillResourceBaseView(this.kind, this.value);
  final SkillResourceBaseKind kind;
  final String value;
}

enum SkillActivationCauseKind { tool, userGesture }

class SkillActivationCauseView {
  const SkillActivationCauseView(this.kind, this.id);
  final SkillActivationCauseKind kind;
  final String id;
}

/// 一条普通问答的只读历史投影：问题、权威状态与已接受的回答。
///
/// 它随发起提问的工具条目一起交付；`resolved` 才表示用户已回答，待回答与已取消各自是独立事实。
/// 问题复用交互自己的 `UserQuestionView`，问答不建立第二套问题模型。
class ThreadToolUserInputView {
  const ThreadToolUserInputView({
    required this.interactionId,
    required this.questions,
    required this.state,
  });

  final String interactionId;
  final List<UserQuestionView> questions;
  final ThreadToolUserInputStateView state;

  bool get isResolved => state is ResolvedThreadToolUserInputView;

  List<ThreadUserInputAnswerView> get answers => switch (state) {
    ResolvedThreadToolUserInputView(:final answers) => answers,
    _ => const [],
  };

  /// 已在窗口里交付的问题标题。
  String headerText(int questionIndex) =>
      _question(questionIndex)?.header ?? '';

  /// 已在窗口里交付的问题正文。
  String questionText(int questionIndex) =>
      _question(questionIndex)?.question ?? '';

  /// 已在窗口里交付的一个选项标签。
  String optionLabel(int questionIndex, int optionIndex) =>
      _option(questionIndex, optionIndex)?.label ?? '';

  /// 已在窗口里交付的一个选项说明。
  String optionDescription(int questionIndex, int optionIndex) =>
      _option(questionIndex, optionIndex)?.description ?? '';

  /// 已在窗口里交付的一个答案值。
  String answerText(int questionIndex, int answerIndex) {
    final values = _answer(questionIndex)?.answers;
    if (values == null || answerIndex < 0 || answerIndex >= values.length) {
      return '';
    }
    return values[answerIndex];
  }

  /// 用一段新的正文替换本地副本，只改这一段，保持结构、顺序与脱敏标记不变。
  ThreadToolUserInputView withText(
    int questionIndex,
    ThreadUserInputFieldPartView part,
    String text,
  ) {
    final question = _question(questionIndex);
    if (question == null) return this;
    switch (part) {
      case ThreadUserInputHeaderFieldPartView():
        return _withQuestion(
          questionIndex,
          _copyQuestion(question, header: text),
        );
      case ThreadUserInputQuestionFieldPartView():
        return _withQuestion(
          questionIndex,
          _copyQuestion(question, questionText: text),
        );
      case ThreadUserInputOptionLabelFieldPartView(:final optionIndex):
        return _withQuestion(
          questionIndex,
          _copyOption(question, optionIndex, label: text),
        );
      case ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex):
        return _withQuestion(
          questionIndex,
          _copyOption(question, optionIndex, description: text),
        );
      case ThreadUserInputAnswerFieldPartView(:final answerIndex):
        // 答案只在权威已解决状态上可写：一段正文永远不会把 pending/cancelled 变成“已回答”。
        if (state is! ResolvedThreadToolUserInputView) return this;
        return ThreadToolUserInputView(
          interactionId: interactionId,
          questions: questions,
          state: ResolvedThreadToolUserInputView([
            for (final answer in answers)
              answer.questionId == question.id
                  ? answer.withAnswer(answerIndex, text)
                  : answer,
          ]),
        );
    }
  }

  /// 把上一份投影的正文搬回只剩结构的本体，只移动正文、不移动身份。
  ThreadToolUserInputView withTextsFrom(ThreadToolUserInputView previous) {
    var next = this;
    for (var index = 0; index < next.questions.length; index++) {
      next = next
          .withText(
            index,
            const ThreadUserInputHeaderFieldPartView(),
            previous.headerText(index),
          )
          .withText(
            index,
            const ThreadUserInputQuestionFieldPartView(),
            previous.questionText(index),
          );
      final options = next.questions[index].options.length;
      for (var option = 0; option < options; option++) {
        next = next
            .withText(
              index,
              ThreadUserInputOptionLabelFieldPartView(option),
              previous.optionLabel(index, option),
            )
            .withText(
              index,
              ThreadUserInputOptionDescriptionFieldPartView(option),
              previous.optionDescription(index, option),
            );
      }
    }
    for (final answer in previous.answers) {
      final index = questionIndex(answer.questionId);
      if (index == null) continue;
      for (var value = 0; value < answer.answers.length; value++) {
        next = next.withText(
          index,
          ThreadUserInputAnswerFieldPartView(value),
          answer.answers[value],
        );
      }
    }
    return next;
  }

  /// 一个 question ID 在原问题顺序里的位置。
  int? questionIndex(String questionId) {
    for (var index = 0; index < questions.length; index++) {
      if (questions[index].id == questionId) return index;
    }
    return null;
  }

  UserQuestionView? _question(int questionIndex) =>
      questionIndex >= 0 && questionIndex < questions.length
      ? questions[questionIndex]
      : null;

  UserQuestionOptionView? _option(int questionIndex, int optionIndex) {
    final options = _question(questionIndex)?.options ?? const [];
    return optionIndex >= 0 && optionIndex < options.length
        ? options[optionIndex]
        : null;
  }

  ThreadUserInputAnswerView? _answer(int questionIndex) {
    final question = _question(questionIndex);
    if (question == null) return null;
    for (final answer in answers) {
      if (answer.questionId == question.id) return answer;
    }
    return null;
  }

  ThreadToolUserInputView _withQuestion(
    int questionIndex,
    UserQuestionView question,
  ) {
    final next = [...questions];
    next[questionIndex] = question;
    return ThreadToolUserInputView(
      interactionId: interactionId,
      questions: next,
      state: state,
    );
  }

  UserQuestionView _copyQuestion(
    UserQuestionView source, {
    String? header,
    String? questionText,
  }) {
    return UserQuestionView(
      id: source.id,
      header: header ?? source.header,
      question: questionText ?? source.question,
      isOther: source.isOther,
      isSecret: source.isSecret,
      options: source.options,
    );
  }

  UserQuestionView _copyOption(
    UserQuestionView question,
    int optionIndex, {
    String? label,
    String? description,
  }) {
    if (optionIndex < 0 || optionIndex >= question.options.length) {
      return question;
    }
    final options = [...question.options];
    options[optionIndex] = UserQuestionOptionView(
      label: label ?? options[optionIndex].label,
      description: description ?? options[optionIndex].description,
    );
    return UserQuestionView(
      id: question.id,
      header: question.header,
      question: question.question,
      isOther: question.isOther,
      isSecret: question.isSecret,
      options: options,
    );
  }
}

sealed class ThreadToolUserInputStateView {
  const ThreadToolUserInputStateView();
}

/// 计划确认回执的权威决定。
///
/// 只由该交互自己的已接受答案派生：`resolved` 表示交互已有回答，但回答里没有本版本
/// 认识的决定标记。后一种情况既不猜测批准也不猜测修改，只保留已回答这一事实。
enum PlanConfirmationDecisionView {
  pending,
  approved,
  revisionRequested,
  cancelled,
  resolved,
}

/// 计划确认的只读历史回执。
///
/// 来源是发起 `plan_submit` 的工具条目携带的同一 typed 问答投影：唯一
/// [agentSessionPlanConfirmationQuestionId] 问题标识计划语义，答案列表保留批准/修订
/// 决定与用户原始反馈。GUI 只把 [decision] 映射成本地化状态，不显示内部标记。
final class PlanConfirmationReceiptView {
  PlanConfirmationReceiptView({
    required this.interactionId,
    required this.title,
    required this.decision,
    Iterable<String> feedback = const [],
  }) : feedback = List.unmodifiable(feedback);

  final String interactionId;

  /// 计划标题（问题正文的一级标题），缺失时退回问题 header。
  final String title;

  final PlanConfirmationDecisionView decision;

  /// 用户原始反馈，按原顺序保留；批准与未知标记不产生反馈正文。
  final List<String> feedback;

  bool get isResolved => decision != PlanConfirmationDecisionView.pending;
}

extension ThreadToolUserInputPlanReceipt on ThreadToolUserInputView {
  /// 计划确认问题的唯一位置；不是恰好一个时不构成计划回执。
  UserQuestionView? get _planQuestion {
    final matches = questions
        .where(
          (question) => question.id == agentSessionPlanConfirmationQuestionId,
        )
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  /// 计划确认回执；普通问答或问题结构不完整时为空，由普通问答通道继续呈现。
  PlanConfirmationReceiptView? get planReceipt {
    final question = _planQuestion;
    if (question == null || questions.length != 1) return null;
    final title = planDocumentTitle(
      question.question,
      fallback: question.header,
    );
    final answer = answers
        .where((item) => item.questionId == question.id)
        .firstOrNull;
    final decision = switch (state) {
      PendingThreadToolUserInputView() => PlanConfirmationDecisionView.pending,
      CancelledThreadToolUserInputView() =>
        PlanConfirmationDecisionView.cancelled,
      ResolvedThreadToolUserInputView() => _planDecision(answer),
    };
    return PlanConfirmationReceiptView(
      interactionId: interactionId,
      title: title,
      decision: decision,
      feedback: _planFeedback(question, answer, decision),
    );
  }

  PlanConfirmationDecisionView _planDecision(
    ThreadUserInputAnswerView? answer,
  ) {
    final values = answer?.answers ?? const <String>[];
    if (values.contains(agentSessionPlanApproveAnswer)) {
      return PlanConfirmationDecisionView.approved;
    }
    if (values.contains(agentSessionPlanReviseAnswer)) {
      return PlanConfirmationDecisionView.revisionRequested;
    }
    return PlanConfirmationDecisionView.resolved;
  }

  /// 只把决定标记之后的原值当作反馈：敏感应答、未知标记和批准都不产生正文。
  List<String> _planFeedback(
    UserQuestionView question,
    ThreadUserInputAnswerView? answer,
    PlanConfirmationDecisionView decision,
  ) {
    if (answer == null || answer.redacted || question.isSecret) return const [];
    if (decision != PlanConfirmationDecisionView.revisionRequested) {
      return const [];
    }
    return [
      for (final value in answer.answers)
        if (value != agentSessionPlanApproveAnswer &&
            value != agentSessionPlanReviseAnswer &&
            value.trim().isNotEmpty)
          value,
    ];
  }
}

final class PendingThreadToolUserInputView
    extends ThreadToolUserInputStateView {
  const PendingThreadToolUserInputView();
}

final class ResolvedThreadToolUserInputView
    extends ThreadToolUserInputStateView {
  const ResolvedThreadToolUserInputView(this.answers);

  /// 按原问题顺序排列的已接受回答；没有回答的问题没有条目。
  final List<ThreadUserInputAnswerView> answers;
}

final class CancelledThreadToolUserInputView
    extends ThreadToolUserInputStateView {
  const CancelledThreadToolUserInputView();
}

/// 一个问题已接受的回答。`redacted` 为真时原值不进入公开投影，只保留已回答/已隐藏的状态。
class ThreadUserInputAnswerView {
  const ThreadUserInputAnswerView({
    required this.questionId,
    this.answers = const [],
    this.redacted = false,
  });

  final String questionId;
  final List<String> answers;
  final bool redacted;

  ThreadUserInputAnswerView withAnswers(List<String> answers) {
    return ThreadUserInputAnswerView(
      questionId: questionId,
      answers: answers,
      redacted: redacted,
    );
  }

  ThreadUserInputAnswerView withAnswer(int index, String text) {
    if (index < 0 || index >= answers.length) return this;
    final next = [...answers];
    next[index] = text;
    return withAnswers(next);
  }
}

class ThreadToolInvocationView {
  const ThreadToolInvocationView({
    required this.toolCallId,
    required this.name,
    required this.arguments,
    this.callId,
    this.providerItemId,
    this.workingDirectory,
    this.taskId,
  });

  final String toolCallId;
  final String? callId;
  final String? providerItemId;
  final String name;
  final String arguments;
  final String? workingDirectory;
  final String? taskId;

  ThreadToolInvocationView withArguments(String arguments) {
    return ThreadToolInvocationView(
      toolCallId: toolCallId,
      callId: callId,
      providerItemId: providerItemId,
      name: name,
      arguments: arguments,
      workingDirectory: workingDirectory,
      taskId: taskId,
    );
  }
}

class ThreadToolOutputView {
  const ThreadToolOutputView({
    required this.result,
    required this.attachments,
    required this.outputArtifacts,
    this.exitCode,
  });

  final String result;
  final List<ThreadAttachmentView> attachments;
  final List<Object?> outputArtifacts;
  final int? exitCode;
}

enum ThreadToolFailureKindView { execution, timedOut, budgetLimited }

class ThreadToolFailureView {
  const ThreadToolFailureView({required this.kind, required this.message});
  final ThreadToolFailureKindView kind;
  final String message;
}

sealed class ThreadToolLifecycleView {
  const ThreadToolLifecycleView();

  String get status => switch (this) {
    QueuedThreadToolView() => 'queued',
    CancellingThreadToolView() => 'cancelling',
    InterruptedThreadToolView() => 'interrupted',
    StartedThreadToolView() => 'started',
    StreamingThreadToolView() => 'streaming',
    AwaitingApprovalThreadToolView() => 'awaitingApproval',
    ApprovedThreadToolView() => 'approved',
    RunningThreadToolView() => 'running',
    SucceededThreadToolView() => 'succeeded',
    FailedThreadToolView() => 'failed',
    DeniedThreadToolView() => 'denied',
    CancelledThreadToolView() => 'cancelled',
  };

  bool get isTerminal => switch (this) {
    InterruptedThreadToolView() => true,
    QueuedThreadToolView() || CancellingThreadToolView() => false,
    SucceededThreadToolView() ||
    FailedThreadToolView() ||
    DeniedThreadToolView() ||
    CancelledThreadToolView() => true,
    StartedThreadToolView() ||
    StreamingThreadToolView() ||
    AwaitingApprovalThreadToolView() ||
    ApprovedThreadToolView() ||
    RunningThreadToolView() => false,
  };
}

final class StartedThreadToolView extends ThreadToolLifecycleView {
  const StartedThreadToolView();
}

final class QueuedThreadToolView extends ThreadToolLifecycleView {
  const QueuedThreadToolView();
}

final class CancellingThreadToolView extends ThreadToolLifecycleView {
  const CancellingThreadToolView(this.streamedOutput);
  final String streamedOutput;
}

final class InterruptedThreadToolView extends ThreadToolLifecycleView {
  const InterruptedThreadToolView(this.interruptedAt, this.reason);
  final DateTime interruptedAt;
  final String reason;
}

final class StreamingThreadToolView extends ThreadToolLifecycleView {
  const StreamingThreadToolView();
}

final class AwaitingApprovalThreadToolView extends ThreadToolLifecycleView {
  const AwaitingApprovalThreadToolView();
}

final class ApprovedThreadToolView extends ThreadToolLifecycleView {
  const ApprovedThreadToolView();
}

final class RunningThreadToolView extends ThreadToolLifecycleView {
  const RunningThreadToolView(this.streamedOutput);
  final String streamedOutput;
}

final class SucceededThreadToolView extends ThreadToolLifecycleView {
  const SucceededThreadToolView(this.completedAt, this.output);
  final DateTime completedAt;
  final ThreadToolOutputView output;
}

final class FailedThreadToolView extends ThreadToolLifecycleView {
  const FailedThreadToolView(this.failedAt, this.failure, this.output);
  final DateTime failedAt;
  final ThreadToolFailureView failure;
  final ThreadToolOutputView? output;
}

final class DeniedThreadToolView extends ThreadToolLifecycleView {
  const DeniedThreadToolView(this.deniedAt, this.reason);
  final DateTime deniedAt;
  final String reason;
}

final class CancelledThreadToolView extends ThreadToolLifecycleView {
  const CancelledThreadToolView(this.cancelledAt, this.reason);
  final DateTime cancelledAt;
  final String reason;
}

final class ThreadToolItemStateView extends ThreadItemStateView {
  const ThreadToolItemStateView({
    required this.invocation,
    required this.lifecycle,
    this.userInput,
    this.wait,
  });

  final ThreadToolInvocationView invocation;
  final ThreadToolLifecycleView lifecycle;

  /// 这条调用携带的普通问答历史；只有真正发起问答的调用才有。
  final ThreadToolUserInputView? userInput;

  /// Typed wait/sleep presentation; only wait/sleep calls with legal parameters have it.
  final ThreadWaitPresentationView? wait;
}

class ThreadAgentIdentityView {
  const ThreadAgentIdentityView({
    required this.id,
    required this.path,
    required this.role,
    required this.task,
    required this.depth,
    this.parentPath,
  });

  final String id;
  final String path;
  final String? parentPath;
  final String role;
  final String task;
  final int depth;
}

sealed class ThreadAgentLifecycleView {
  const ThreadAgentLifecycleView();
}

final class QueuedThreadAgentView extends ThreadAgentLifecycleView {
  const QueuedThreadAgentView();
}

final class RunningThreadAgentView extends ThreadAgentLifecycleView {
  const RunningThreadAgentView();
}

final class SucceededThreadAgentView extends ThreadAgentLifecycleView {
  const SucceededThreadAgentView(this.completedAt, this.summary);
  final DateTime completedAt;
  final String summary;
}

final class DeniedThreadAgentView extends ThreadAgentLifecycleView {
  const DeniedThreadAgentView(this.deniedAt, this.reason);
  final DateTime deniedAt;
  final String reason;
}

final class CancelledThreadAgentView extends ThreadAgentLifecycleView {
  const CancelledThreadAgentView(this.cancelledAt, this.reason);
  final DateTime cancelledAt;
  final String reason;
}

final class FailedThreadAgentView extends ThreadAgentLifecycleView {
  const FailedThreadAgentView(this.failedAt, this.error);
  final DateTime failedAt;
  final String error;
}

final class ThreadAgentItemStateView extends ThreadItemStateView {
  const ThreadAgentItemStateView({
    required this.identity,
    required this.lifecycle,
  });
  final ThreadAgentIdentityView identity;
  final ThreadAgentLifecycleView lifecycle;
}

final class ThreadTurnItemStateView extends ThreadItemStateView {
  const ThreadTurnItemStateView(this.state, {this.inputId});
  final StudioTurnState state;
  final String? inputId;
}

sealed class ThreadInferenceLifecycleView {
  const ThreadInferenceLifecycleView();
}

final class RunningThreadInferenceView extends ThreadInferenceLifecycleView {
  const RunningThreadInferenceView();
}

final class CompletedThreadInferenceView extends ThreadInferenceLifecycleView {
  const CompletedThreadInferenceView(this.completedAt, this.usage);
  final DateTime completedAt;
  final ThreadInferenceUsageView usage;
}

class ThreadInferenceUsageView {
  const ThreadInferenceUsageView({
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.totalTokens,
  });
  final int promptTokens;
  final int completionTokens;
  final int cachedPromptTokens;
  final int totalTokens;
}

final class FailedThreadInferenceView extends ThreadInferenceLifecycleView {
  const FailedThreadInferenceView(this.failedAt, this.error);
  final DateTime failedAt;
  final String error;
}

final class CancelledThreadInferenceView extends ThreadInferenceLifecycleView {
  const CancelledThreadInferenceView(this.cancelledAt, this.reason);
  final DateTime cancelledAt;
  final String reason;
}

final class ThreadInferenceItemStateView extends ThreadItemStateView {
  const ThreadInferenceItemStateView({
    required this.inferenceId,
    required this.model,
    required this.lifecycle,
  });
  final String inferenceId;
  final String model;
  final ThreadInferenceLifecycleView lifecycle;
}

class RawHistoryPayload {
  const RawHistoryPayload(this.format, this.version, this.content);
  final String format;
  final int version;
  final String content;
}

final class ThreadRawItemStateView extends ThreadItemStateView {
  const ThreadRawItemStateView(this.payloads, this.notice, this.recordedAt);
  final List<RawHistoryPayload> payloads;
  final String notice;
  final DateTime recordedAt;
}

final class ThreadFileItemStateView extends ThreadItemStateView {
  const ThreadFileItemStateView(this.path, this.mediaType, this.completedAt);
  final String path;
  final String? mediaType;
  final DateTime completedAt;
}

final class ThreadContextCompactionItemStateView extends ThreadItemStateView {
  const ThreadContextCompactionItemStateView(
    this.beforeTokens,
    this.afterTokens,
    this.compactedAt,
  );
  final int? beforeTokens;
  final int? afterTokens;
  final DateTime compactedAt;
}

class ThreadItemView {
  const ThreadItemView({
    required this.id,
    required this.threadId,
    required this.turnId,
    required this.ordinal,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
    this.contextDisposition = ThreadContextDisposition.active,
    this.bodyOmittedUnits = 0,
    this.executionTerminal = false,
    this.saved = true,
  });

  final String id;
  final String threadId;
  final String turnId;
  final int ordinal;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ThreadItemStateView state;
  final ThreadContextDisposition contextDisposition;

  /// 数据源声明的正文省略量；0 表示窗口交付了完整正文。
  final int bodyOmittedUnits;

  /// 窗口条目的执行终态事实（后端 `BridgeChatLifecycle`）。
  ///
  /// 与保存水位 [saved] 严格独立：终态可以尚未保存，已保存也仍可继续增量。终态身份不会
  /// 回退成 streaming，但仍接受可靠权威修订（正文补齐或更高 revision 的扩展）；`Append`
  /// 只是正文前缀差量的编码，不是执行权限。
  final bool executionTerminal;

  /// Execution completion and history durability are independent.
  final bool saved;

  /// 条目正文只以数据源声明的有界预览驻留：需要按身份补齐完整正文。
  bool get bodyPreviewed => bodyOmittedUnits > 0;

  ThreadItemKind get kind => switch (state) {
    ThreadTextItemStateView(:final channel) =>
      channel == ThreadTextChannel.user
          ? ThreadItemKind.userMessage
          : channel == ThreadTextChannel.parentAgent
          ? ThreadItemKind.parentAgentMessage
          : ThreadItemKind.agentMessage,
    ThreadThinkingItemStateView() => ThreadItemKind.reasoning,
    ThreadToolItemStateView() => ThreadItemKind.toolCall,
    ThreadAgentItemStateView() => ThreadItemKind.agent,
    ThreadTurnItemStateView() => ThreadItemKind.turn,
    ThreadInferenceItemStateView() => ThreadItemKind.inference,
    ThreadSkillItemStateView() => ThreadItemKind.skill,
    ThreadRawItemStateView() => ThreadItemKind.raw,
    ThreadFileItemStateView() => ThreadItemKind.file,
    ThreadContextCompactionItemStateView() => ThreadItemKind.contextCompaction,
  };

  String get status => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.status,
    ThreadToolItemStateView(:final lifecycle) => lifecycle.status,
    ThreadAgentItemStateView(:final lifecycle) => switch (lifecycle) {
      QueuedThreadAgentView() => 'queued',
      RunningThreadAgentView() => 'running',
      SucceededThreadAgentView() => 'succeeded',
      DeniedThreadAgentView() => 'denied',
      CancelledThreadAgentView() => 'cancelled',
      FailedThreadAgentView() => 'failed',
    },
    ThreadTurnItemStateView(:final state) => state.status.name,
    ThreadInferenceItemStateView(:final lifecycle) => switch (lifecycle) {
      RunningThreadInferenceView() => 'running',
      CompletedThreadInferenceView() => 'completed',
      FailedThreadInferenceView() => 'failed',
      CancelledThreadInferenceView() => 'cancelled',
    },
    ThreadSkillItemStateView() ||
    ThreadFileItemStateView() ||
    ThreadRawItemStateView() ||
    ThreadContextCompactionItemStateView() => 'completed',
  };

  bool get isTerminal => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.isTerminal,
    ThreadToolItemStateView(:final lifecycle) => lifecycle.isTerminal,
    ThreadAgentItemStateView(:final lifecycle) =>
      lifecycle is! QueuedThreadAgentView &&
          lifecycle is! RunningThreadAgentView,
    ThreadTurnItemStateView(:final state) => state.isTerminal,
    ThreadInferenceItemStateView(:final lifecycle) =>
      lifecycle is! RunningThreadInferenceView,
    ThreadSkillItemStateView() ||
    ThreadFileItemStateView() ||
    ThreadRawItemStateView() ||
    ThreadContextCompactionItemStateView() => true,
  };

  DateTime? get completedAt => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.terminalAt,
    ThreadToolItemStateView(:final lifecycle) => switch (lifecycle) {
      InterruptedThreadToolView(:final interruptedAt) => interruptedAt,
      QueuedThreadToolView() || CancellingThreadToolView() => null,
      SucceededThreadToolView(:final completedAt) => completedAt,
      FailedThreadToolView(:final failedAt) => failedAt,
      DeniedThreadToolView(:final deniedAt) => deniedAt,
      CancelledThreadToolView(:final cancelledAt) => cancelledAt,
      StartedThreadToolView() ||
      StreamingThreadToolView() ||
      AwaitingApprovalThreadToolView() ||
      ApprovedThreadToolView() ||
      RunningThreadToolView() => null,
    },
    ThreadAgentItemStateView(:final lifecycle) => switch (lifecycle) {
      SucceededThreadAgentView(:final completedAt) => completedAt,
      DeniedThreadAgentView(:final deniedAt) => deniedAt,
      CancelledThreadAgentView(:final cancelledAt) => cancelledAt,
      FailedThreadAgentView(:final failedAt) => failedAt,
      QueuedThreadAgentView() || RunningThreadAgentView() => null,
    },
    ThreadTurnItemStateView(:final state) => switch (state) {
      CompletedStudioTurnState(:final completedAt) ||
      CancelledStudioTurnState(:final completedAt) ||
      FailedStudioTurnState(:final completedAt) ||
      BudgetLimitedStudioTurnState(
        :final completedAt,
      ) => DateTime.fromMillisecondsSinceEpoch(completedAt * 1000),
      QueuedStudioTurnState() || RunningStudioTurnState() => null,
    },
    ThreadInferenceItemStateView(:final lifecycle) => switch (lifecycle) {
      CompletedThreadInferenceView(:final completedAt) => completedAt,
      FailedThreadInferenceView(:final failedAt) => failedAt,
      CancelledThreadInferenceView(:final cancelledAt) => cancelledAt,
      RunningThreadInferenceView() => null,
    },
    ThreadSkillItemStateView(:final activatedAt) => activatedAt,
    ThreadRawItemStateView(:final recordedAt) => recordedAt,
    ThreadFileItemStateView(:final completedAt) => completedAt,
    ThreadContextCompactionItemStateView(:final compactedAt) => compactedAt,
  };

  String? get error => switch (state) {
    ThreadTextItemStateView(:final lifecycle) ||
    ThreadThinkingItemStateView(:final lifecycle) => lifecycle.failure,
    ThreadToolItemStateView(:final lifecycle) => switch (lifecycle) {
      FailedThreadToolView(:final failure) => failure.message,
      InterruptedThreadToolView(:final reason) => reason,
      _ => null,
    },
    ThreadAgentItemStateView(:final lifecycle) => switch (lifecycle) {
      FailedThreadAgentView(:final error) => error,
      _ => null,
    },
    ThreadTurnItemStateView(:final state) => state.reason,
    ThreadInferenceItemStateView(:final lifecycle) => switch (lifecycle) {
      FailedThreadInferenceView(:final error) => error,
      _ => null,
    },
    ThreadSkillItemStateView() ||
    ThreadFileItemStateView() ||
    ThreadRawItemStateView() ||
    ThreadContextCompactionItemStateView() => null,
  };

  String get text => switch (state) {
    ThreadRawItemStateView(:final notice) => notice,
    ThreadTextItemStateView(:final text) => text,
    ThreadAgentItemStateView(:final lifecycle) => switch (lifecycle) {
      SucceededThreadAgentView(:final summary) => summary,
      DeniedThreadAgentView(:final reason) ||
      CancelledThreadAgentView(:final reason) => reason,
      FailedThreadAgentView(:final error) => error,
      QueuedThreadAgentView() || RunningThreadAgentView() => '',
    },
    ThreadSkillItemStateView(:final name) => name,
    _ => '',
  };

  AgentMessageChannel? get channel => switch (state) {
    ThreadTextItemStateView(channel: ThreadTextChannel.commentary) =>
      AgentMessageChannel.commentary,
    ThreadTextItemStateView(channel: ThreadTextChannel.finalAnswer) =>
      AgentMessageChannel.finalAnswer,
    _ => null,
  };

  List<ThreadAttachmentView> get attachments => switch (state) {
    ThreadTextItemStateView(:final attachments) => attachments,
    _ => const [],
  };

  List<String> get reasoningSummary => switch (state) {
    ThreadThinkingItemStateView(:final summary) => summary,
    _ => const [],
  };

  List<String> get reasoningContent => switch (state) {
    ThreadThinkingItemStateView(:final content) => content,
    _ => const [],
  };

  String? get filePath => switch (state) {
    ThreadFileItemStateView(:final path) => path,
    _ => null,
  };

  String? get mediaType => switch (state) {
    ThreadFileItemStateView(:final mediaType) => mediaType,
    _ => null,
  };

  ThreadSkillItemStateView? get skill => switch (state) {
    final ThreadSkillItemStateView skill => skill,
    _ => null,
  };

  TimelineToolPart? get tool => switch (state) {
    ThreadToolItemStateView(
      :final invocation,
      :final lifecycle,
      :final userInput,
      :final wait,
    ) =>
      TimelineToolPart(
        taskId: invocation.taskId,
        toolCallId: invocation.toolCallId,
        callId: invocation.callId,
        providerItemId: invocation.providerItemId,
        name: invocation.name,
        arguments: invocation.arguments,
        userInput: userInput,
        wait: wait,
        result: switch (lifecycle) {
          RunningThreadToolView(:final streamedOutput) ||
          CancellingThreadToolView(:final streamedOutput) => streamedOutput,
          SucceededThreadToolView(:final output) => output.result,
          FailedThreadToolView(:final output) => output?.result,
          _ => null,
        },
        outputArtifacts: switch (lifecycle) {
          SucceededThreadToolView(:final output) => output.outputArtifacts,
          FailedThreadToolView(:final output) =>
            output?.outputArtifacts ?? const [],
          _ => const [],
        },
        attachments: switch (lifecycle) {
          SucceededThreadToolView(:final output) => output.attachments,
          FailedThreadToolView(:final output) =>
            output?.attachments ?? const [],
          _ => const [],
        },
        exitCode: switch (lifecycle) {
          SucceededThreadToolView(:final output) => output.exitCode,
          FailedThreadToolView(:final output) => output?.exitCode,
          _ => null,
        },
        timedOut: switch (lifecycle) {
          FailedThreadToolView(
            failure: ThreadToolFailureView(
              kind: ThreadToolFailureKindView.timedOut,
            ),
          ) =>
            true,
          _ => false,
        },
        workingDirectory: invocation.workingDirectory,
        denialReason: switch (lifecycle) {
          DeniedThreadToolView(:final reason) => reason,
          _ => null,
        },
      ),
    _ => null,
  };

  /// 原子应用一帧 `BridgeViewChange::UpdateItem` 的整组字段变化。
  ///
  /// 语义（与后端/core 契约一致）：
  /// 1. 本地 `revision` 必须等于 [expectedRevision]，否则基线不连续 → 返回 null 让调用方
  ///    重建权威窗口，**不逐字段升版本**。
  /// 2. 逐个应用 `fields`：`Append` 追加到本地字段末尾、`Replace` 整体替换、`Remove` 丢弃本地
  ///    副本（推理块按 `chunkIndex` 删除，不移动其它块身份）、`Unchanged` 正文不动。
  /// 3. 全部字段应用完成后**一次**提交 [revision]、[omittedUnits] 与保存水位 [saved]；即使
  ///    字段全为 `Unchanged`（仅版本推进 / 仅保存确认）也要提交，不能当成空帧丢弃。
  ///
  /// 真正的不变量（不在此重做 producer 准入）：
  /// - 身份与顺序稳定：`itemShell` 的 item/ordinal 必须与本条一致；Turn 关联不是 identity，
  ///   可靠的更高 revision 允许重新绑定 Turn。
  /// - revision 不倒退（`revision >= this.revision`），且同 revision 不得回退已交付的省略量或
  ///   保存水位。
  /// - 终态身份保持终态：不得 `terminal → streaming`；终态仍可接受可靠权威修订（含
  ///   `Append`/`Replace` 的正文补齐或更高 revision 的扩展），因为 `Append` 只是正文前缀差量
  ///   的编码，不是执行权限。
  /// - 同 revision 的预览补齐是合法更新：core 允许预览被权威完整正文在**不伪增 revision** 的
  ///   情况下补齐（`pl-core/tests/chat_page.rs` 的同 revision 用例），差量可以是 `Append` 或
  ///   `Replace`。
  ThreadItemView? applyFieldUpdates({
    required List<ThreadFieldUpdateView> fields,
    required int expectedRevision,
    required int revision,
    required int omittedUnits,
    required bool saved,
    required bool terminal,
    ThreadItemView? itemShell,
  }) {
    if (this.revision != expectedRevision) return null;
    // revision 是内容版本：任何帧都不能让它倒退。
    if (revision < this.revision) return null;
    // 终态只能保持终态；终态仍可接受可靠权威修订（见上文不变量）。
    if (executionTerminal && !terminal) return null;
    if (revision == this.revision) {
      // 同 revision 只能推进或保持事实：省略量不得回升，已保存不得回退。
      if (omittedUnits > bodyOmittedUnits) return null;
      if (this.saved && !saved) return null;
    }
    var nextState = state;
    if (itemShell != null) {
      // 身份与顺序必须稳定；Turn 关联不是 identity，允许可靠修订重新绑定。
      if (itemShell.id != id || itemShell.ordinal != ordinal) return null;
      final seeded = _seedDynamicFieldsFromCurrent(state, itemShell.state);
      if (seeded == null) return null;
      nextState = seeded;
    }
    var nextOmitted = omittedUnits;
    for (final update in fields) {
      if (itemShell != null &&
          update.field is ThreadToolResultFieldView &&
          update.change is RemoveThreadFieldChangeView &&
          nextState is ThreadToolItemStateView &&
          nextState.lifecycle is! RunningThreadToolView &&
          nextState.lifecycle is! CancellingThreadToolView) {
        // Running/Cancelling -> Succeeded/Failed removes the streaming
        // tool.result field while itemShell already carries the terminal output.
        continue;
      }
      final applied = _applyFieldChange(
        nextState,
        update.field,
        update.change,
        nextOmitted,
      );
      if (applied == null) return null;
      nextState = applied.state;
      nextOmitted = applied.omittedUnits;
    }
    return copyWith(
      turnId: itemShell?.turnId,
      revision: revision,
      updatedAt: itemShell?.updatedAt,
      state: nextState,
      contextDisposition: itemShell?.contextDisposition,
      bodyOmittedUnits: nextOmitted,
      saved: saved,
      executionTerminal: terminal,
    );
  }

  ThreadItemStateView? _seedDynamicFieldsFromCurrent(
    ThreadItemStateView current,
    ThreadItemStateView shell,
  ) {
    return switch ((current, shell)) {
      (
        ThreadTextItemStateView(:final text),
        ThreadTextItemStateView(
          :final channel,
          :final attachments,
          :final lifecycle,
        ),
      ) =>
        ThreadTextItemStateView(
          channel: channel,
          text: text,
          attachments: attachments,
          lifecycle: lifecycle,
        ),
      (
        ThreadThinkingItemStateView(
          :final summary,
          :final content,
          :final summaryChunkBase,
          :final contentChunkBase,
        ),
        ThreadThinkingItemStateView(:final lifecycle),
      ) =>
        ThreadThinkingItemStateView(
          summary: summary,
          content: content,
          summaryChunkBase: summaryChunkBase,
          contentChunkBase: contentChunkBase,
          lifecycle: lifecycle,
        ),
      (
        ThreadToolItemStateView(
          invocation: final currentInvocation,
          lifecycle: final currentLifecycle,
          userInput: final currentUserInput,
          wait: final currentWait,
        ),
        ThreadToolItemStateView(
          invocation: final shellInvocation,
          lifecycle: final shellLifecycle,
          userInput: final shellUserInput,
          wait: final shellWait,
        ),
      ) =>
        ThreadToolItemStateView(
          invocation: shellInvocation.withArguments(
            currentInvocation.arguments,
          ),
          lifecycle: switch ((currentLifecycle, shellLifecycle)) {
            (
              RunningThreadToolView(:final streamedOutput) ||
                  CancellingThreadToolView(:final streamedOutput),
              RunningThreadToolView(),
            ) =>
              RunningThreadToolView(streamedOutput),
            (
              RunningThreadToolView(:final streamedOutput) ||
                  CancellingThreadToolView(:final streamedOutput),
              CancellingThreadToolView(),
            ) =>
              CancellingThreadToolView(streamedOutput),
            _ => shellLifecycle,
          },
          // 问答结构来自权威 shell，正文来自本窗口已交付的副本；字段变化随后叠加其上。
          userInput: switch ((currentUserInput, shellUserInput)) {
            (final current?, final shell?) => shell.withTextsFrom(current),
            (_, final shell) => shell,
          },
          wait: shellWait ?? currentWait,
        ),
      _ when current.runtimeType == shell.runtimeType => shell,
      _ => null,
    };
  }

  /// 把一个 typed 字段变化落进当前条目状态；返回 null 表示字段身份与条目不匹配（重同步）。
  ({ThreadItemStateView state, int omittedUnits})? _applyFieldChange(
    ThreadItemStateView current,
    ThreadContentFieldView field,
    ThreadFieldChangeView change,
    int omittedUnits,
  ) {
    switch (current) {
      case ThreadTextItemStateView(
        :final channel,
        :final text,
        :final attachments,
        :final lifecycle,
      ):
        if (field is! ThreadTextFieldView) return null;
        return (
          state: ThreadTextItemStateView(
            channel: channel,
            text: _applyTextChange(text, change),
            attachments: attachments,
            lifecycle: lifecycle,
          ),
          omittedUnits: omittedUnits,
        );
      case ThreadThinkingItemStateView(
        :final summary,
        :final content,
        :final summaryChunkBase,
        :final contentChunkBase,
        :final lifecycle,
      ):
        final addressed = switch (field) {
          ThreadThinkingSummaryFieldView(:final chunkIndex) => (
            isSummary: true,
            chunkIndex: chunkIndex,
          ),
          ThreadThinkingContentFieldView(:final chunkIndex) => (
            isSummary: false,
            chunkIndex: chunkIndex,
          ),
          _ => null,
        };
        if (addressed == null) return null;
        final isSummary = addressed.isSummary;
        final chunkIndex = addressed.chunkIndex;
        final changed = _applyChunkChange(
          isSummary ? summary : content,
          isSummary ? summaryChunkBase : contentChunkBase,
          chunkIndex,
          change,
        );
        if (changed == null) return null;
        return (
          state: ThreadThinkingItemStateView(
            summary: isSummary ? changed.chunks : summary,
            content: isSummary ? content : changed.chunks,
            summaryChunkBase: summaryChunkBase,
            contentChunkBase: contentChunkBase,
            lifecycle: lifecycle,
          ),
          omittedUnits: omittedUnits,
        );
      case ThreadToolItemStateView(
        :final invocation,
        :final lifecycle,
        :final userInput,
        :final wait,
      ):
        switch (field) {
          case ThreadToolArgumentsFieldView():
            return (
              state: ThreadToolItemStateView(
                invocation: invocation.withArguments(
                  _applyTextChange(invocation.arguments, change),
                ),
                lifecycle: lifecycle,
                userInput: userInput,
                wait: wait,
              ),
              omittedUnits: omittedUnits,
            );
          case ThreadToolResultFieldView():
            return (
              state: ThreadToolItemStateView(
                invocation: invocation,
                lifecycle: _applyToolOutput(lifecycle, change),
                userInput: userInput,
                wait: wait,
              ),
              omittedUnits: omittedUnits,
            );
          case ThreadToolOutputArtifactsFieldView():
            // 产物正文是**独立内容字段**：完整文本只在详情查看器里读取，typed 预览数组由
            // 权威条目修订携带。这里接受整段替换/追加而不在 reducer 里解析 JSON，只推进
            // 字节账目；`Remove` 才清掉预览数组里那一份已交付值。
            return (
              state: ThreadToolItemStateView(
                invocation: invocation,
                lifecycle: change is RemoveThreadFieldChangeView
                    ? _withToolArtifacts(lifecycle, const [])
                    : lifecycle,
                userInput: userInput,
                wait: wait,
              ),
              omittedUnits: omittedUnits,
            );
          case ThreadToolUserInputFieldView(:final questionIndex, :final part):
            if (userInput == null) return null;
            final current = switch (part) {
              ThreadUserInputHeaderFieldPartView() => userInput.headerText(
                questionIndex,
              ),
              ThreadUserInputQuestionFieldPartView() => userInput.questionText(
                questionIndex,
              ),
              ThreadUserInputAnswerFieldPartView(:final answerIndex) =>
                userInput.answerText(questionIndex, answerIndex),
              ThreadUserInputOptionLabelFieldPartView(:final optionIndex) =>
                userInput.optionLabel(questionIndex, optionIndex),
              ThreadUserInputOptionDescriptionFieldPartView(
                :final optionIndex,
              ) =>
                userInput.optionDescription(questionIndex, optionIndex),
            };
            return (
              state: ThreadToolItemStateView(
                invocation: invocation,
                lifecycle: lifecycle,
                wait: wait,
                userInput: userInput.withText(
                  questionIndex,
                  part,
                  _applyTextChange(current, change),
                ),
              ),
              omittedUnits: omittedUnits,
            );
          default:
            return null;
        }
      case ThreadRawItemStateView(
        :final payloads,
        :final notice,
        :final recordedAt,
      ):
        final target = switch (field) {
          ThreadRawPayloadFieldView(:final payloadIndex) => payloadIndex,
          _ => null,
        };
        if (target == null || target < 0 || target >= payloads.length) {
          return null;
        }
        // 原始记录正文同样有独立详情字段：替换/追加只推进字节账目，不在 reducer 里解析
        // 载荷；删除该段才从 typed 预览里移除对应载荷。
        return (
          state: ThreadRawItemStateView(
            change is RemoveThreadFieldChangeView
                ? ([...payloads]..removeAt(target))
                : payloads,
            notice,
            recordedAt,
          ),
          omittedUnits: omittedUnits,
        );
      default:
        return null;
    }
  }

  ThreadItemView copyWith({
    String? turnId,
    int? ordinal,
    int? revision,
    DateTime? updatedAt,
    ThreadItemStateView? state,
    ThreadContextDisposition? contextDisposition,
    int? bodyOmittedUnits,
    bool? executionTerminal,
    bool? saved,
  }) {
    return ThreadItemView(
      id: id,
      threadId: threadId,
      turnId: turnId ?? this.turnId,
      ordinal: ordinal ?? this.ordinal,
      revision: revision ?? this.revision,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      state: state ?? this.state,
      contextDisposition: contextDisposition ?? this.contextDisposition,
      bodyOmittedUnits: bodyOmittedUnits ?? this.bodyOmittedUnits,
      executionTerminal: executionTerminal ?? this.executionTerminal,
      saved: saved ?? this.saved,
    );
  }

  /// 权威整条预览落在**已交付**的同 revision 事实上（design/26 §26.7）。
  ///
  /// 尾部 `Add` 携带权威整条预览，既不保证该身份从未被页查询加载，也不保证随后还会
  /// 补发同一事实的 `UpdateItem`；因此已加载身份必须在这里原位收敛，而不是等待更新。
  /// 调用方按 revision 分派：更高 revision 直接采纳权威条目（它自带自己的保存水位），
  /// 更旧 revision 不得覆盖已加载的新 revision。
  ///
  /// 本方法只处理**同 revision**：逐字段取更完整者，保存水位与执行终态不回退，Turn 关联、
  /// 更新时间与上下文处置采用权威条目。返回 null 表示两者无法证明是同一条事实（调用方
  /// 必须显式重同步）。
  ///
  /// 本 helper **不**自行计算整体省略量：它不拥有别的条目的字段总长，无法验证合成后的
  /// 账目。`omittedBytes` 由持有逐字段详情引用、已核实预览支配关系与产品预算的调用方传入
  /// （design/26 §26.8）；负数直接拒绝。
  ///
  /// 稳定身份只要求 `id`/`ordinal` 不变，**不**要求保持同一个 Dart 对象实例；条目正文与
  /// 元数据字段由实现各自收敛，不做为了指针复用的全字段值相等优化。
  ThreadItemView? convergeWith(
    ThreadItemView incoming, {
    required int omittedBytes,
  }) {
    if (omittedBytes < 0) {
      throw ArgumentError.value(
        omittedBytes,
        'omittedBytes',
        'omitted bytes must be non-negative',
      );
    }
    if (id != incoming.id || ordinal != incoming.ordinal) return null;
    if (revision != incoming.revision) return null;
    final merged = _convergeState(state, incoming.state);
    if (merged == null) return null;
    return incoming.copyWith(
      revision: revision,
      state: merged,
      bodyOmittedUnits: omittedBytes,
      executionTerminal: executionTerminal || incoming.executionTerminal,
      saved: saved || incoming.saved,
    );
  }
}

/// 同一身份的权威整条预览落在**已交付**的同 revision 事实上（design/26 §26.7）。
///
/// 语义是「同一事实的更完整交付」：逐字段取更完整者，保存水位、执行终态与省略量不回退，
/// Turn 关联／更新时间／上下文处置采用权威条目。返回 null 表示两者无法证明是同一事实，
/// 调用方必须显式重同步，不能把片段当成正文继续应用。
ThreadItemStateView? _convergeState(
  ThreadItemStateView current,
  ThreadItemStateView incoming,
) {
  switch ((current, incoming)) {
    case (ThreadTextItemStateView a, ThreadTextItemStateView b):
      if (a.channel != b.channel) return null;
      final text = _convergeText(a.text, b.text);
      if (text == null) return null;
      return ThreadTextItemStateView(
        channel: b.channel,
        text: text,
        attachments: a.attachments.length <= b.attachments.length
            ? b.attachments
            : a.attachments,
        lifecycle: _convergeContentLifecycle(a.lifecycle, b.lifecycle),
      );
    case (ThreadThinkingItemStateView a, ThreadThinkingItemStateView b):
      // chunk base 是分块坐标系的一部分：坐标系变了就不是同一份内容。
      if (a.summaryChunkBase != b.summaryChunkBase ||
          a.contentChunkBase != b.contentChunkBase) {
        return null;
      }
      final summary = _convergeChunks(a.summary, b.summary);
      if (summary == null) return null;
      final content = _convergeChunks(a.content, b.content);
      if (content == null) return null;
      return ThreadThinkingItemStateView(
        summary: summary,
        content: content,
        lifecycle: _convergeContentLifecycle(a.lifecycle, b.lifecycle),
        summaryChunkBase: b.summaryChunkBase,
        contentChunkBase: b.contentChunkBase,
      );
    case (ThreadToolItemStateView a, ThreadToolItemStateView b):
      final invocation = _convergeInvocation(a.invocation, b.invocation);
      if (invocation == null) return null;
      final userInput = _convergeUserInput(a.userInput, b.userInput);
      if (identical(userInput, _incompatibleUserInput)) return null;
      return ThreadToolItemStateView(
        invocation: invocation,
        lifecycle: _convergeToolLifecycle(a.lifecycle, b.lifecycle),
        userInput: userInput as ThreadToolUserInputView?,
        wait: b.wait ?? a.wait,
      );
    case (ThreadRawItemStateView a, ThreadRawItemStateView b):
      final payloads = _convergeRawPayloads(a.payloads, b.payloads);
      if (payloads == null) return null;
      final notice = _convergeText(a.notice, b.notice);
      if (notice == null) return null;
      return ThreadRawItemStateView(payloads, notice, b.recordedAt);
    case (ThreadFileItemStateView a, ThreadFileItemStateView b):
      return a.path == b.path ? b : null;
    case (ThreadSkillItemStateView a, ThreadSkillItemStateView b):
      return a.name == b.name ? b : null;
    case (ThreadAgentItemStateView a, ThreadAgentItemStateView b):
      return a.identity.id == b.identity.id ? b : null;
    case (ThreadTurnItemStateView a, ThreadTurnItemStateView b):
      return a.inputId == b.inputId ? b : null;
    case (ThreadInferenceItemStateView a, ThreadInferenceItemStateView b):
      return a.inferenceId == b.inferenceId ? b : null;
    case (
      ThreadContextCompactionItemStateView(),
      ThreadContextCompactionItemStateView(),
    ):
      return incoming;
    default:
      // 种类不同说明本地副本与权威条目已经不是同一条事实。
      return null;
  }
}

/// 同 revision 的两份文本只能是「同一正文的不同完整度」：互为前缀才可收敛。
String? _convergeText(String current, String incoming) {
  if (current == incoming) return current;
  if (incoming.startsWith(current)) return incoming;
  if (current.startsWith(incoming)) return current;
  return null;
}

/// 分块列表的收敛：除最后一块外必须逐块相同，最后一块按前缀规则取更完整者；
/// 多出来的块只能是后续追加块。
List<String>? _convergeChunks(List<String> current, List<String> incoming) {
  final common = current.length <= incoming.length
      ? current.length
      : incoming.length;
  for (var index = 0; index < common - 1; index++) {
    if (current[index] != incoming[index]) return null;
  }
  if (common == 0) {
    return current.length >= incoming.length ? current : incoming;
  }
  final last = _convergeText(current[common - 1], incoming[common - 1]);
  if (last == null) return null;
  final longer = current.length >= incoming.length ? current : incoming;
  return [...current.take(common - 1), last, ...longer.skip(common)];
}

/// 内容生命周期只允许前进：流式让位于任何已收束事实，其余保持本地已交付事实。
ThreadContentLifecycleView _convergeContentLifecycle(
  ThreadContentLifecycleView current,
  ThreadContentLifecycleView incoming,
) {
  if (current is StreamingThreadContentView &&
      incoming is! StreamingThreadContentView) {
    return incoming;
  }
  return current;
}

/// 工具生命周期的阶段单调前进；同阶段只在同一变体内合并已交付流式正文。
ThreadToolLifecycleView _convergeToolLifecycle(
  ThreadToolLifecycleView current,
  ThreadToolLifecycleView incoming,
) {
  if (current is RunningThreadToolView && incoming is RunningThreadToolView) {
    final output = _convergeText(
      current.streamedOutput,
      incoming.streamedOutput,
    );
    return output == null ? current : RunningThreadToolView(output);
  }
  if (current is CancellingThreadToolView &&
      incoming is CancellingThreadToolView) {
    final output = _convergeText(
      current.streamedOutput,
      incoming.streamedOutput,
    );
    return output == null ? current : CancellingThreadToolView(output);
  }
  if (current is SucceededThreadToolView &&
      incoming is SucceededThreadToolView) {
    return SucceededThreadToolView(
      current.completedAt,
      _convergeToolOutput(current.output, incoming.output),
    );
  }
  if (current.runtimeType == incoming.runtimeType) return current;
  return _toolLifecycleRank(incoming) > _toolLifecycleRank(current)
      ? incoming
      : current;
}

int _toolLifecycleRank(ThreadToolLifecycleView lifecycle) =>
    switch (lifecycle) {
      QueuedThreadToolView() => 0,
      StartedThreadToolView() => 1,
      StreamingThreadToolView() => 2,
      AwaitingApprovalThreadToolView() => 3,
      ApprovedThreadToolView() => 4,
      RunningThreadToolView() => 5,
      CancellingThreadToolView() => 6,
      InterruptedThreadToolView() ||
      SucceededThreadToolView() ||
      FailedThreadToolView() ||
      DeniedThreadToolView() ||
      CancelledThreadToolView() => 7,
    };

/// 工具输出正文按前缀规则收敛；附件与产物数组取更完整的一份。
ThreadToolOutputView _convergeToolOutput(
  ThreadToolOutputView current,
  ThreadToolOutputView incoming,
) {
  return ThreadToolOutputView(
    result: _convergeText(current.result, incoming.result) ?? current.result,
    attachments: current.attachments.length <= incoming.attachments.length
        ? incoming.attachments
        : current.attachments,
    outputArtifacts:
        current.outputArtifacts.length <= incoming.outputArtifacts.length
        ? incoming.outputArtifacts
        : current.outputArtifacts,
    exitCode: incoming.exitCode ?? current.exitCode,
  );
}

/// 调用身份必须一致；参数正文按前缀规则取更完整者。
ThreadToolInvocationView? _convergeInvocation(
  ThreadToolInvocationView current,
  ThreadToolInvocationView incoming,
) {
  if (current.toolCallId != incoming.toolCallId ||
      current.name != incoming.name ||
      current.callId != incoming.callId ||
      current.providerItemId != incoming.providerItemId ||
      current.taskId != incoming.taskId ||
      current.workingDirectory != incoming.workingDirectory) {
    return null;
  }
  final arguments = _convergeText(current.arguments, incoming.arguments);
  if (arguments == null) return null;
  return incoming.withArguments(arguments);
}

/// 问答正文的收敛：结构来自权威副本，已交付正文与已解决状态不回退。
///
/// 返回 [_incompatibleUserInput] 表示两份问答已经不是同一个交互。
Object? _convergeUserInput(
  ThreadToolUserInputView? current,
  ThreadToolUserInputView? incoming,
) {
  if (current == null) return incoming;
  if (incoming == null) return current;
  if (current.interactionId != incoming.interactionId) {
    return _incompatibleUserInput;
  }
  // 结构来自权威副本；已交付正文（含已解决状态的答案）先按原样搬回，再看权威副本里
  // 是否存在更完整的同段正文。
  var merged = incoming.withTextsFrom(current);
  if (current.state is ResolvedThreadToolUserInputView &&
      merged.state is! ResolvedThreadToolUserInputView) {
    // 已解决是更强的权威事实：不能因为权威副本暂时只剩结构就退回待回答。
    merged = ThreadToolUserInputView(
      interactionId: merged.interactionId,
      questions: merged.questions,
      state: current.state,
    ).withTextsFrom(current);
  }
  for (var index = 0; index < incoming.questions.length; index++) {
    merged = _preferFullerPart(
      merged,
      index,
      const ThreadUserInputHeaderFieldPartView(),
      incoming.headerText(index),
    );
    merged = _preferFullerPart(
      merged,
      index,
      const ThreadUserInputQuestionFieldPartView(),
      incoming.questionText(index),
    );
    final options = incoming.questions[index].options.length;
    for (var option = 0; option < options; option++) {
      merged = _preferFullerPart(
        merged,
        index,
        ThreadUserInputOptionLabelFieldPartView(option),
        incoming.optionLabel(index, option),
      );
      merged = _preferFullerPart(
        merged,
        index,
        ThreadUserInputOptionDescriptionFieldPartView(option),
        incoming.optionDescription(index, option),
      );
    }
  }
  for (final answer in incoming.answers) {
    final index = merged.questionIndex(answer.questionId);
    if (index == null) continue;
    for (var value = 0; value < answer.answers.length; value++) {
      merged = _preferFullerPart(
        merged,
        index,
        ThreadUserInputAnswerFieldPartView(value),
        answer.answers[value],
      );
    }
  }
  return merged;
}

const Object _incompatibleUserInput = Object();

/// 只在候选正文是当前正文的前缀扩展时替换：不猜测、不回退。
ThreadToolUserInputView _preferFullerPart(
  ThreadToolUserInputView view,
  int questionIndex,
  ThreadUserInputFieldPartView part,
  String candidate,
) {
  final current = switch (part) {
    ThreadUserInputHeaderFieldPartView() => view.headerText(questionIndex),
    ThreadUserInputQuestionFieldPartView() => view.questionText(questionIndex),
    ThreadUserInputOptionLabelFieldPartView(:final optionIndex) =>
      view.optionLabel(questionIndex, optionIndex),
    ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) =>
      view.optionDescription(questionIndex, optionIndex),
    ThreadUserInputAnswerFieldPartView(:final answerIndex) => view.answerText(
      questionIndex,
      answerIndex,
    ),
  };
  if (current == candidate || !candidate.startsWith(current)) return view;
  return view.withText(questionIndex, part, candidate);
}

/// 原始记录正文按段收敛：格式与版本必须一致，正文按前缀规则取更完整者。
List<RawHistoryPayload>? _convergeRawPayloads(
  List<RawHistoryPayload> current,
  List<RawHistoryPayload> incoming,
) {
  final common = current.length <= incoming.length
      ? current.length
      : incoming.length;
  final merged = <RawHistoryPayload>[];
  for (var index = 0; index < common; index++) {
    final a = current[index];
    final b = incoming[index];
    if (a.format != b.format || a.version != b.version) return null;
    final content = _convergeText(a.content, b.content);
    if (content == null) return null;
    merged.add(RawHistoryPayload(b.format, b.version, content));
  }
  final longer = current.length >= incoming.length ? current : incoming;
  merged.addAll(longer.skip(common));
  return merged;
}

class ThreadWorkspace {
  const ThreadWorkspace({
    required this.thread,
    required this.revision,
    required this.interactions,
    required this.runtime,
    this.activeTurn,
    this.latestTurn,
    this.todo,
    this.activity,
    this.storage,
  });

  /// Thread 身份；由 Thread directory 重绑，不作为 mode/role/status 的事实源。
  final StudioThread thread;

  /// 当前状态 revision（snapshot 与实时事件共用）；历史页 watermark 不属于它。
  final int revision;

  final List<PendingInteraction> interactions;
  final ThreadRuntimeView runtime;

  /// 当前执行中的 Turn；Terminal Turn 不留在当前状态里。
  final StudioTurnView? activeTurn;

  /// 最近一次已知 Turn 事实（live turn 通知）。
  final StudioTurnView? latestTurn;

  final TimelineTodoListUpdate? todo;

  /// 后端 typed 当前活动投影；`null` 表示当前没有活动。独立于消息窗口。
  final ThreadActivityView? activity;

  /// 后端 typed 存储状态；`null` 表示没有可报告的存储事实（不是“健康”）。
  final ThreadStorageStateView? storage;

  /// 最近 Turn 事实：当前执行的 Turn 不早于已观测到的终态 Turn。
  StudioTurnView? get lastTurn {
    final observed = latestTurn;
    final active = activeTurn;
    if (active == null) return observed;
    if (observed == null || active.revision >= observed.revision) return active;
    return observed;
  }

  ThreadWorkspace copyWith({
    StudioThread? thread,
    int? revision,
    List<PendingInteraction>? interactions,
    ThreadRuntimeView? runtime,
    Object? activeTurn = _workspaceUnset,
    Object? latestTurn = _workspaceUnset,
    Object? todo = _workspaceUnset,
    Object? activity = _workspaceUnset,
    Object? storage = _workspaceUnset,
  }) {
    return ThreadWorkspace(
      thread: thread ?? this.thread,
      revision: revision ?? this.revision,
      interactions: interactions ?? this.interactions,
      runtime: runtime ?? this.runtime,
      activeTurn: identical(activeTurn, _workspaceUnset)
          ? this.activeTurn
          : activeTurn as StudioTurnView?,
      latestTurn: identical(latestTurn, _workspaceUnset)
          ? this.latestTurn
          : latestTurn as StudioTurnView?,
      todo: identical(todo, _workspaceUnset)
          ? this.todo
          : todo as TimelineTodoListUpdate?,
      activity: identical(activity, _workspaceUnset)
          ? this.activity
          : activity as ThreadActivityView?,
      storage: identical(storage, _workspaceUnset)
          ? this.storage
          : storage as ThreadStorageStateView?,
    );
  }
}

class WorkspaceUiState {
  const WorkspaceUiState({
    this.composer = const ComposerThreadState.idle(),
    this.syncState = AgentWorkspaceSyncState.loading,
    this.loadError,
    this.subscriptionGeneration = 0,
    this.activityDetail = const ThreadActivityDetailState(),
  });

  final ComposerThreadState composer;
  final AgentWorkspaceSyncState syncState;
  final String? loadError;
  final int subscriptionGeneration;

  /// 按活动身份缓存的完整详情读取状态；身份变化即失效。
  final ThreadActivityDetailState activityDetail;

  WorkspaceUiState copyWith({
    ComposerThreadState? composer,
    AgentWorkspaceSyncState? syncState,
    String? loadError,
    int? subscriptionGeneration,
    ThreadActivityDetailState? activityDetail,
  }) {
    return WorkspaceUiState(
      composer: composer ?? this.composer,
      syncState: syncState ?? this.syncState,
      loadError:
          syncState == AgentWorkspaceSyncState.loading ||
              syncState == AgentWorkspaceSyncState.ready
          ? null
          : loadError ?? this.loadError,
      subscriptionGeneration:
          subscriptionGeneration ?? this.subscriptionGeneration,
      activityDetail: activityDetail ?? this.activityDetail,
    );
  }
}

/// 固定活动条展开详情的一次按需读取状态。
///
/// 以活动身份 + 版本为键：同一身份内版本前进即视为需要刷新；身份变化即失效。
/// 读取在途时只保留一个请求（调用方合并），旧身份的迟到结果不得覆盖新身份。
class ThreadActivityDetailState {
  const ThreadActivityDetailState({
    this.identity,
    this.revision = 0,
    this.loading = false,
    this.detail,
    this.error,
  });

  final String? identity;
  final int revision;
  final bool loading;
  final ThreadActivityDetail? detail;
  final String? error;

  bool matches(String identity) => this.identity == identity;

  /// 当前缓存是否已对同一身份的最新版本有效（无需重读）。
  bool covers(String identity, int revision) {
    if (identity.isEmpty || this.identity != identity) return false;
    if (loading) return true;
    return (detail != null || error != null) && this.revision >= revision;
  }

  ThreadActivityDetailState copyWith({
    Object? identity = _workspaceUnset,
    int? revision,
    bool? loading,
    Object? detail = _workspaceUnset,
    Object? error = _workspaceUnset,
  }) {
    return ThreadActivityDetailState(
      identity: identical(identity, _workspaceUnset)
          ? this.identity
          : identity as String?,
      revision: revision ?? this.revision,
      loading: loading ?? this.loading,
      detail: identical(detail, _workspaceUnset)
          ? this.detail
          : detail as ThreadActivityDetail?,
      error: identical(error, _workspaceUnset) ? this.error : error as String?,
    );
  }
}

const _workspaceUnset = Object();

/// 把一个字段变化作用在单段正文上（文本正文 / 工具参数 / 工具输出）。
///
/// `Append` 只在前缀仍有效时到达，直接拼接；`Replace` 是权威替换（含预览升级完整正文）；
/// `Remove` 丢弃本地副本（空串）；`Unchanged` 不动。
String _applyTextChange(String current, ThreadFieldChangeView change) {
  return switch (change) {
    UnchangedThreadFieldChangeView() => current,
    AppendThreadFieldChangeView(:final text) => '$current$text',
    ReplaceThreadFieldChangeView(:final text) => text,
    RemoveThreadFieldChangeView() => '',
  };
}

/// 把字段变化作用在推理分块列表的逻辑 [logicalIndex] 上。
///
/// 逻辑下标 < 已保留窗口时该块本地副本已被省略，丢弃即可；下标超出本地尾部意味着生产者
/// 真的缺块，返回 null 让调用方重同步；删除块只清空该逻辑下标，**不移动**其它块身份。
({List<String> chunks})? _applyChunkChange(
  List<String> chunks,
  int chunkBase,
  int logicalIndex,
  ThreadFieldChangeView change,
) {
  if (change is UnchangedThreadFieldChangeView) return (chunks: chunks);
  final local = logicalIndex - chunkBase;
  if (local < 0) return (chunks: chunks);
  if (local > chunks.length) return null;
  if (local == chunks.length) {
    return switch (change) {
      AppendThreadFieldChangeView(:final text) ||
      ReplaceThreadFieldChangeView(:final text) => (chunks: [...chunks, text]),
      RemoveThreadFieldChangeView() ||
      UnchangedThreadFieldChangeView() => (chunks: chunks),
    };
  }
  final applied = switch (change) {
    AppendThreadFieldChangeView(:final text) => '${chunks[local]}$text',
    ReplaceThreadFieldChangeView(:final text) => text,
    RemoveThreadFieldChangeView() => '',
    UnchangedThreadFieldChangeView() => chunks[local],
  };
  return (chunks: [...chunks.take(local), applied, ...chunks.skip(local + 1)]);
}

/// 把工具输出的字段变化落进工具生命周期：运行/取消沿用原变体；已成功/失败重建输出对象；
/// 尚无输出载体的变体在收到 `Append`/`Replace` 时进入运行态。
ThreadToolLifecycleView _applyToolOutput(
  ThreadToolLifecycleView lifecycle,
  ThreadFieldChangeView change,
) {
  if (change is UnchangedThreadFieldChangeView) return lifecycle;
  switch (lifecycle) {
    case RunningThreadToolView(:final streamedOutput):
      return RunningThreadToolView(_applyTextChange(streamedOutput, change));
    case CancellingThreadToolView(:final streamedOutput):
      return CancellingThreadToolView(_applyTextChange(streamedOutput, change));
    case SucceededThreadToolView(:final completedAt, :final output):
      return SucceededThreadToolView(
        completedAt,
        _withToolResult(output, _applyTextChange(output.result, change)),
      );
    case FailedThreadToolView(:final failedAt, :final failure, :final output):
      return FailedThreadToolView(
        failedAt,
        failure,
        output == null
            ? ThreadToolOutputView(
                result: _applyTextChange('', change),
                attachments: const [],
                outputArtifacts: const [],
              )
            : _withToolResult(output, _applyTextChange(output.result, change)),
      );
    default:
      if (change is RemoveThreadFieldChangeView) return lifecycle;
      return RunningThreadToolView(_applyTextChange('', change));
  }
}

ThreadToolOutputView _withToolResult(
  ThreadToolOutputView output,
  String result,
) {
  return ThreadToolOutputView(
    result: result,
    attachments: output.attachments,
    outputArtifacts: output.outputArtifacts,
    exitCode: output.exitCode,
  );
}

/// 清空/替换工具终态输出里那份已交付的产物预览；流式阶段没有产物数组可清。
ThreadToolLifecycleView _withToolArtifacts(
  ThreadToolLifecycleView lifecycle,
  List<Object?> artifacts,
) {
  switch (lifecycle) {
    case SucceededThreadToolView(:final completedAt, :final output):
      return SucceededThreadToolView(
        completedAt,
        ThreadToolOutputView(
          result: output.result,
          attachments: output.attachments,
          outputArtifacts: artifacts,
          exitCode: output.exitCode,
        ),
      );
    case FailedThreadToolView(:final failedAt, :final failure, :final output):
      final current = output;
      if (current == null) return lifecycle;
      return FailedThreadToolView(
        failedAt,
        failure,
        ThreadToolOutputView(
          result: current.result,
          attachments: current.attachments,
          outputArtifacts: artifacts,
          exitCode: current.exitCode,
        ),
      );
    default:
      return lifecycle;
  }
}
