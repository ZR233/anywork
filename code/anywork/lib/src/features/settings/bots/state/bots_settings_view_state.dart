import 'package:anywork_client/bots.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'bots_settings_view_state.freezed.dart';

typedef BotsChatTarget = ({String botId, String chatId});

/// A local presentation of a frozen send, not another send ledger.
final class BotsMessageAction {
  const BotsMessageAction({required this.text, required this.action});

  final String text;
  final SettingsAction action;
}

/// Confirmation applies only to the displayed target, draft and attempt.
final class BotsSendRetry {
  const BotsSendRetry({
    required this.target,
    required this.text,
    required this.draftRevision,
    required this.intent,
    required this.operationId,
  });

  final BotsChatTarget target;
  final String text;
  final int draftRevision;
  final int? intent;
  final OperationId? operationId;
}

bool isCurrentBotsSnapshot(BotsState source) {
  final snapshot = source.snapshot;
  final projection = source.projection;
  final stamp = projection.stamp;
  return snapshot != null &&
      stamp != null &&
      projection.sync.phase == ResourceSyncPhase.ready &&
      projection.header?.source.brief is ReadyObservedBrief &&
      snapshot.origin == stamp.origin &&
      snapshot.reference.resourceKey == 'bots' &&
      snapshot.reference.ownerEpoch == stamp.ownerEpoch &&
      snapshot.reference.revision == projection.header?.botsRevision &&
      snapshot.value.revision == projection.header?.botsRevision;
}

/// Repository values retain their original provenance. Only selection, read
/// demand and operation presentation are owned by the settings page.
@Freezed(toStringOverride: false)
final class BotsSettingsViewState with _$BotsSettingsViewState {
  BotsSettingsViewState({
    required this.source,
    required this.messages,
    required this.sends,
    this.selectedBotId,
    this.chatId = '',
    this.messageDraft = '',
    this.draftRevision = 0,
    this.visible = false,
    this.synchronizing = false,
    this.readingStatus = false,
    this.readingMessages = false,
    this.syncIssue,
    this.statusIssue,
    this.observationIssue,
    this.messageIssue,
    this.draftIssue,
    this.registrationAction,
    Map<String, SettingsAction> botActions = const {},
    Map<BotsChatTarget, BotsMessageAction> messageActions = const {},
  }) : botActions = Map.unmodifiable(botActions),
       messageActions = Map.unmodifiable(messageActions);

  final BotsState source;
  final BotMessagesState messages;
  final BotSendsState sends;
  final String? selectedBotId;
  final String chatId;
  final String messageDraft;
  final int draftRevision;
  final bool visible;
  final bool synchronizing;
  final bool readingStatus;
  final bool readingMessages;
  final StudioFailure? syncIssue;
  final StudioFailure? statusIssue;
  final StudioFailure? observationIssue;
  final StudioFailure? messageIssue;
  final StudioFailure? draftIssue;
  final SettingsAction? registrationAction;
  final Map<String, SettingsAction> botActions;
  final Map<BotsChatTarget, BotsMessageAction> messageActions;

  bool get snapshotCurrent => isCurrentBotsSnapshot(source);
  bool get editable => visible && observationIssue == null && snapshotCurrent;
  List<BotSnapshot>? get bots => source.snapshot?.value.bots;

  /// The canonical registration attempt stays page-owned: opening or closing
  /// the setup editor never hides an attempt that already exists.
  BotRegistrationAttempt? get registration =>
      source.snapshot?.value.registration;
  bool get registrationPending => registrationAction?.pending ?? false;
  bool get registrationBlocked =>
      registrationAction?.preventsResubmission ?? false;
  bool get canStartRegistration => editable && !registrationBlocked;

  /// Overview rule from the first-run flow: an in-flight attempt replaces the
  /// setup form instead of being hidden behind it.
  bool get registrationActive => switch (registration?.status) {
    BotRegistrationPreparing() ||
    BotRegistrationWaiting() ||
    BotRegistrationSlowDown() ||
    BotRegistrationCommitting() => true,
    _ => false,
  };
  List<BotPendingCredentialOperation> get pendingCredentialOperations =>
      source.snapshot?.value.pendingCredentialOperations ?? const [];

  BotSnapshot? get selectedBot =>
      bots?.where((bot) => bot.id == selectedBotId).firstOrNull;
  BotsChatTarget? get chatTarget => selectedBot == null || chatId.trim().isEmpty
      ? null
      : (botId: selectedBot!.id, chatId: chatId.trim());

  bool get messagesMatch =>
      chatTarget != null &&
      messages.query?.botId == chatTarget!.botId &&
      messages.query?.chatId == chatTarget!.chatId;
  BotMessagePage? get messagePage {
    final page = messages.messagePage;
    return messagesMatch &&
            page?.botId == chatTarget?.botId &&
            page?.chatId == chatTarget?.chatId
        ? page
        : null;
  }

  bool get messagesPending =>
      readingMessages || messagesMatch && messages.loading;
  BotsMessageAction? get submission => messageActions[chatTarget];
  BotSendResult? get latestSend => chatTarget == null
      ? null
      : sends.latestFor(chatTarget!.botId, chatTarget!.chatId);

  /// A receipt for an older attempt must not label the new attempt successful.
  BotSendResult? get submissionResult {
    final operation = submission?.action.operation?.id;
    return submission == null ? latestSend : sends.byOperationId[operation];
  }

  bool get sendUncertain =>
      submission?.action.uncertain == true ||
      submissionResult?.status == BotSendStatus.unknown ||
      submissionResult?.status == BotSendStatus.partial;
  bool get sendPending => submission?.action.pending == true;
  bool get canSend =>
      editable &&
      chatTarget != null &&
      messageDraft.trim().isNotEmpty &&
      draftIssue == null &&
      !sendPending &&
      !sendUncertain &&
      submission?.action.outcome != SettingsActionOutcome.synchronizationFailed;
  BotsSendRetry? get sendRetry =>
      editable &&
          chatTarget != null &&
          messageDraft.trim().isNotEmpty &&
          draftIssue == null &&
          !sendPending &&
          sendUncertain
      ? BotsSendRetry(
          target: chatTarget!,
          text: messageDraft,
          draftRevision: draftRevision,
          intent: submission?.action.intent,
          operationId:
              submission?.action.operation?.id ?? latestSend?.operationId,
        )
      : null;
}
