import 'package:material_ui/material_ui.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/studio_update_view_state.dart';

class StudioUpdateSettingsView extends StatelessWidget {
  const StudioUpdateSettingsView({
    super.key,
    required this.state,
    required this.onCheck,
    required this.onInstall,
    required this.onCancel,
    required this.onOpenReleaseNotes,
  });

  final StudioUpdateViewState state;
  final VoidCallback onCheck;
  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = _action(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.system_update_alt,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settingsStudioUpdateTitle,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusText(context),
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (state.readyVersion != null &&
                        state.statusKind != StudioUpdateStatusKind.ready &&
                        state.statusKind !=
                            StudioUpdateStatusKind.installerLaunched) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.settingsStudioUpdateReady(
                          state.readyVersion!,
                        ),
                        style: context.text.bodySmall,
                      ),
                    ],
                    if (state.requestKind ==
                            StudioUpdateRequestKind.preparing ||
                        state.requestKind ==
                            StudioUpdateRequestKind.cancelling ||
                        state.requestKind ==
                            StudioUpdateRequestKind.cancelled) ...[
                      const SizedBox(height: 4),
                      Text(
                        switch (state.requestKind) {
                          StudioUpdateRequestKind.cancelling =>
                            context.l10n.settingsStudioUpdateCancelling,
                          StudioUpdateRequestKind.cancelled =>
                            context.l10n.settingsStudioUpdateCancelled,
                          _ => context.l10n.settingsStudioUpdatePreparing,
                        },
                        key: const ValueKey('studio-update-request'),
                        style: context.text.bodySmall,
                      ),
                    ],
                    if (state.errorKind != StudioUpdateErrorKind.none) ...[
                      const SizedBox(height: 4),
                      Text(
                        state.errorKind == StudioUpdateErrorKind.cancelled
                            ? context.l10n.settingsStudioUpdateCancelled
                            : context.l10n.settingsStudioUpdateFailed(
                                state.errorMessage,
                              ),
                        key: const ValueKey('studio-update-error'),
                        style: context.text.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    if (state.requestErrorMessage case final error?) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.settingsStudioUpdateFailed(error),
                        style: context.text.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 16), action],
            ],
          ),
          if (state.showProgress) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              key: const ValueKey('studio-update-progress'),
              value: state.progress,
            ),
          ],
        ],
      ),
    );
  }

  Widget? _action(BuildContext context) {
    switch (state.actionLayout) {
      case StudioUpdateSettingsActionLayout.none:
        return null;
      case StudioUpdateSettingsActionLayout.checking:
        return const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case StudioUpdateSettingsActionLayout.progress:
        return Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            FilledButton(
              key: const ValueKey('studio-update-install'),
              onPressed: state.primaryEnabled ? onInstall : null,
              child: Text(
                state.primaryEnabled
                    ? context.l10n.settingsStudioUpdateWhenReady
                    : context.l10n.settingsStudioUpdatePreparing,
              ),
            ),
            TextButton(
              key: const ValueKey('studio-update-cancel'),
              onPressed: state.cancelEnabled ? onCancel : null,
              child: Text(context.l10n.settingsCancel),
            ),
          ],
        );
      case StudioUpdateSettingsActionLayout.updateAvailable:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (state.showReleaseNotes)
              TextButton(
                key: const ValueKey('studio-update-release-notes'),
                onPressed: onOpenReleaseNotes,
                child: Text(context.l10n.settingsStudioUpdateReleaseNotes),
              ),
            FilledButton(
              key: const ValueKey('studio-update-install'),
              onPressed: state.primaryEnabled ? onInstall : null,
              child: Text(
                state.primaryAction ==
                        StudioUpdatePrimaryAction.installAndRestart
                    ? context.l10n.settingsStudioUpdateRestart
                    : context.l10n.settingsStudioUpdateInstall,
              ),
            ),
            if (state.showCancel)
              TextButton(
                key: const ValueKey('studio-update-cancel'),
                onPressed: state.cancelEnabled ? onCancel : null,
                child: Text(context.l10n.settingsCancel),
              ),
          ],
        );
      case StudioUpdateSettingsActionLayout.check:
        return OutlinedButton(
          key: const ValueKey('studio-update-check'),
          onPressed: onCheck,
          child: Text(context.l10n.settingsStudioUpdateCheck),
        );
    }
  }

  String _statusText(BuildContext context) {
    final current = state.currentVersion;
    final available = state.availableVersion ?? '';
    return switch (state.statusKind) {
      StudioUpdateStatusKind.disabled =>
        context.l10n.settingsStudioUpdateDisabled(current),
      StudioUpdateStatusKind.idle => context.l10n.settingsStudioUpdateCurrent(
        current,
      ),
      StudioUpdateStatusKind.checking =>
        context.l10n.settingsStudioUpdateChecking(current),
      StudioUpdateStatusKind.upToDate =>
        context.l10n.settingsStudioUpdateLatest(current),
      StudioUpdateStatusKind.available ||
      StudioUpdateStatusKind.installFailed =>
        context.l10n.settingsStudioUpdateAvailable(current, available),
      StudioUpdateStatusKind.downloading =>
        context.l10n.settingsStudioUpdateDownloading(
          available,
          state.progressPercent,
        ),
      StudioUpdateStatusKind.verifying =>
        context.l10n.settingsStudioUpdateVerifying(available),
      StudioUpdateStatusKind.ready => context.l10n.settingsStudioUpdateReady(
        state.readyVersion ?? available,
      ),
      StudioUpdateStatusKind.installerLaunched =>
        context.l10n.settingsStudioUpdateInstallerLaunched(available),
      StudioUpdateStatusKind.checkFailed =>
        context.l10n.settingsStudioUpdateCurrent(current),
    };
  }
}
