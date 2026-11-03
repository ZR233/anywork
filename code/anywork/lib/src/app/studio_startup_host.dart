import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';

/// Front-end contract for startup progress and recovery notices.
///
/// Production supplies the FRB-backed host. Demo and UI tests supply an
/// in-memory host. The UI never reads FRB statics.
abstract interface class StudioStartupHost {
  ValueListenable<StudioStartupPhase> get progress;
  ValueListenable<StartupRecoveryReport?> get recovery;
  void dismissRecovery();
  void prepareRetry();
}

/// Ready immediately, with no recovery banner. Demo and tests use this host.
final class ImmediateStudioStartupHost implements StudioStartupHost {
  ImmediateStudioStartupHost({
    StudioStartupPhase phase = StudioStartupPhase.ready,
    StartupRecoveryReport? recovery,
  }) : progress = ValueNotifier(phase),
       recovery = ValueNotifier(recovery);

  @override
  final ValueNotifier<StudioStartupPhase> progress;

  @override
  final ValueNotifier<StartupRecoveryReport?> recovery;

  @override
  void dismissRecovery() => recovery.value = null;

  @override
  void prepareRetry() {}
}
