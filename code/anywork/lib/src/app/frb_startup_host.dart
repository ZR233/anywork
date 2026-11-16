import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';

import '../infrastructure/frb/studio_api.dart';
import 'studio_startup_host.dart';

/// Production startup host. Borrows the injected runtime's startup state.
final class FrbStudioStartupHost implements StudioStartupHost {
  FrbStudioStartupHost(this.runtime);

  final FrbRuntimeOwner runtime;

  @override
  ValueListenable<StudioStartupPhase> get progress => runtime.startupProgress;

  @override
  ValueListenable<StartupRecoveryReport?> get recovery =>
      runtime.startupRecovery;

  @override
  void dismissRecovery() => runtime.startupRecovery.value = null;

  @override
  void prepareRetry() => runtime.retryInitialization();
}
