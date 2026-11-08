part of 'chat_models.dart';

/// Mechanical values from pl-protocol/conversation/atom.rs. No UI grouping,
/// lifecycle inference, display ranges or alternate read/ACK owner.
sealed class ChatSourceId {
  const ChatSourceId();
}

final class ForegroundTurnChatSource extends ChatSourceId {
  const ForegroundTurnChatSource({required this.turnId});
  final String turnId;
  @override
  bool operator ==(Object other) =>
      other is ForegroundTurnChatSource && other.turnId == turnId;
  @override
  int get hashCode => Object.hash(ForegroundTurnChatSource, turnId);
}

final class InputChatSource extends ChatSourceId {
  const InputChatSource({required this.inputId});
  final String inputId;
  @override
  bool operator ==(Object other) =>
      other is InputChatSource && other.inputId == inputId;
  @override
  int get hashCode => Object.hash(InputChatSource, inputId);
}

final class InboxMessageChatSource extends ChatSourceId {
  const InboxMessageChatSource({
    required this.sourceId,
    required this.messageId,
  });
  final String sourceId;
  final String messageId;
  @override
  bool operator ==(Object other) =>
      other is InboxMessageChatSource &&
      sourceId == other.sourceId &&
      messageId == other.messageId;
  @override
  int get hashCode => Object.hash(InboxMessageChatSource, sourceId, messageId);
}

final class BackgroundResultChatSource extends ChatSourceId {
  const BackgroundResultChatSource({required this.messageId});
  final String messageId;
  @override
  bool operator ==(Object other) =>
      other is BackgroundResultChatSource && other.messageId == messageId;
  @override
  int get hashCode => Object.hash(BackgroundResultChatSource, messageId);
}

final class OperationChatSource extends ChatSourceId {
  const OperationChatSource({required this.operationId});
  final String operationId;
  @override
  bool operator ==(Object other) =>
      other is OperationChatSource && other.operationId == operationId;
  @override
  int get hashCode => Object.hash(OperationChatSource, operationId);
}

final class ReceiptChatSource extends ChatSourceId {
  const ReceiptChatSource({required this.receiptId});
  final String receiptId;
  @override
  bool operator ==(Object other) =>
      other is ReceiptChatSource && other.receiptId == receiptId;
  @override
  int get hashCode => Object.hash(ReceiptChatSource, receiptId);
}

final class ChatFactPosition implements Comparable<ChatFactPosition> {
  const ChatFactPosition({required this.effectSeq, required this.suborder});
  final int effectSeq;
  final int suborder;
  @override
  int compareTo(ChatFactPosition other) {
    final order = effectSeq.compareTo(other.effectSeq);
    return order == 0 ? suborder.compareTo(other.suborder) : order;
  }
}

enum ChatAtomKind {
  input,
  text,
  reasoning,
  toolCall,
  fileChange,
  skill,
  interaction,
  plan,
  compaction,
  turnReceipt,
  receipt,
  raw,
  agent,
  inference,
  unknown,
}

enum ChatDeliveryKind { foreground, backgroundHandoff, independent }

enum ChatActiveStatus { running, waiting }

enum ChatTerminalOutcome { completed, failed, cancelled, transferred }

sealed class ChatAtomLifecycle {
  const ChatAtomLifecycle();
}

final class ActiveChatAtom extends ChatAtomLifecycle {
  const ActiveChatAtom({required this.started, required this.status});
  final ChatFactPosition? started;
  final ChatActiveStatus status;
}

final class TerminalChatAtom extends ChatAtomLifecycle {
  const TerminalChatAtom({
    required this.started,
    required this.ended,
    required this.outcome,
  });
  final ChatFactPosition? started;
  final ChatFactPosition? ended;
  final ChatTerminalOutcome outcome;
}

final class ChatToolIdentity {
  const ChatToolIdentity({required this.callId, required this.name});
  final String callId;
  final String name;
}

enum ChatContentRole { body, reasoningSummary, toolArguments, toolOutput }

final class ChatAtomContent {
  const ChatAtomContent({required this.role, required this.reference});
  final ChatContentRole role;
  final ContentRef reference;
}

final class ChatAtom {
  ChatAtom({
    required this.id,
    this.completionItemId,
    this.completionSeq,
    required this.source,
    this.sourceState,
    required this.sourceOrder,
    required this.kind,
    required this.delivery,
    required this.lifecycle,
    this.turnId,
    this.attemptId,
    this.tool,
    this.wait,
    this.textChannel,
    this.contentPresent,
    this.startedAt,
    this.finishedAt,
    required List<ChatAtomContent> contents,
    this.payload,
  }) : contents = List.unmodifiable(contents);
  final String id;
  final String? completionItemId;
  final int? completionSeq;
  final ChatSourceId source;

  /// Same-query-cut lifecycle evidence; not part of frozen completion metadata.
  final ChatSourceState? sourceState;
  final int? sourceOrder;
  final ChatAtomKind kind;
  final ChatDeliveryKind delivery;
  final ChatAtomLifecycle lifecycle;
  final String? turnId;
  final String? attemptId;
  final ChatToolIdentity? tool;
  final ThreadWaitPresentationView? wait;
  final ThreadTextChannel? textChannel;

  /// Whether accepted text or attachments exist; `null` means unknown.
  final bool? contentPresent;
  final int? startedAt;
  final int? finishedAt;
  final List<ChatAtomContent> contents;
  final PayloadData? payload;
}

sealed class ChatSourceLifecycle {
  const ChatSourceLifecycle();
}

final class UnknownChatSource extends ChatSourceLifecycle {
  const UnknownChatSource();
}

final class ActiveChatSource extends ChatSourceLifecycle {
  const ActiveChatSource();
}

final class EndedChatSource extends ChatSourceLifecycle {
  const EndedChatSource({required this.outcome});
  final ChatTerminalOutcome outcome;
}

final class ChatSourceState {
  const ChatSourceState({
    required this.source,
    required this.lifecycle,
    required this.started,
    required this.ended,
  });
  final ChatSourceId source;
  final ChatSourceLifecycle lifecycle;
  final ChatFactPosition? started;
  final ChatFactPosition? ended;
}
