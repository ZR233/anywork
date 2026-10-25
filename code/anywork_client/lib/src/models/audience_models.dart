import 'bot_models.dart';
import 'command_receipts.dart';

// Revisions below intentionally stay in their own domains: binding, authorization
// control, summary/delivery and canonical content are not interchangeable clocks.
abstract class _AudienceValue {
  const _AudienceValue();
  List<Object?> get _fields;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AudienceValue &&
          runtimeType == other.runtimeType &&
          _equalFields(_fields, other._fields);
  @override
  int get hashCode => Object.hash(
    runtimeType,
    Object.hashAll(
      _fields.map((value) => value is List ? Object.hashAll(value) : value),
    ),
  );
}

bool _equalFields(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x is List && y is List) {
      if (!_equalFields(x.cast<Object?>(), y.cast<Object?>())) return false;
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

enum BotAudienceCloseReason {
  localClose,
  botDisabled,
  trustRevoked,
  bindingReplaced,
  bindingUnavailable,
  startCancelled,
  startFailed,
}

enum ThreadAudienceUnavailableReason {
  ownershipUnproven,
  invalidOwnership,
  botUnavailable,
  stateUnreadable,
  inconsistentScope,
  bindingUnavailable,
  runtimeClosed,
}

enum BotAudienceItemsUnavailableReason {
  ownerUnavailable,
  ledgerUnreadable,
  canonicalReadInvalidated,
  scopeChanged,
}

enum BotAuthorizationPhase { pendingStart, active, paused, closed }

enum BotCanonicalUnavailableReason {
  missing,
  readInvalidated,
  storageUnavailable,
  invalidMetadata,
  startProofUnavailable,
}

enum BotCardOperationKind { create, send, content, settings }

enum BotFileBlockReason {
  emptyFile,
  platformSizeLimit,
  sourceUnavailable,
  budgetUnavailable,
}

enum BotFileOutcome { pending, delivered, partial, rejected, unknown, stopped }

enum BotItemExclusion {
  nonPublicContent,
  outsideAuthorization,
  excludedStartedTurn,
  legacyOnly,
}

enum BotPublicTextChannel { commentary, finalAnswer }

enum BotTextIntegrity { full, truncated }

enum BotThreadSyncAction { pause, resume, close, enable }

final class BotAudienceStart extends _AudienceValue {
  const BotAudienceStart({required this.commitSequence, this.excludedTurnId});
  final int commitSequence;
  final String? excludedTurnId;
  @override
  List<Object?> get _fields => [commitSequence, excludedTurnId];
}

final class BotAudienceTarget extends _AudienceValue {
  const BotAudienceTarget({
    required this.botId,
    required this.botName,
    required this.chatId,
    this.chatName,
    required this.kind,
  });
  final String botId;
  final String botName;
  final String chatId;
  final String? chatName;
  final BotConversationKind kind;
  @override
  List<Object?> get _fields => [botId, botName, chatId, chatName, kind];
}

final class BotAuthorizationId extends _AudienceValue {
  const BotAuthorizationId({
    required this.botId,
    required this.chatId,
    required this.generation,
  });
  final String botId;
  final String chatId;
  final int generation;
  @override
  List<Object?> get _fields => [botId, chatId, generation];
}

final class BotAuthorizationRef extends _AudienceValue {
  const BotAuthorizationRef({required this.id, required this.revision});
  final BotAuthorizationId id;
  final int revision;
  @override
  List<Object?> get _fields => [id, revision];
}

final class BotClosedAuthorization extends _AudienceValue {
  const BotClosedAuthorization({
    required this.authorization,
    required this.bindingRevision,
    required this.start,
    required this.reason,
    required this.closedAt,
  });
  final BotAuthorizationRef authorization;
  final int bindingRevision;
  final BotClosedStart start;
  final BotAudienceCloseReason reason;
  final int closedAt;
  @override
  List<Object?> get _fields => [
    authorization,
    bindingRevision,
    start,
    reason,
    closedAt,
  ];
}

final class BotDeliverySummary extends _AudienceValue {
  const BotDeliverySummary({
    required this.version,
    required this.pendingItems,
    required this.unknownOperations,
    required this.incompleteItems,
    required this.countsCapped,
  });
  final int version;
  final int pendingItems;
  final int unknownOperations;
  final int incompleteItems;
  final bool countsCapped;
  @override
  List<Object?> get _fields => [
    version,
    pendingItems,
    unknownOperations,
    incompleteItems,
    countsCapped,
  ];
}

final class BotLegacyFinalSummary extends _AudienceValue {
  const BotLegacyFinalSummary({
    required this.unfinishedChains,
    required this.unknownOperations,
    required this.needsAttention,
    required this.countsCapped,
  });
  final int unfinishedChains;
  final int unknownOperations;
  final bool needsAttention;
  final bool countsCapped;
  @override
  List<Object?> get _fields => [
    unfinishedChains,
    unknownOperations,
    needsAttention,
    countsCapped,
  ];
}

final class BotPendingAuthorization extends _AudienceValue {
  const BotPendingAuthorization({
    required this.authorization,
    required this.operationId,
    this.diagnostic,
  });
  final BotAuthorizationRef authorization;
  final String operationId;
  final BotDiagnostic? diagnostic;
  @override
  List<Object?> get _fields => [authorization, operationId, diagnostic];
}

final class BotStartedAuthorization extends _AudienceValue {
  const BotStartedAuthorization({
    required this.authorization,
    required this.bindingRevision,
    required this.start,
  });
  final BotAuthorizationRef authorization;
  final int bindingRevision;
  final BotAudienceStart start;
  @override
  List<Object?> get _fields => [authorization, bindingRevision, start];
}

final class BotSyncCas extends _AudienceValue {
  const BotSyncCas({
    required this.bindingRevision,
    required this.authorizationHead,
  });
  final int bindingRevision;
  final BotAuthorizationHead authorizationHead;
  @override
  List<Object?> get _fields => [bindingRevision, authorizationHead];
}

final class BotThreadAudience extends _AudienceValue {
  const BotThreadAudience({
    required this.target,
    required this.binding,
    this.latestClosed,
    required this.hasOlderClosed,
    required this.delivery,
    required this.legacyFinal,
  });
  final BotAudienceTarget target;
  final BotThreadBindingPosition binding;
  final BotClosedAuthorization? latestClosed;
  final bool hasOlderClosed;
  final BotDeliverySummary delivery;
  final BotLegacyFinalSummary legacyFinal;
  @override
  List<Object?> get _fields => [
    target,
    binding,
    latestClosed,
    hasOlderClosed,
    delivery,
    legacyFinal,
  ];
}

final class BotAudienceItemStatus extends _AudienceValue {
  const BotAudienceItemStatus({
    required this.itemId,
    required this.canonical,
    required this.delivery,
  });
  final String itemId;
  final BotAudienceCanonicalItem canonical;
  final BotItemDelivery delivery;
  @override
  List<Object?> get _fields => [itemId, canonical, delivery];
}

final class BotCardOperationSummary extends _AudienceValue {
  const BotCardOperationSummary({
    required this.operationId,
    required this.contentRevision,
    required this.action,
    required this.result,
  });
  final String operationId;
  final int contentRevision;
  final BotCardOperationKind action;
  final BotPlatformResult result;
  @override
  List<Object?> get _fields => [operationId, contentRevision, action, result];
}

final class BotItemLedgerSummary extends _AudienceValue {
  const BotItemLedgerSummary({
    required this.observedRevision,
    required this.projected,
    required this.accepted,
    required this.platform,
  });
  final int observedRevision;
  final BotItemPresentation projected;
  final BotItemPresentation accepted;
  final BotItemPlatform platform;
  @override
  List<Object?> get _fields => [
    observedRevision,
    projected,
    accepted,
    platform,
  ];
}

final class ChangeBotThreadSyncReply extends _AudienceValue {
  const ChangeBotThreadSyncReply({
    required this.threadId,
    required this.audience,
    required this.state,
    required this.receipt,
  });
  final String threadId;
  final ThreadAudience audience;
  final BotThreadSyncCommandState state;
  final StudioCommandReceipt receipt;
  @override
  List<Object?> get _fields => [threadId, audience, state, receipt];
}

final class ChangeBotThreadSyncRequest extends _AudienceValue {
  const ChangeBotThreadSyncRequest({
    required this.operationId,
    required this.threadId,
    required this.expected,
    required this.action,
  });
  final String operationId;
  final String threadId;
  final BotSyncCas expected;
  final BotThreadSyncAction action;
  @override
  List<Object?> get _fields => [operationId, threadId, expected, action];
}

final class ReadThreadAudienceItemsReply extends _AudienceValue {
  const ReadThreadAudienceItemsReply({
    required this.threadId,
    required this.authorization,
    required this.result,
  });
  final String threadId;
  final BotAuthorizationId authorization;
  final BotAudienceItemsRead result;
  @override
  List<Object?> get _fields => [threadId, authorization, result];
}

final class ReadThreadAudienceItemsRequest extends _AudienceValue {
  ReadThreadAudienceItemsRequest({
    required this.threadId,
    required this.authorization,
    required List<String> itemIds,
  }) : itemIds = List.unmodifiable(itemIds);
  final String threadId;
  final BotAuthorizationId authorization;
  final List<String> itemIds;
  @override
  List<Object?> get _fields => [threadId, authorization, itemIds];
}

final class ReadThreadClosedAuthorizationsReply extends _AudienceValue {
  const ReadThreadClosedAuthorizationsReply({
    required this.threadId,
    required this.result,
  });
  final String threadId;
  final ThreadClosedAuthorizationsRead result;
  @override
  List<Object?> get _fields => [threadId, result];
}

final class ReadThreadClosedAuthorizationsRequest extends _AudienceValue {
  const ReadThreadClosedAuthorizationsRequest({
    required this.threadId,
    this.cursor,
    this.limit,
  });
  final String threadId;
  final String? cursor;
  final int? limit;
  @override
  List<Object?> get _fields => [threadId, cursor, limit];
}

final class ThreadClosedAuthorizationPage extends _AudienceValue {
  ThreadClosedAuthorizationPage({
    required this.target,
    required List<BotClosedAuthorization> authorizations,
    this.nextCursor,
  }) : authorizations = List.unmodifiable(authorizations);
  final BotAudienceTarget target;
  final List<BotClosedAuthorization> authorizations;
  final String? nextCursor;
  @override
  List<Object?> get _fields => [target, authorizations, nextCursor];
}

sealed class BotAuthorizationHead extends _AudienceValue {
  const BotAuthorizationHead();
}

final class BotAuthorizationHeadNone extends BotAuthorizationHead {
  const BotAuthorizationHeadNone();
  @override
  List<Object?> get _fields => [];
}

final class BotAuthorizationHeadPresent extends BotAuthorizationHead {
  const BotAuthorizationHeadPresent({required this.authorization});
  final BotAuthorizationRef authorization;
  @override
  List<Object?> get _fields => [authorization];
}

sealed class BotClosedStart extends _AudienceValue {
  const BotClosedStart();
}

final class BotClosedStartNeverActivated extends BotClosedStart {
  const BotClosedStartNeverActivated();
  @override
  List<Object?> get _fields => [];
}

final class BotClosedStartSaved extends BotClosedStart {
  const BotClosedStartSaved({required this.start});
  final BotAudienceStart start;
  @override
  List<Object?> get _fields => [start];
}

sealed class BotCurrentSync extends _AudienceValue {
  const BotCurrentSync();
}

final class BotCurrentSyncPreparingThread extends BotCurrentSync {
  const BotCurrentSyncPreparingThread();
  @override
  List<Object?> get _fields => [];
}

final class BotCurrentSyncRequiresUpgrade extends BotCurrentSync {
  const BotCurrentSyncRequiresUpgrade();
  @override
  List<Object?> get _fields => [];
}

final class BotCurrentSyncPendingStart extends BotCurrentSync {
  const BotCurrentSyncPendingStart({required this.pending});
  final BotPendingAuthorization pending;
  @override
  List<Object?> get _fields => [pending];
}

final class BotCurrentSyncActive extends BotCurrentSync {
  const BotCurrentSyncActive({required this.authorization});
  final BotStartedAuthorization authorization;
  @override
  List<Object?> get _fields => [authorization];
}

final class BotCurrentSyncPaused extends BotCurrentSync {
  const BotCurrentSyncPaused({required this.authorization});
  final BotStartedAuthorization authorization;
  @override
  List<Object?> get _fields => [authorization];
}

final class BotCurrentSyncClosed extends BotCurrentSync {
  const BotCurrentSyncClosed();
  @override
  List<Object?> get _fields => [];
}

sealed class BotThreadBindingPosition extends _AudienceValue {
  const BotThreadBindingPosition();
}

final class BotThreadBindingPositionCurrent extends BotThreadBindingPosition {
  const BotThreadBindingPositionCurrent({
    required this.cas,
    required this.sync,
  });
  final BotSyncCas cas;
  final BotCurrentSync sync;
  @override
  List<Object?> get _fields => [cas, sync];
}

final class BotThreadBindingPositionReplaced extends BotThreadBindingPosition {
  const BotThreadBindingPositionReplaced({
    required this.lastBindingRevision,
    required this.currentBindingRevision,
  });
  final int lastBindingRevision;
  final int currentBindingRevision;
  @override
  List<Object?> get _fields => [lastBindingRevision, currentBindingRevision];
}

sealed class ThreadAudience extends _AudienceValue {
  const ThreadAudience();
}

final class ThreadAudienceUnbound extends ThreadAudience {
  const ThreadAudienceUnbound();
  @override
  List<Object?> get _fields => [];
}

final class ThreadAudienceUnavailable extends ThreadAudience {
  const ThreadAudienceUnavailable({required this.reason});
  final ThreadAudienceUnavailableReason reason;
  @override
  List<Object?> get _fields => [reason];
}

final class ThreadAudienceKnown extends ThreadAudience {
  const ThreadAudienceKnown({required this.audience});
  final BotThreadAudience audience;
  @override
  List<Object?> get _fields => [audience];
}

sealed class BotAudienceCanonicalItem extends _AudienceValue {
  const BotAudienceCanonicalItem();
}

final class BotAudienceCanonicalItemPresent extends BotAudienceCanonicalItem {
  const BotAudienceCanonicalItemPresent({
    required this.revision,
    required this.saved,
    required this.eligibility,
  });
  final int revision;
  final bool saved;
  final BotItemEligibility eligibility;
  @override
  List<Object?> get _fields => [revision, saved, eligibility];
}

final class BotAudienceCanonicalItemRemoved extends BotAudienceCanonicalItem {
  const BotAudienceCanonicalItemRemoved();
  @override
  List<Object?> get _fields => [];
}

final class BotAudienceCanonicalItemUnavailable
    extends BotAudienceCanonicalItem {
  const BotAudienceCanonicalItemUnavailable({required this.reason});
  final BotCanonicalUnavailableReason reason;
  @override
  List<Object?> get _fields => [reason];
}

sealed class BotAudienceItemsRead extends _AudienceValue {
  const BotAudienceItemsRead();
}

final class BotAudienceItemsReadUnavailable extends BotAudienceItemsRead {
  const BotAudienceItemsReadUnavailable({required this.reason});
  final BotAudienceItemsUnavailableReason reason;
  @override
  List<Object?> get _fields => [reason];
}

final class BotAudienceItemsReadItems extends BotAudienceItemsRead {
  BotAudienceItemsReadItems({
    required this.authorization,
    required this.phase,
    required this.summaryVersion,
    required this.deliveryVersion,
    required List<BotAudienceItemStatus> items,
  }) : items = List.unmodifiable(items);
  final BotAuthorizationRef authorization;
  final BotAuthorizationPhase phase;
  final int summaryVersion;
  final int deliveryVersion;
  final List<BotAudienceItemStatus> items;
  @override
  List<Object?> get _fields => [
    authorization,
    phase,
    summaryVersion,
    deliveryVersion,
    items,
  ];
}

sealed class BotItemDelivery extends _AudienceValue {
  const BotItemDelivery();
}

final class BotItemDeliveryNotProjected extends BotItemDelivery {
  const BotItemDeliveryNotProjected();
  @override
  List<Object?> get _fields => [];
}

final class BotItemDeliveryKnown extends BotItemDelivery {
  const BotItemDeliveryKnown({required this.ledger});
  final BotItemLedgerSummary ledger;
  @override
  List<Object?> get _fields => [ledger];
}

sealed class BotItemEligibility extends _AudienceValue {
  const BotItemEligibility();
}

final class BotItemEligibilityText extends BotItemEligibility {
  const BotItemEligibilityText({required this.channel});
  final BotPublicTextChannel channel;
  @override
  List<Object?> get _fields => [channel];
}

final class BotItemEligibilityPublicArtifact extends BotItemEligibility {
  const BotItemEligibilityPublicArtifact();
  @override
  List<Object?> get _fields => [];
}

final class BotItemEligibilityNotAuthorized extends BotItemEligibility {
  const BotItemEligibilityNotAuthorized({required this.reason});
  final BotItemExclusion reason;
  @override
  List<Object?> get _fields => [reason];
}

sealed class BotItemPlatform extends _AudienceValue {
  const BotItemPlatform();
}

final class BotItemPlatformNone extends BotItemPlatform {
  const BotItemPlatformNone();
  @override
  List<Object?> get _fields => [];
}

final class BotItemPlatformBlocked extends BotItemPlatform {
  const BotItemPlatformBlocked({required this.reason});
  final BotFileBlockReason reason;
  @override
  List<Object?> get _fields => [reason];
}

final class BotItemPlatformCard extends BotItemPlatform {
  const BotItemPlatformCard({required this.latestOperation});
  final BotCardOperationSummary latestOperation;
  @override
  List<Object?> get _fields => [latestOperation];
}

final class BotItemPlatformFile extends BotItemPlatform {
  const BotItemPlatformFile({
    required this.operationId,
    required this.contentRevision,
    required this.upload,
    required this.message,
    required this.outcome,
    this.localStop,
  });
  final String operationId;
  final int contentRevision;
  final BotPlatformResult upload;
  final BotPlatformResult message;
  final BotFileOutcome outcome;
  final BotSendStopReason? localStop;
  @override
  List<Object?> get _fields => [
    operationId,
    contentRevision,
    upload,
    message,
    outcome,
    localStop,
  ];
}

sealed class BotItemPresentation extends _AudienceValue {
  const BotItemPresentation();
}

final class BotItemPresentationNone extends BotItemPresentation {
  const BotItemPresentationNone();
  @override
  List<Object?> get _fields => [];
}

final class BotItemPresentationText extends BotItemPresentation {
  const BotItemPresentationText({
    required this.revision,
    required this.integrity,
    required this.saved,
  });
  final int revision;
  final BotTextIntegrity integrity;
  final bool saved;
  @override
  List<Object?> get _fields => [revision, integrity, saved];
}

final class BotItemPresentationFile extends BotItemPresentation {
  const BotItemPresentationFile({required this.revision});
  final int revision;
  @override
  List<Object?> get _fields => [revision];
}

sealed class BotPlatformResult extends _AudienceValue {
  const BotPlatformResult();
}

final class BotPlatformResultNotStarted extends BotPlatformResult {
  const BotPlatformResultNotStarted();
  @override
  List<Object?> get _fields => [];
}

final class BotPlatformResultInFlight extends BotPlatformResult {
  const BotPlatformResultInFlight();
  @override
  List<Object?> get _fields => [];
}

final class BotPlatformResultAccepted extends BotPlatformResult {
  const BotPlatformResultAccepted();
  @override
  List<Object?> get _fields => [];
}

final class BotPlatformResultRejected extends BotPlatformResult {
  const BotPlatformResultRejected({required this.diagnostic});
  final BotDiagnostic diagnostic;
  @override
  List<Object?> get _fields => [diagnostic];
}

final class BotPlatformResultUnknown extends BotPlatformResult {
  const BotPlatformResultUnknown({required this.diagnostic});
  final BotDiagnostic diagnostic;
  @override
  List<Object?> get _fields => [diagnostic];
}

sealed class BotThreadSyncCommandState extends _AudienceValue {
  const BotThreadSyncCommandState();
}

final class BotThreadSyncCommandStateSettled extends BotThreadSyncCommandState {
  const BotThreadSyncCommandStateSettled();
  @override
  List<Object?> get _fields => [];
}

final class BotThreadSyncCommandStatePendingStart
    extends BotThreadSyncCommandState {
  const BotThreadSyncCommandStatePendingStart({required this.authorization});
  final BotAuthorizationId authorization;
  @override
  List<Object?> get _fields => [authorization];
}

final class BotThreadSyncCommandStateSuperseded
    extends BotThreadSyncCommandState {
  const BotThreadSyncCommandStateSuperseded({required this.authorization});
  final BotAuthorizationId authorization;
  @override
  List<Object?> get _fields => [authorization];
}

sealed class ThreadClosedAuthorizationsRead extends _AudienceValue {
  const ThreadClosedAuthorizationsRead();
}

final class ThreadClosedAuthorizationsReadUnbound
    extends ThreadClosedAuthorizationsRead {
  const ThreadClosedAuthorizationsReadUnbound();
  @override
  List<Object?> get _fields => [];
}

final class ThreadClosedAuthorizationsReadUnavailable
    extends ThreadClosedAuthorizationsRead {
  const ThreadClosedAuthorizationsReadUnavailable({required this.reason});
  final ThreadAudienceUnavailableReason reason;
  @override
  List<Object?> get _fields => [reason];
}

final class ThreadClosedAuthorizationsReadPage
    extends ThreadClosedAuthorizationsRead {
  const ThreadClosedAuthorizationsReadPage({required this.page});
  final ThreadClosedAuthorizationPage page;
  @override
  List<Object?> get _fields => [page];
}

/// Explicit current-or-latest-closed query context, never all historical grants.
extension ThreadAudienceContext on ThreadAudience {
  BotThreadAudience? get known => switch (this) {
    ThreadAudienceKnown(:final audience) => audience,
    ThreadAudienceUnbound() || ThreadAudienceUnavailable() => null,
  };

  BotAuthorizationRef? get queryAuthorization {
    final audience = known;
    if (audience == null) return null;
    final current = switch (audience.binding) {
      BotThreadBindingPositionCurrent(:final cas) =>
        switch (cas.authorizationHead) {
          BotAuthorizationHeadPresent(:final authorization) => authorization,
          BotAuthorizationHeadNone() => null,
        },
      BotThreadBindingPositionReplaced() => null,
    };
    return current ?? audience.latestClosed?.authorization;
  }

  BotSyncCas? get writableCas => switch (known?.binding) {
    BotThreadBindingPositionCurrent(:final cas) => cas,
    BotThreadBindingPositionReplaced() || null => null,
  };
}
