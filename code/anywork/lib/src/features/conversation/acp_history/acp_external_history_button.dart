import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/studio_l10n.dart';
import 'acp_external_history_view_model.dart';

/// Entry point for the source conversation's remote ACP session directory.
/// Import this file from the shell; opening the panel is the only list trigger.
class AcpExternalHistoryButton extends ConsumerWidget {
  const AcpExternalHistoryButton({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability = ref.watch(
      acpExternalHistoryAvailabilityProvider(threadId),
    );
    final owner = availability.owner;
    final canList =
        availability.status == AcpExternalHistoryAvailability.available;
    final labels = context.l10n;
    final reason = switch (availability.status) {
      AcpExternalHistoryAvailability.noOwner => labels.acpHistoryNoOwner,
      AcpExternalHistoryAvailability.loading => labels.acpHistoryOwnerLoading,
      AcpExternalHistoryAvailability.unknownCapability =>
        labels.acpHistoryUnknownCapability,
      AcpExternalHistoryAvailability.unsupported =>
        labels.acpHistoryUnsupported,
      AcpExternalHistoryAvailability.notReady => labels.acpHistoryNotReady,
      AcpExternalHistoryAvailability.available => null,
    };
    return Tooltip(
      message: reason ?? labels.acpHistoryOpenPanel,
      child: OutlinedButton.icon(
        onPressed: canList
            ? () => showDialog<void>(
                context: context,
                builder: (_) => _AcpExternalHistoryDialog(
                  threadId: threadId,
                  owner: owner!,
                  labels: labels,
                ),
              )
            : null,
        icon: const Icon(Icons.history),
        label: Text(labels.acpHistoryButton),
      ),
    );
  }
}

final class _AcpExternalHistoryDialog extends ConsumerStatefulWidget {
  const _AcpExternalHistoryDialog({
    required this.threadId,
    required this.owner,
    required this.labels,
  });

  final String threadId;
  final AcpConversationSession owner;
  final AppLocalizations labels;

  @override
  ConsumerState<_AcpExternalHistoryDialog> createState() =>
      _AcpExternalHistoryDialogState();
}

final class _AcpExternalHistoryDialogState
    extends ConsumerState<_AcpExternalHistoryDialog> {
  late final AcpExternalHistoryIdentity identity = (
    threadId: widget.threadId,
    owner: widget.owner,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(acpExternalHistoryViewModelProvider(identity).notifier)
            .refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(acpExternalHistoryViewModelProvider(identity));
    final vm = ref.read(acpExternalHistoryViewModelProvider(identity).notifier);
    final availability = ref.watch(
      acpExternalHistoryAvailabilityProvider(widget.threadId),
    );
    final labels = widget.labels;
    return AlertDialog(
      title: Text(labels.acpHistoryTitle),
      content: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: state.loading || state.loadingMore
                      ? null
                      : vm.refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(labels.acpHistoryRefresh),
                ),
              ),
              if (state.loading) const LinearProgressIndicator(),
              if (state.error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${labels.acpHistoryListFailed}: ${state.error}',
                    ),
                  ),
                ),
              if (state.loading && state.sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(labels.acpHistoryLoading),
                )
              else if (state.sessions.isEmpty && state.error == null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(labels.acpHistoryEmpty),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: state.sessions.length,
                    itemBuilder: (context, index) => _AcpExternalSessionTile(
                      session: state.sessions[index],
                      labels: labels,
                      state: state,
                      canLoad: availability.canLoad,
                      canResume: availability.canResume,
                      onOpen: (resume) =>
                          vm.open(state.sessions[index], resume: resume),
                    ),
                  ),
                ),
              if (state.nextCursor != null)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: state.loading || state.loadingMore
                        ? null
                        : vm.loadMore,
                    child: state.loadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(labels.acpHistoryLoadMore),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(labels.acpHistoryClose),
        ),
      ],
    );
  }
}

final class _AcpExternalSessionTile extends StatelessWidget {
  const _AcpExternalSessionTile({
    required this.session,
    required this.labels,
    required this.state,
    required this.canLoad,
    required this.canResume,
    required this.onOpen,
  });

  final AcpSessionInfoView session;
  final AppLocalizations labels;
  final AcpExternalHistoryState state;
  final bool canLoad;
  final bool canResume;
  final ValueChanged<bool> onOpen;

  @override
  Widget build(BuildContext context) {
    final id = session.sessionId.value;
    final outcome = state.openOutcomes[id];
    final openError = state.openErrors[id];
    return ListTile(
      title: Text(session.title ?? id),
      subtitle: SelectableText(
        '$id\n${labels.acpHistoryCwd}: ${session.cwd}'
        '${session.updatedAt == null ? '' : '\n${labels.acpHistoryUpdated}: ${session.updatedAt}'}'
        '${outcome == null && canLoad ? '\n${labels.acpHistoryLoadNote}' : ''}'
        '${outcome == null && canResume ? '\n${labels.acpHistoryResumeNote}' : ''}',
      ),
      isThreeLine: session.updatedAt != null || canLoad || canResume,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: switch (outcome) {
          AcpExternalOpenOutcome.opening => Text(labels.acpHistoryOpening),
          AcpExternalOpenOutcome.opened => Text(labels.acpHistoryOpened),
          AcpExternalOpenOutcome.unknown => Tooltip(
            message: '$openError',
            child: Text(labels.acpHistoryUnknown),
          ),
          null when !canLoad && !canResume => Text(
            labels.acpHistoryUnavailable,
          ),
          null when canLoad && canResume => PopupMenuButton<bool>(
            tooltip: labels.acpHistoryActions,
            icon: const Icon(Icons.more_vert),
            onSelected: onOpen,
            itemBuilder: (context) => [
              PopupMenuItem(value: false, child: Text(labels.acpHistoryLoad)),
              PopupMenuItem(
                value: true,
                child: Text(
                  '${labels.acpHistoryResume} · ${labels.acpHistoryResumeNote}',
                ),
              ),
            ],
          ),
          null when canLoad => TextButton(
            onPressed: () => onOpen(false),
            child: Text(labels.acpHistoryLoad),
          ),
          null => TextButton(
            onPressed: () => onOpen(true),
            child: Tooltip(
              message: labels.acpHistoryResumeNote,
              child: Text(labels.acpHistoryResume),
            ),
          ),
        },
      ),
    );
  }
}
