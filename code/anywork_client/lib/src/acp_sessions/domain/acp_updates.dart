import 'acp_content.dart';
import 'acp_session_payloads.dart';
import 'acp_values.dart';

final class AcpSessionNotificationView {
  const AcpSessionNotificationView({
    required this.sessionId,
    required this.update,
    this.meta,
  });
  final AcpRemoteSessionId sessionId;
  final AcpSessionUpdateView update;
  final AcpJsonObject? meta;
}

sealed class AcpSessionUpdateView {
  const AcpSessionUpdateView();
}

final class AcpContentChunkView {
  const AcpContentChunkView({required this.content, this.messageId, this.meta});
  final AcpContentBlockView content;
  final AcpMessageId? messageId;
  final AcpJsonObject? meta;
}

final class AcpUserMessageChunkView extends AcpSessionUpdateView {
  const AcpUserMessageChunkView(this.chunk);
  final AcpContentChunkView chunk;
}

final class AcpAgentMessageChunkView extends AcpSessionUpdateView {
  const AcpAgentMessageChunkView(this.chunk);
  final AcpContentChunkView chunk;
}

final class AcpAgentThoughtChunkView extends AcpSessionUpdateView {
  const AcpAgentThoughtChunkView(this.chunk);
  final AcpContentChunkView chunk;
}

final class AcpToolCallSessionUpdateView extends AcpSessionUpdateView {
  const AcpToolCallSessionUpdateView(this.toolCall);
  final AcpToolCallView toolCall;
}

final class AcpToolCallChangedView extends AcpSessionUpdateView {
  const AcpToolCallChangedView(this.toolCall);
  final AcpToolCallUpdateView toolCall;
}

enum AcpPlanPriorityView { high, medium, low }

enum AcpPlanStatusView { pending, inProgress, completed }

final class AcpPlanEntryView {
  const AcpPlanEntryView({
    required this.content,
    required this.priority,
    required this.status,
    this.meta,
  });
  final String content;
  final AcpPlanPriorityView priority;
  final AcpPlanStatusView status;
  final AcpJsonObject? meta;
}

final class AcpPlanView extends AcpSessionUpdateView {
  AcpPlanView({required Iterable<AcpPlanEntryView> entries, this.meta})
    : entries = List.unmodifiable(entries);
  final List<AcpPlanEntryView> entries;
  final AcpJsonObject? meta;
}

sealed class AcpAvailableCommandInputView {
  const AcpAvailableCommandInputView();
}

final class AcpUnstructuredCommandInputView
    extends AcpAvailableCommandInputView {
  const AcpUnstructuredCommandInputView({required this.hint, this.meta});
  final String hint;
  final AcpJsonObject? meta;
}

final class AcpAvailableCommandView {
  const AcpAvailableCommandView({
    required this.name,
    required this.description,
    this.input,
    this.meta,
  });
  final String name;
  final String description;
  final AcpAvailableCommandInputView? input;
  final AcpJsonObject? meta;
}

final class AcpAvailableCommandsUpdateView extends AcpSessionUpdateView {
  AcpAvailableCommandsUpdateView({
    required Iterable<AcpAvailableCommandView> commands,
    this.meta,
  }) : commands = List.unmodifiable(commands);
  final List<AcpAvailableCommandView> commands;
  final AcpJsonObject? meta;
}

final class AcpCurrentModeUpdateView extends AcpSessionUpdateView {
  const AcpCurrentModeUpdateView({required this.currentModeId, this.meta});
  final AcpModeId currentModeId;
  final AcpJsonObject? meta;
}

final class AcpConfigOptionsUpdateView extends AcpSessionUpdateView {
  AcpConfigOptionsUpdateView({
    required Iterable<AcpSessionConfigOptionView> configOptions,
    this.meta,
  }) : configOptions = List.unmodifiable(configOptions);
  final List<AcpSessionConfigOptionView> configOptions;
  final AcpJsonObject? meta;
}

final class AcpSessionInfoUpdateView extends AcpSessionUpdateView {
  const AcpSessionInfoUpdateView({
    this.title = const AcpFieldAbsent(),
    this.updatedAt = const AcpFieldAbsent(),
    this.meta,
  });
  final AcpOptionalField<String> title;
  final AcpOptionalField<String> updatedAt;
  final AcpJsonObject? meta;
}

final class AcpCostView {
  const AcpCostView({required this.amount, required this.currency, this.meta});
  final double amount;
  final String currency;
  final AcpJsonObject? meta;
}

final class AcpUsageUpdateView extends AcpSessionUpdateView {
  const AcpUsageUpdateView({
    required this.used,
    required this.size,
    this.cost,
    this.meta,
  });
  final BigInt used;
  final BigInt size;
  final AcpCostView? cost;
  final AcpJsonObject? meta;
}

enum AcpNoticeSeverityKindView { info, warning, error, other }

final class AcpNoticeSeverityView {
  const AcpNoticeSeverityView.known(this.kind)
    : other = null,
      assert(kind != AcpNoticeSeverityKindView.other);
  const AcpNoticeSeverityView.other(this.other)
    : kind = AcpNoticeSeverityKindView.other;
  final AcpNoticeSeverityKindView kind;
  final String? other;
}

final class AcpNoticeView extends AcpSessionUpdateView {
  const AcpNoticeView({
    required this.severity,
    required this.title,
    this.description,
    this.meta,
  });
  final AcpNoticeSeverityView severity;
  final String title;
  final String? description;
  final AcpJsonObject? meta;
}

enum AcpCompactionStatusKindView {
  inProgress,
  completed,
  failed,
  cancelled,
  other,
}

final class AcpCompactionStatusView {
  const AcpCompactionStatusView.known(this.kind)
    : other = null,
      assert(kind != AcpCompactionStatusKindView.other);
  const AcpCompactionStatusView.other(this.other)
    : kind = AcpCompactionStatusKindView.other;
  final AcpCompactionStatusKindView kind;
  final String? other;
}

final class AcpCompactionUpdateView extends AcpSessionUpdateView {
  AcpCompactionUpdateView({
    required this.compactionId,
    required this.status,
    AcpOptionalField<List<AcpContentBlockView>> summary =
        const AcpFieldAbsent(),
    this.error = const AcpFieldAbsent(),
    this.meta = const AcpFieldAbsent(),
  }) : summary = switch (summary) {
         AcpFieldValue(:final value) => AcpFieldValue(List.unmodifiable(value)),
         _ => summary,
       };
  final AcpCompactionId compactionId;
  final AcpCompactionStatusView status;
  final AcpOptionalField<List<AcpContentBlockView>> summary;
  final AcpOptionalField<String> error;
  final AcpOptionalField<AcpJsonObject> meta;
}

final class AcpCompactionSummaryChunkView extends AcpSessionUpdateView {
  const AcpCompactionSummaryChunkView({
    required this.compactionId,
    required this.content,
    this.meta,
  });
  final AcpCompactionId compactionId;
  final AcpContentBlockView content;
  final AcpJsonObject? meta;
}

enum AcpPermissionOptionKindView {
  allowOnce,
  allowAlways,
  rejectOnce,
  rejectAlways,
}

final class AcpPermissionOptionView {
  const AcpPermissionOptionView({
    required this.optionId,
    required this.name,
    required this.kind,
    this.meta,
  });
  final AcpPermissionOptionId optionId;
  final String name;
  final AcpPermissionOptionKindView kind;
  final AcpJsonObject? meta;
}

final class AcpPermissionRequestView {
  AcpPermissionRequestView({
    required this.sessionId,
    required this.toolCall,
    required Iterable<AcpPermissionOptionView> options,
    this.meta,
  }) : options = List.unmodifiable(options);
  final AcpRemoteSessionId sessionId;
  final AcpToolCallUpdateView toolCall;
  final List<AcpPermissionOptionView> options;
  final AcpJsonObject? meta;
}
