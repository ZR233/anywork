import 'command_receipts.dart';

enum AcpLocalDetectionPhaseView {
  idle,
  checking,
  available,
  missing,
  unsupported,
  failed,
  cancelling,
  cancelled,
}

enum AcpLocalDetectionFailureKindView {
  timeout,
  outputLimit,
  execution,
  cleanup,
}

final class AcpLocalDetectionFailureView {
  const AcpLocalDetectionFailureView({
    required this.kind,
    required this.message,
  });
  final AcpLocalDetectionFailureKindView kind;
  final String message;
}

/// A read-only projection of the Host's single detection result slot.
/// Availability is not authentication proof.
final class AcpLocalDetectionSnapshotView {
  const AcpLocalDetectionSnapshotView({
    required this.revision,
    required this.state,
    this.operationId,
    this.program,
    this.version,
    this.failure,
  });
  const AcpLocalDetectionSnapshotView.idle()
    : revision = 0,
      state = AcpLocalDetectionPhaseView.idle,
      operationId = null,
      program = null,
      version = null,
      failure = null;
  final int revision;
  final String? operationId;
  final AcpLocalDetectionPhaseView state;
  final String? program;
  final String? version;
  final AcpLocalDetectionFailureView? failure;
  bool get isBusy =>
      state == AcpLocalDetectionPhaseView.checking ||
      state == AcpLocalDetectionPhaseView.cancelling;
}

final class AcpLocalDetectionCommandReply {
  const AcpLocalDetectionCommandReply({
    required this.receipt,
    required this.snapshot,
  });
  final StudioCommandReceipt receipt;
  final AcpLocalDetectionSnapshotView snapshot;
}
