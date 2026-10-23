import 'package:anywork_client/updates.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/updates_view_state.dart';

class UpdatesView extends StatelessWidget {
  const UpdatesView({required this.state, required this.errors, required this.canCheck,
    required this.canPrepare, required this.canCancel, required this.onCheck, required this.onPrepare,
    required this.onCancel, required this.onNotes, required this.onRetryRead, super.key});
  final UpdatesViewState state;
  final List<String> errors;
  final bool canCheck;
  final bool canPrepare;
  final bool canCancel;
  final VoidCallback onCheck;
  final VoidCallback onPrepare;
  final VoidCallback onCancel;
  final VoidCallback? onNotes;
  final VoidCallback onRetryRead;

  @override
  Widget build(BuildContext context) {
    final phase = state.source.projection.header?.brief;
    final version = state.currentSummary?.version ?? '—';
    final progress = phase is DownloadingUpdatesBrief && phase.total > 0
      ? (phase.downloaded / phase.total).clamp(0.0, 1.0).toDouble() : null;
    final status = switch (phase) {
      DisabledUpdatesBrief() => context.l10n.settingsStudioUpdateDisabled(state.currentVersion),
      IdleUpdatesBrief() || null => context.l10n.settingsStudioUpdateCurrent(state.currentVersion),
      CheckFailedUpdatesBrief() => context.l10n.settingsStudioUpdateFailed('—'),
      CheckingUpdatesBrief() => context.l10n.settingsStudioUpdateChecking(state.currentVersion),
      UpToDateUpdatesBrief() => context.l10n.settingsStudioUpdateLatest(state.currentVersion),
      AvailableUpdatesBrief() || InstallFailedUpdatesBrief() => context.l10n.settingsStudioUpdateAvailable(state.currentVersion, version),
      DownloadingUpdatesBrief() => context.l10n.settingsStudioUpdateDownloading(version, progress == null ? 0 : (progress * 100).round()),
      VerifyingUpdatesBrief() => context.l10n.settingsStudioUpdateVerifying(version),
      ReadyUpdatesBrief() => context.l10n.settingsStudioUpdateReady(version),
      InstallerLaunchedUpdatesBrief() => context.l10n.settingsStudioUpdateInstallerLaunched(version),
    };
    final preparing = state.actions[UpdateSettingsAction.prepare]?.pending ?? false;
    final cancelling = state.actions[UpdateSettingsAction.cancel]?.pending ?? false;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.system_update_alt, size: 20),
          const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.settingsStudioUpdateTitle, style: Theme.of(context).textTheme.titleSmall),
            Text(status),
            if (!state.controls.enabled && phase is! DisabledUpdatesBrief)
              Text(context.l10n.settingsStudioUpdateDisabled(state.currentVersion)),
            if (preparing || cancelling) Text(cancelling ? context.l10n.settingsStudioUpdateCancelling
              : context.l10n.settingsStudioUpdatePreparing, key: const ValueKey('studio-update-request')),
            for (var index = 0; index < errors.length; index++) SelectableText(context.l10n.settingsStudioUpdateFailed(errors[index]),
              key: index == 0 ? const ValueKey('studio-update-error') : null,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (state.readError != null) TextButton(onPressed: onRetryRead, child: Text(context.l10n.runtimeFatalRetry)),
          ])),
          const SizedBox(width: 12),
          if (state.controls.enabled) Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (state.actions[UpdateSettingsAction.check]?.pending == true || phase is CheckingUpdatesBrief || preparing || cancelling)
              const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            if (onNotes != null) TextButton(key: const ValueKey('studio-update-release-notes'), onPressed: onNotes,
              child: Text(context.l10n.settingsStudioUpdateReleaseNotes)),
            if (phase is AvailableUpdatesBrief || phase is ReadyUpdatesBrief || phase is InstallFailedUpdatesBrief ||
                phase is DownloadingUpdatesBrief || phase is VerifyingUpdatesBrief || preparing)
              FilledButton(key: const ValueKey('studio-update-install'), onPressed: canPrepare ? onPrepare : null,
                child: Text(preparing ? context.l10n.settingsStudioUpdatePreparing : phase is ReadyUpdatesBrief
                  ? context.l10n.settingsStudioUpdateRestart : phase is DownloadingUpdatesBrief || phase is VerifyingUpdatesBrief
                    ? context.l10n.settingsStudioUpdateWhenReady : context.l10n.settingsStudioUpdateInstall))
            else if (phase is! InstallerLaunchedUpdatesBrief && phase is! DisabledUpdatesBrief)
              OutlinedButton(key: const ValueKey('studio-update-check'), onPressed: canCheck ? onCheck : null,
                child: Text(context.l10n.settingsStudioUpdateCheck)),
            if (preparing || cancelling || phase is DownloadingUpdatesBrief || phase is VerifyingUpdatesBrief)
              TextButton(key: const ValueKey('studio-update-cancel'), onPressed: canCancel ? onCancel : null,
                child: Text(context.l10n.settingsCancel)),
          ]),
        ]),
        if (phase is DownloadingUpdatesBrief) ...[const SizedBox(height: 10),
          LinearProgressIndicator(key: const ValueKey('studio-update-progress'), value: progress)],
      ]));
  }
}
