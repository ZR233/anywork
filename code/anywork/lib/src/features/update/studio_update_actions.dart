import 'dart:ui' show AppExitType;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/studio_shutdown.dart';
import '../../platform/error_log.dart';
import '../../platform/studio_platform.dart';
import '../../presentation/providers/client_provider.dart';

/// Host actions borrow the Client operation; this controller owns no resource.
final class StudioUpdateActions {
  StudioUpdateActions(this._owner, this._reportShutdownFailure);

  final StudioUpdateClient _owner;
  final void Function(String) _reportShutdownFailure;

  Future<void> check() => _owner.check();

  Future<void> install() async {
    final result = await _owner.install();
    if (result.shutdownFailureMessage case final message?) {
      _reportShutdownFailure(message);
    }
    // The Client consumes the same strong operation's real finishHandoff ACK
    // before releasing it. Host exit then enters the existing single deadline.
    if (result.exitRequired) {
      await ServicesBinding.instance.exitApplication(AppExitType.required);
    }
  }

  Future<void> cancelInstall() => _owner.cancelInstall();

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

/// A Connector supplies host presentation callbacks without starting updates.
StudioUpdateActions readStudioUpdateActions(WidgetRef ref) =>
    StudioUpdateActions(ref.read(anyworkClientProvider).updates, (message) {
      if (ref.context.mounted) {
        ref.read(studioShutdownProgressStateProvider.notifier).fail(message);
      }
    });
