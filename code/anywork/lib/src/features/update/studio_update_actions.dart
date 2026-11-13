import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/studio_host_lifecycle.dart';
import '../../platform/error_log.dart';
import '../../platform/external_url_launcher.dart';
import '../../presentation/providers/client_provider.dart';

/// Host actions borrow Client preparation; the process owns its exit coordinator.
abstract interface class StudioUpdateCommands {
  Future<void> check();
  Future<void> install();
  Future<void> cancelInstall();
  Future<void> openReleaseNotes();
}

final studioUpdateActionsProvider = Provider<StudioUpdateCommands>(
  (ref) => StudioUpdateActions(ref.read(anyworkClientProvider).updates),
);

final class StudioUpdateActions implements StudioUpdateCommands {
  StudioUpdateActions(this._owner);

  final StudioUpdateClient _owner;

  @override
  Future<void> check() => _owner.check();

  @override
  Future<void> install() async {
    final result = await _owner.install();
    if (result.readyVersion case final version?) {
      await StudioExitCoordinator.requestExit(
        intent: StudioExitIntent.updateRestart,
        updateVersion: version,
      );
    }
  }

  @override
  Future<void> cancelInstall() => _owner.cancelInstall();

  @override
  Future<void> openReleaseNotes() async {
    final update = _owner.state.update;
    if (update == null) return;
    try {
      await openExternalUrl(update.notesUrl);
    } catch (error, stack) {
      recordDartError(error, stack, stage: 'update-release-notes');
      rethrow;
    }
  }
}
