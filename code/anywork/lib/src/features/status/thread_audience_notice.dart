import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import '../../app/app_graph.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/thread_audience_provider.dart';

/// A persistent, narrow warning strip rather than a second settings surface.
/// Target names ellipsize independently; group audience and sync warning wrap.
class ThreadAudienceNotice extends ConsumerWidget {
  const ThreadAudienceNotice({
    required this.threadId,
    this.controls = false,
    super.key,
  });
  final String threadId;
  final bool controls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audience = ref.watch(threadAudienceProvider(threadId));
    final progress = ref.watch(threadSyncProgressProvider(threadId));
    if (audience is ThreadAudienceUnbound) return const SizedBox.shrink();
    final l = context.l10n;
    final known = audience.known;
    final target = known?.target;
    final binding = known?.binding;
    final sync = binding is BotThreadBindingPositionCurrent
        ? binding.sync
        : null;
    final status = switch (audience) {
      ThreadAudienceUnavailable() => l.audienceUnavailable,
      ThreadAudienceUnbound() => '',
      ThreadAudienceKnown() => switch (binding) {
        BotThreadBindingPositionReplaced() => l.audienceReplaced,
        BotThreadBindingPositionCurrent() => switch (sync!) {
          BotCurrentSyncPreparingThread() => l.audiencePreparing,
          BotCurrentSyncRequiresUpgrade() => l.audienceUpgrade,
          BotCurrentSyncPendingStart() => l.audiencePendingStart,
          BotCurrentSyncActive() => l.audienceActive,
          BotCurrentSyncPaused() => l.audiencePaused,
          BotCurrentSyncClosed() => l.audienceClosed,
        },
        null => l.audienceUnavailable,
      },
    };
    final delivery = known?.delivery;
    final counts = delivery == null
        ? ''
        : '${l.audiencePendingItems}: ${delivery.pendingItems} · '
              '${l.audienceUnknownOperations}: ${delivery.unknownOperations} · '
              '${l.audienceIncompleteItems}: ${delivery.incompleteItems}';
    final actions = switch (sync) {
      BotCurrentSyncActive() => [
        BotThreadSyncAction.pause,
        BotThreadSyncAction.close,
      ],
      BotCurrentSyncPaused() => [
        BotThreadSyncAction.resume,
        BotThreadSyncAction.close,
      ],
      BotCurrentSyncPendingStart() => [BotThreadSyncAction.close],
      BotCurrentSyncClosed() => [BotThreadSyncAction.enable],
      BotCurrentSyncPreparingThread() ||
      BotCurrentSyncRequiresUpgrade() ||
      null => const <BotThreadSyncAction>[],
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(
            width: 3,
            color: sync is BotCurrentSyncActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.tertiary,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (target != null)
              Row(
                children: [
                  Icon(
                    target.kind == BotConversationKind.group
                        ? Icons.groups_outlined
                        : Icons.chat_outlined,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    target.kind == BotConversationKind.group
                        ? l.audienceGroup
                        : l.audienceDirect,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message:
                          '${target.botName} (${target.botId}) → ${target.chatName ?? target.chatId} (${target.chatId})',
                      child: Text(
                        '${target.botName} (${target.botId}) → ${target.chatName ?? target.chatId} (${target.chatId})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            Text(status, style: Theme.of(context).textTheme.labelMedium),
            if (audience case ThreadAudienceUnavailable(:final reason))
              Text(reason.name, style: Theme.of(context).textTheme.labelSmall),
            if (counts.isNotEmpty)
              Text(counts, style: Theme.of(context).textTheme.labelSmall),
            if (audience.queryAuthorization case final authorization?)
              Text(
                '${l.audienceCurrentContext}: ${authorization.id.generation}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (delivery?.countsCapped == true ||
                known?.legacyFinal.countsCapped == true)
              Text(
                l.audienceCountsCapped,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (known != null &&
                (known.legacyFinal.needsAttention ||
                    known.legacyFinal.unfinishedChains > 0 ||
                    known.legacyFinal.unknownOperations > 0))
              Text(
                '${l.audienceLegacyAttention}: ${known.legacyFinal.unfinishedChains} / ${known.legacyFinal.unknownOperations}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (controls && target != null)
              Text(
                l.audiencePrivateInput,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (controls && progress != null) ...[
              if (progress.unknown)
                Text(l.audienceOperationUnknown)
              else if (progress.superseded)
                Text(l.audienceOperationSuperseded)
              else if (progress.inFlight ||
                  progress.operation.state.value.isPending ||
                  progress.reply?.state
                          is BotThreadSyncCommandStatePendingStart &&
                      !progress.operation.state.value.effective)
                Text(l.audienceOperationPending),
              if (progress.error != null)
                Text(
                  progress.error.toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
            if (controls && known != null)
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final action in actions)
                    TextButton(
                      key: ValueKey('audience-${action.name}:$threadId'),
                      onPressed:
                          _samePending(progress, audience.writableCas, action)
                          ? null
                          : () => unawaited(
                              _perform(
                                context,
                                () => ref
                                    .read(anyworkClientProvider)
                                    .botThreadSync
                                    .change(threadId, action),
                              ),
                            ),
                      child: Text(switch (action) {
                        BotThreadSyncAction.pause => l.audiencePause,
                        BotThreadSyncAction.resume => l.audienceResume,
                        BotThreadSyncAction.close => l.audienceClose,
                        BotThreadSyncAction.enable => l.audienceEnable,
                      }),
                    ),
                  if (progress?.unknown == true)
                    TextButton(
                      onPressed: progress!.inFlight
                          ? null
                          : () => unawaited(
                              _perform(
                                context,
                                () => ref
                                    .read(anyworkClientProvider)
                                    .botThreadSync
                                    .reconcile(threadId),
                              ),
                            ),
                      child: Text(l.audienceReconcile),
                    ),
                  if (sync is BotCurrentSyncRequiresUpgrade)
                    TextButton(
                      onPressed: () => unawaited(_upgrade(context, ref, known)),
                      child: Text(l.audienceNewThread),
                    ),
                  TextButton(
                    onPressed: () => _showHistory(context, ref),
                    child: Text(l.audienceHistory),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool _samePending(
    BotThreadSyncProgress? progress,
    BotSyncCas? cas,
    BotThreadSyncAction action,
  ) =>
      progress != null &&
      progress.request.expected == cas &&
      progress.request.action == action &&
      (progress.inFlight ||
          progress.unknown ||
          progress.operation.state.value.isPending);

  Future<void> _perform(
    BuildContext context,
    Future<Object?> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _upgrade(
    BuildContext context,
    WidgetRef ref,
    BotThreadAudience known,
  ) async {
    final client = ref.read(anyworkClientProvider);
    final cas = (known.binding as BotThreadBindingPositionCurrent).cas;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.audienceNewThread),
        content: Text(context.l10n.audienceUpgrade),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.l10n.settingsBotsDismiss),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.l10n.audienceNewThread),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _perform(context, () async {
      // Config is read by the existing typed bot command, not inferred from the
      // Thread id or setBotEnabled. The old frozen Thread is never rewritten.
      final reply = await client.botThreadSync.createUpgradedConversation(
        threadId,
        expected: cas,
      );
      final newId = reply.binding.threadId;
      if (newId != null &&
          newId.isNotEmpty &&
          client.selection.state.selectedThreadId == threadId) {
        await client.directoryCommands.selectThread(newId);
      }
      return reply;
    });
  }

  void _showHistory(BuildContext context, WidgetRef ref) {
    final history = ref
        .read(anyworkClientProvider)
        .audienceQueries
        .openHistory(threadId);
    final lease = ref.read(appGraphProvider).timeline.lease(threadId);
    showDialog<void>(
      context: context,
      builder: (_) => _AuthorizationHistoryDialog(
        history: history,
        onSelected: (authorization) {
          if (lease != null && !lease.isRetired) {
            lease.audience?.selectAuthorization(authorization);
          }
        },
      ),
    ).whenComplete(history.retire);
  }
}

class _AuthorizationHistoryDialog extends StatefulWidget {
  const _AuthorizationHistoryDialog({
    required this.history,
    required this.onSelected,
  });
  final ThreadClosedAuthorizationsHistory history;
  final ValueChanged<BotAuthorizationRef?> onSelected;
  @override
  State<_AuthorizationHistoryDialog> createState() =>
      _AuthorizationHistoryDialogState();
}

class _AuthorizationHistoryDialogState
    extends State<_AuthorizationHistoryDialog> {
  final List<BotClosedAuthorization> _entries = [];
  bool _loading = false;
  bool _more = true;
  Object? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_next());
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.history.next();
      if (!mounted) return;
      setState(() {
        switch (result) {
          case ThreadClosedAuthorizationsReadPage(:final page):
            _entries.addAll(page.authorizations);
            _more = page.nextCursor != null;
          case ThreadClosedAuthorizationsReadUnavailable(:final reason):
            _error = reason;
            _more = false;
          case ThreadClosedAuthorizationsReadUnbound():
            _more = false;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.audienceHistory),
    content: SizedBox(
      width: 560,
      height: 360,
      child: ListView(
        children: [
          for (final entry in _entries)
            ListTile(
              dense: true,
              onTap: () {
                widget.onSelected(entry.authorization);
                Navigator.pop(context);
              },
              title: Text(
                '${entry.authorization.id.botId} / ${entry.authorization.id.chatId} · ${entry.authorization.id.generation}',
              ),
              subtitle: Text(
                '${entry.reason.name} · ${entry.closedAt} · revision ${entry.authorization.revision}',
              ),
            ),
          if (_error != null)
            Text('${context.l10n.audienceReadUnavailable}: $_error'),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _more)
            TextButton(
              onPressed: _next,
              child: Text(context.l10n.audienceMoreHistory),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          widget.onSelected(null);
          Navigator.pop(context);
        },
        child: Text(context.l10n.audienceCurrentContext),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.modelDetailClose),
      ),
    ],
  );
}
