import 'studio_enums.dart';
import 'thread_models.dart';

part 'timeline_todo.dart';

enum TimelineTextChannel { user, parentAgent, commentary, finalAnswer }

class TimelineSkillActivation {
  const TimelineSkillActivation({
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

class TimelineToolPart {
  const TimelineToolPart({
    required this.toolCallId,
    required this.name,
    this.callId,
    this.providerItemId,
    this.arguments = '',
    this.result,
    this.attachments = const [],
    this.outputArtifacts = const [],
    this.exitCode,
    this.timedOut = false,
    this.workingDirectory,
    this.denialReason,
    this.taskId,
    this.userInput,
  });

  final String toolCallId;
  final String name;
  final String? callId;
  final String? providerItemId;
  final String arguments;
  final String? result;
  final List<ThreadAttachmentView> attachments;
  final List<Object?> outputArtifacts;
  final int? exitCode;
  final bool timedOut;
  final String? workingDirectory;
  final String? denialReason;
  final String? taskId;

  /// 这条调用携带的普通问答历史；它让问答回执按工具条目独立成行而不解析工具载荷。
  final ThreadToolUserInputView? userInput;

  TimelineToolPart copyWith({String? arguments, String? result}) {
    return TimelineToolPart(
      toolCallId: toolCallId,
      name: name,
      callId: callId,
      providerItemId: providerItemId,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
      attachments: attachments,
      outputArtifacts: outputArtifacts,
      exitCode: exitCode,
      timedOut: timedOut,
      workingDirectory: workingDirectory,
      denialReason: denialReason,
      taskId: taskId,
      userInput: userInput,
    );
  }
}

class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.groupId,
    required this.type,
    required this.text,
    this.reasoningSummary = const [],
    this.reasoningContent = const [],
    this.threadId = '',
    this.turnId = '',
    this.order = 0,
    this.sequence = 0,
    this.status = 'completed',
    this.revision = 0,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.error,
    this.title,
    this.textChannel,
    this.tool,
    this.skill,
    this.attachments = const [],
    this.contextDisposition = ThreadContextDisposition.active,
  });

  final String id;
  final String groupId;
  final String threadId;
  final String turnId;
  final TimelineEntryType type;
  final int order;
  final int sequence;
  final String text;
  final List<String> reasoningSummary;
  final List<String> reasoningContent;
  final String? title;
  final String status;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? error;
  final TimelineTextChannel? textChannel;
  final TimelineToolPart? tool;
  final TimelineSkillActivation? skill;
  final List<ThreadAttachmentView> attachments;
  final ThreadContextDisposition contextDisposition;
}

/// 把一行 reasoning 文本压成无标记的纯文本摘要；空行与注释占位返回 null。
///
/// 固定活动条与 Timeline 推理摘要共用这一处映射，避免两处各自实现一套去除
/// markdown 标记的规则而出现不一致。
String? plainReasoningSummary(String value) {
  var summary = value.trim();
  if (summary.isEmpty || summary == '<!-- -->') {
    return null;
  }
  if ((summary.startsWith('**') && summary.endsWith('**')) ||
      (summary.startsWith('__') && summary.endsWith('__'))) {
    summary = summary.substring(2, summary.length - 2);
  }
  summary = summary
      .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
      .replaceFirst(RegExp(r'^>\s*'), '')
      .replaceFirst(RegExp(r'^(?:[-+*]|\d+[.)])\s+'), '')
      .replaceAll(RegExp(r'[*_`]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return summary.isEmpty ? null : summary;
}

bool isTerminalTimelineStatus(String status) {
  return const {
    'completed',
    'succeeded',
    'failed',
    'interrupted',
    'cancelled',
    'denied',
    'budgetLimited',
  }.contains(status);
}
