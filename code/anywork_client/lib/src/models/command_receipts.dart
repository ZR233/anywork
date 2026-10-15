import '../commands/mutation_board.dart';
import '../contracts/stamps.dart';
import 'composer_models.dart';
import 'interaction_models.dart';
import 'runtime_models.dart';
import 'studio_state_snapshots.dart';
import 'thread_directory_models.dart';

export '../commands/mutation_board.dart'
    show CommitDisposition, CommitReceipt, EffectPoint;
export '../contracts/stamps.dart' show OperationId, ResourceStamp;

/// An acknowledgement produced at the canonical owner's commit point.
///
/// Revision equality is only an observation barrier. [disposition] describes
/// the actual command result, independently of previously delivered frames.
final class StudioCommandReceipt {
  StudioCommandReceipt({
    required this.operationId,
    required this.disposition,
    required Iterable<ResourceStamp> targets,
    required this.effect,
    required this.effective,
    required this.durable,
    this.requiresIdentityObservation = false,
  }) : targets = List.unmodifiable(targets);

  final OperationId operationId;
  final CommitDisposition disposition;
  final List<ResourceStamp> targets;
  final EffectPoint effect;
  final bool effective;
  final bool durable;
  final bool requiresIdentityObservation;

  CommitReceipt toCommitReceipt() => CommitReceipt(
    operationId: operationId,
    disposition: disposition,
    targets: targets,
    effect: effect,
    effective: effective,
    durable: durable,
    requiresIdentityObservation: requiresIdentityObservation,
  );
}

final class SettingsCommandReply {
  const SettingsCommandReply({required this.snapshot, required this.receipt});
  final SettingsStateSnapshot snapshot;
  final StudioCommandReceipt receipt;
}

final class ThreadModeCommandReply {
  const ThreadModeCommandReply({required this.receipt});
  final StudioCommandReceipt receipt;
}

final class ThreadModelRouteCommandReply {
  const ThreadModelRouteCommandReply({
    required this.runtime,
    required this.settings,
    required this.modeDefaultSaved,
    this.warning,
    required this.receipt,
  });
  final ThreadRuntimeView runtime;
  final SettingsStateSnapshot settings;
  final bool modeDefaultSaved;
  final String? warning;
  final StudioCommandReceipt receipt;
}

final class RenameThreadCommandReply {
  const RenameThreadCommandReply({required this.thread, required this.receipt});
  final StudioThread thread;
  final StudioCommandReceipt receipt;
}

final class ArchiveThreadCommandReply {
  const ArchiveThreadCommandReply({
    required this.result,
    required this.receipt,
  });
  final ArchiveThreadResult result;
  final StudioCommandReceipt receipt;
}

final class InterruptTurnCommandReply {
  const InterruptTurnCommandReply({
    required this.threadId,
    required this.turnId,
    required this.interrupted,
    required this.receipt,
  });
  final String threadId;
  final String turnId;
  final bool interrupted;
  final StudioCommandReceipt receipt;
}

final class InteractionCommandReply {
  const InteractionCommandReply({
    required this.interaction,
    required this.receipt,
  });
  final PendingInteraction interaction;
  final StudioCommandReceipt receipt;
}
