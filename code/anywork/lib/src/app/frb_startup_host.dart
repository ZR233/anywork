import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';

import '../infrastructure/frb/studio_api.dart';
import 'studio_startup_host.dart';

/// Production startup host. Reads the FRB statics that own native progress.
final class FrbStudioStartupHost implements StudioStartupHost {
  @override
  ValueListenable<StudioStartupPhase> get progress =>
      FrbStudioTransport.startupProgress;

  @override
  ValueListenable<StartupRecoveryReport?> get recovery =>
      FrbStudioTransport.startupRecovery;

  @override
  void dismissRecovery() => FrbStudioTransport.startupRecovery.value = null;

  @override
  void prepareRetry() => FrbStudioTransport.retryInitialization();
}
