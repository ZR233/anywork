import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../state/acp_view_state.dart';

/// Pure modal dialog presenting external ACP peer sessions with explicit
/// "Load history" and "Resume" actions, cursor pagination, and `unknown`
/// open-outcome protection.
class AcpExternalHistoryDialog extends StatelessWidget {
  const AcpExternalHistoryDialog({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onLoadSession,
    required this.onResumeSession,
    required this.onClose,
  });

  final AcpExternalHistoryDialogState state;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onLoadSession;
  final ValueChanged<String> onResumeSession;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final available =
        state.availability == AcpExternalHistoryAvailability.available;
    final canRefresh =
        available && !state.loading && !state.loadingMore && !state.anyOpening;

    return Dialog(
      backgroundColor: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadii.lg),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StudioIconBadge(icon: Icons.history_rounded, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.acpHistoryTitle,
                          style: context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.acpHistorySubtitle,
                          style: context.text.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: l10n.acpHistoryRefresh,
                    onPressed: canRefresh ? onRefresh : null,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(context)),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (state.nextCursor != null)
                    OutlinedButton.icon(
                      onPressed: canRefresh ? onLoadMore : null,
                      icon: state.loadingMore
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded, size: 16),
                      label: Text(l10n.acpHistoryLoadMore),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: onClose,
                    child: Text(l10n.acpHistoryClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final available =
        state.availability == AcpExternalHistoryAvailability.available;
    if (!available) {
      final message = switch (state.availability) {
        AcpExternalHistoryAvailability.loading => l10n.acpHistoryOwnerLoading,
        AcpExternalHistoryAvailability.noOwner => l10n.acpHistoryNoOwner,
        AcpExternalHistoryAvailability.unknownCapability =>
          l10n.acpHistoryUnknownCapability,
        AcpExternalHistoryAvailability.unsupported =>
          l10n.acpHistoryUnsupported,
        AcpExternalHistoryAvailability.notReady => l10n.acpHistoryNotReady,
        AcpExternalHistoryAvailability.available => '',
      };
      return Center(
        child: StudioEmptyState(
          icon: Icons.link_off_rounded,
          title: l10n.acpHistoryTitle,
          message: message,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.loading && state.sessions.isNotEmpty) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
        ],
        if (state.listError case final err?) ...[
          StudioNotice(
            icon: Icons.error_outline_rounded,
            title: l10n.acpHistoryListFailed,
            message: err,
            tone: StudioNoticeTone.danger,
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: state.loading && state.sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.acpHistoryLoading,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : !state.loading &&
                    state.sessions.isEmpty &&
                    state.listError == null
              ? Center(
                  child: StudioEmptyState(
                    icon: Icons.inbox_outlined,
                    title: l10n.acpHistoryEmpty,
                    message: l10n.acpHistorySubtitle,
                  ),
                )
              : ListView.separated(
                  itemCount: state.sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _ExternalSessionCard(
                    row: state.sessions[index],
                    canLoad: state.canLoad,
                    canResume: state.canResume,
                    locked:
                        state.loading || state.loadingMore || state.anyOpening,
                    onLoad: () =>
                        onLoadSession(state.sessions[index].sessionId),
                    onResume: () =>
                        onResumeSession(state.sessions[index].sessionId),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ExternalSessionCard extends StatelessWidget {
  const _ExternalSessionCard({
    required this.row,
    required this.canLoad,
    required this.canResume,
    required this.locked,
    required this.onLoad,
    required this.onResume,
  });

  final AcpExternalSessionRowPresentation row;
  final bool canLoad;
  final bool canResume;
  final bool locked;
  final VoidCallback onLoad;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final hasTitle = row.title != null && row.title!.trim().isNotEmpty;
    final primaryTitle = hasTitle ? row.title! : row.sessionId;
    final rowInteractive = !locked && row.outcome == null;

    return StudioPanel(
      backgroundColor: colors.surfaceContainerLow,
      borderColor: colors.outlineVariant,
      radius: StudioRadii.md,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      primaryTitle,
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasTitle) ...[
                      const SizedBox(height: 3),
                      SelectableText(
                        row.sessionId,
                        style: context.text.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFamily: studioCodeFontFamily,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: SelectableText(
                                '${l10n.acpHistoryCwd}: ${row.cwd}',
                                style: context.text.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFamily: studioCodeFontFamily,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (row.updatedAt case final updated?
                            when updated.trim().isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 13,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${l10n.acpHistoryUpdated}: $updated',
                                style: context.text.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildActions(context, rowInteractive),
            ],
          ),
          if (row.outcome == AcpExternalOpenOutcome.unknown) ...[
            const SizedBox(height: 10),
            StudioNotice(
              icon: Icons.warning_amber_rounded,
              message: row.errorMessage == null
                  ? l10n.acpHistoryUnknown
                  : '${l10n.acpHistoryUnknown}\n${row.errorMessage}',
              tone: StudioNoticeTone.warning,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool rowInteractive) {
    final l10n = context.l10n;
    if (row.outcome == AcpExternalOpenOutcome.opening) {
      return StudioPill(
        icon: Icons.hourglass_top_rounded,
        label: l10n.acpHistoryOpening,
        tone: StudioTone.brand,
      );
    }
    if (row.outcome == AcpExternalOpenOutcome.opened) {
      return StudioPill(
        icon: Icons.check_circle_outline_rounded,
        label: l10n.acpHistoryOpened,
        tone: StudioTone.success,
      );
    }
    if (row.outcome == AcpExternalOpenOutcome.unknown) {
      return const SizedBox.shrink();
    }
    if (!canLoad && !canResume) {
      return Tooltip(
        message: l10n.acpHistoryUnavailable,
        child: StudioPill(label: l10n.acpHistoryUnavailable),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        if (canLoad)
          Tooltip(
            message: l10n.acpHistoryLoadNote,
            child: OutlinedButton(
              key: ValueKey(
                AcpViewKeyValues.externalHistoryLoad(row.sessionId),
              ),
              onPressed: rowInteractive ? onLoad : null,
              child: Text(l10n.acpHistoryLoad),
            ),
          ),
        if (canResume)
          Tooltip(
            message: l10n.acpHistoryResumeNote,
            child: FilledButton.tonal(
              key: ValueKey(
                AcpViewKeyValues.externalHistoryResume(row.sessionId),
              ),
              onPressed: rowInteractive ? onResume : null,
              child: Text(l10n.acpHistoryResume),
            ),
          ),
      ],
    );
  }
}
