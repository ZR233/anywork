import 'package:anywork_client/studio_client.dart';

import '../../../../domain/models/composer_primary_action.dart';

enum ComposerClipboardFailure { unsupportedImage, readFailed }

/// Immutable input projection. Execution facts and editable content have
/// different owners; only this projection decides the meaning of the main action.
final class ComposerInputState {
  const ComposerInputState({
    required this.composer,
    required this.enabled,
    this.draftText,
    this.inputCapabilities = const [],
    this.targetDiagnostic,
    this.additionalDiagnostics = const [],
    this.execution,
    this.continuation,
    this.continuationAccepted = false,
    this.continuationPending = false,
    this.blocker,
    this.failure,
    this.stopCommand,
    this.queuedStopStartedAtMs,
    this.submissionLocked = false,
    required this.nowMs,
  });

  final ComposerThreadState composer;
  final String? draftText;
  String get text => draftText ?? composer.draft;
  final bool enabled;
  final List<ModelInputCapabilityView> inputCapabilities;
  final ComposerTargetDiagnostic? targetDiagnostic;
  final List<ComposerTargetDiagnostic> additionalDiagnostics;
  final AgentExecutionView? execution;
  final ContinuationView? continuation;
  final bool continuationAccepted;
  final bool continuationPending;
  final ComposerBlocker? blocker;
  final ComposerBlocker? failure;
  final CommandStatus? stopCommand;
  final int? queuedStopStartedAtMs;
  final bool submissionLocked;
  final int nowMs;

  static const stopUnconfirmedAfter = Duration(seconds: 15);

  bool get stopPending =>
      stopCommand != null &&
      stopCommand!.isPending &&
      execution != null &&
      stopCommand!.target.label == execution!.id &&
      !stopCommand!.accepted;

  bool get stopAccepted =>
      stopCommand != null &&
      stopCommand!.accepted &&
      execution != null &&
      stopCommand!.target.label == execution!.id;

  bool get stopAwaitingReceipt =>
      stopPending && !stopAccepted && !(execution?.phase.isStopping ?? false);

  bool get stopUnconfirmed {
    final started = stopCommand?.startedAtMs ?? 0;
    return stopAwaitingReceipt &&
        started != 0 &&
        queuedStopStartedAtMs != started &&
        nowMs - started >= stopUnconfirmedAfter.inMilliseconds;
  }

  ComposerBlocker? get stopFailure {
    final command = stopCommand;
    if (command == null || command.phase != CommandPhase.failed) return null;
    return ComposerFailureBlocker(
      command.error?.reason,
      recoveryIssue: recoveryIssueFromFailure(command.error),
    );
  }

  // Once Client has handed off a submission, its pending work does not lock the
  // next editable revision. Start creation has a separate, single-create lock.
  bool get submissionPending => submissionLocked;

  ComposerPrimaryAction get action => ComposerPrimaryAction.resolve(
    isChild: false,
    execution: execution,
    continuation: continuation,
    hasContent: text.trim().isNotEmpty || composer.attachments.isNotEmpty,
    inputEnabled: enabled,
    submissionPending: submissionPending,
    stopPending: stopPending,
    stopUnconfirmed: stopUnconfirmed,
    stopAccepted: stopAccepted,
    continuationAccepted: continuationAccepted,
    continuationPending: continuationPending,
    blocker: blocker,
  );

  bool get primaryEnabled => action.enabled;

  bool get primaryBusy => action.busy;

  bool get enterSubmits => action.enterSubmits;
}
