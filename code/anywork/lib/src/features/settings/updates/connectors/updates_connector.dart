import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart' show ExitIntent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_bindings.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../update/update.dart' show releaseNotesViewModelProvider;
import '../../connectors/settings_failure_text.dart';
import '../view_models/updates_view_model.dart';
import '../views/updates_view.dart';

class UpdatesConnector extends ConsumerWidget {
  const UpdatesConnector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(updatesViewModelProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
          return Column(
            children: [
              SelectableText(settingsFailureText(error)),
              TextButton(
                onPressed: () => ref.invalidate(updatesViewModelProvider),
                child: Text(context.l10n.runtimeFatalRetry),
              ),
            ],
          );
        },
        data: (state) {
          final vm = ref.read(updatesViewModelProvider.notifier);
          final sourceError = switch (state.currentValue) {
            CheckFailedUpdatesValue(:final error) ||
            InstallFailedUpdatesValue(:final error) => error,
            _ => null,
          };
          final summary = state.currentSummary;
          return UpdatesView(
            state: state,
            canCheck: vm.canCheck,
            canPrepare: vm.canPrepare,
            canCancel: vm.canCancel,
            onCheck: () => unawaited(vm.check()),
            onPrepare: () => unawaited(_prepare(context, ref, vm)),
            onCancel: () => unawaited(vm.cancelPreparation()),
            onNotes: summary == null || summary.notesUrl.isEmpty
                ? null
                : () => unawaited(
                    ref
                        .read(releaseNotesViewModelProvider(summary).notifier)
                        .open(),
                  ),
            errors: [
              if (sourceError != null)
                '${sourceError.message} [${sourceError.code}]',
              if (state.currentValue == null &&
                  state.source.projection.header?.brief
                      is InstallFailedUpdatesBrief)
                '—',
              for (final error in state.readIssues.values)
                settingsFailureText(error),
              if (state.source.projection.sync.error case final error?)
                settingsFailureText(error),
              for (final action in state.actions.values) ...[
                if (action.error case final error?) settingsFailureText(error),
                if (action.observationError case final error?)
                  settingsFailureText(error),
                if (action.operation?.evidenceError case final error?)
                  settingsFailureText(error),
              ],
            ],
          );
        },
      );

  Future<void> _prepare(
    BuildContext context,
    WidgetRef ref,
    UpdatesViewModel vm,
  ) async {
    final request = await vm.prepare();
    if (request == null || !context.mounted || !vm.takeRestart(request)) return;
    // The one U3 instance owns the first intent/deadline/finalizer and host exit.
    // A preparation result does not install, finalize or terminate by itself.
    try {
      await ref
          .read(applicationExitCoordinatorProvider)
          .requestHostExit(ExitIntent.updateRestart);
    } catch (error) {
      if (context.mounted) _failure(context, error);
    }
  }

  void _failure(BuildContext context, Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.settingsStudioUpdateFailed(
              error is StudioFailure
                  ? settingsFailureText(error)
                  : error.toString(),
            ),
          ),
        ),
      );
}
