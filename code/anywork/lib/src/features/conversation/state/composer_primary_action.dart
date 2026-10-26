import 'package:anywork_client/conversation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'composer_primary_action.freezed.dart';

enum ComposerPrimaryActionKind {
  readOnly,
  stop,
  sendAndContinue,
  stopping,
  continueConversation,
  continuing,
  send,
}

/// Prerequisites and the previous rejection are different facts. A rejection
/// stays visible but never permanently disables an explicit new attempt.
@Freezed(toStringOverride: false)
sealed class ComposerBlocker with _$ComposerBlocker {
  const ComposerBlocker._();
  const factory ComposerBlocker.storage() = ComposerStorageBlocker;
  const factory ComposerBlocker.model() = ComposerModelBlocker;
  const factory ComposerBlocker.workspace() = ComposerWorkspaceBlocker;
  const factory ComposerBlocker.failure(StudioFailureReason? reason) =
      ComposerFailureBlocker;

  bool get blocksSubmission => this is! ComposerFailureBlocker;
}

/// Pure canonical matrix. No ticket, Session, click memory or inferred Turn.
@Freezed(toStringOverride: false)
abstract class ComposerPrimaryAction with _$ComposerPrimaryAction {
  const ComposerPrimaryAction._();
  const factory ComposerPrimaryAction({
    required ComposerPrimaryActionKind kind,
    required bool enabled,
    ComposerBlocker? blocker,
  }) = _ComposerPrimaryAction;

  static ComposerPrimaryAction resolve({
    required bool isChild,
    required AgentExecution? execution,
    required ContinuationView? continuation,
    required bool hasContent,
    required bool submissionPending,
    required bool stopAccepted,
    required bool continuationAccepted,
    bool stopPending = false,
    bool continuationPending = false,
    ComposerBlocker? blocker,
  }) {
    if (isChild) {
      return const ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.readOnly,
        enabled: false,
      );
    }
    final blocked = blocker?.blocksSubmission ?? false;
    final requestPending = submissionPending || continuationPending || stopPending;
    final submitEnabled = !requestPending && !blocked && hasContent;
    if (stopAccepted || execution?.phase == AgentExecutionPhase.stopping) {
      return ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.stopping,
        enabled: false,
        blocker: blocker,
      );
    }
    if (execution != null) {
      return ComposerPrimaryAction(
        kind: hasContent
            ? ComposerPrimaryActionKind.sendAndContinue
            : ComposerPrimaryActionKind.stop,
        // Storage, route and workspace failures cannot block this stop target.
        enabled: hasContent ? submitEnabled : !stopPending,
        blocker: blocker,
      );
    }
    if (continuationAccepted || continuation?.claimed == true) {
      return ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.continuing,
        enabled: false,
        blocker: blocker,
      );
    }
    if (continuation != null) {
      return ComposerPrimaryAction(
        kind: hasContent
            ? ComposerPrimaryActionKind.sendAndContinue
            : ComposerPrimaryActionKind.continueConversation,
        enabled: !requestPending && !blocked,
        blocker: blocker,
      );
    }
    return ComposerPrimaryAction(
      kind: ComposerPrimaryActionKind.send,
      enabled: submitEnabled,
      blocker: blocker,
    );
  }

  bool get enterSubmits =>
      enabled &&
      (kind == ComposerPrimaryActionKind.send ||
          kind == ComposerPrimaryActionKind.sendAndContinue);
}
