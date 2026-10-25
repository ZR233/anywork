part of 'timeline_view.dart';

/// Mounted rows declare finite demand. A display group's visible member IDs are
/// canonical; its presentation ID is never sent to the host item API.
class _AudienceDeliveryHost extends ConsumerStatefulWidget {
  const _AudienceDeliveryHost({
    required this.item,
    required this.lease,
    required this.child,
  });
  final TimelinePresentationItem item;
  final TimelineDisplayLease lease;
  final Widget child;
  @override
  ConsumerState<_AudienceDeliveryHost> createState() =>
      _AudienceDeliveryHostState();
}

class _AudienceDeliveryHostState extends ConsumerState<_AudienceDeliveryHost> {
  ThreadAudienceScope? _scope;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    widget.item.addListener(_changed);
    widget.lease.addItemListener(_memberChanged);
    try {
      _scope = widget.lease.audience;
      _demand();
    } catch (error) {
      _error = error;
    }
  }

  void _detach(TimelinePresentationItem item, TimelineDisplayLease lease) {
    item.removeListener(_changed);
    lease.removeItemListener(_memberChanged);
    lease.removeAudienceDemand(this);
  }

  void _memberChanged(String id, TimelineMessagePayload? payload) {
    if (widget.item.visibleMemberIds.contains(id)) _changed();
  }

  void _changed() {
    _demand();
    if (mounted) setState(() {});
  }

  Iterable<String> get _ids => widget.item.visibleMemberIds.where((id) {
    final state = widget.item.payload(id)?.item.state;
    return state is ThreadPublicArtifactItemStateView ||
        state is ThreadTextItemStateView &&
            (state.channel == ThreadTextChannel.commentary ||
                state.channel == ThreadTextChannel.finalAnswer);
  });
  void _demand() => widget.lease.setAudienceDemand(this, _ids);
  @override
  void didUpdateWidget(covariant _AudienceDeliveryHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item || oldWidget.lease != widget.lease) {
      _detach(oldWidget.item, oldWidget.lease);
      _attach();
    } else {
      _demand();
    }
  }

  @override
  void dispose() {
    _detach(widget.item, widget.lease);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    if (widget.lease.isRetired || scope != null && !scope.isActive) {
      return widget.child;
    }
    final ids = _ids.toList(growable: false);
    ThreadAudienceItemsState? snapshot;
    try {
      snapshot = scope == null
          ? null
          : ref.watch(threadAudienceItemsProvider(scope));
    } catch (error) {
      _error = error;
    }
    if (ids.isEmpty || snapshot?.authorization == null && _error == null) {
      return widget.child;
    }
    final lines = <String>[];
    if (_error != null ||
        snapshot?.error != null ||
        snapshot?.unavailable != null) {
      lines.add(context.l10n.audienceReadUnavailable);
    } else if (snapshot?.loading == true) {
      lines.add(context.l10n.audienceReading);
    } else {
      for (final id in ids) {
        final item = snapshot?.items[id];
        final payload = widget.item.payload(id);
        if (item != null && payload != null) {
          lines.addAll(
            _deliveryLines(
              context,
              AudienceItemDeliveryProjection.fromStatus(
                item,
                displayRevision: payload.revision,
              ),
            ),
          );
        }
      }
    }
    if (lines.isEmpty) return widget.child;
    final authorization = snapshot?.authorization?.id;
    final contextLabel = _scope?.isHistoricalSelection == true
        ? context.l10n.audienceHistoryContext
        : context.l10n.audienceCurrentContext;
    final label = authorization == null
        ? context.l10n.audienceReadUnavailable
        : '$contextLabel · ${authorization.botId}/${authorization.chatId} · ${authorization.generation}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.child,
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tooltip(
            message: '$label\n${lines.join('\n')}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  lines.first,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (ids.any((id) => _channelTruncated(snapshot?.items[id])))
                  Text(
                    context.l10n.audienceTruncated,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ),
        if (_error != null ||
            snapshot?.error != null ||
            snapshot?.unavailable != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                try {
                  _scope ??= widget.lease.audience;
                  _scope?.retry();
                  setState(() => _error = null);
                } catch (error) {
                  setState(() => _error = error);
                }
              },
              child: Text(context.l10n.modelDetailRetry),
            ),
          ),
      ],
    );
  }
}

bool _channelTruncated(BotAudienceItemStatus? status) {
  final delivery = status?.delivery;
  if (delivery is! BotItemDeliveryKnown) return false;
  return [delivery.ledger.projected, delivery.ledger.accepted].any(
    (presentation) =>
        presentation is BotItemPresentationText &&
        presentation.integrity == BotTextIntegrity.truncated,
  );
}

List<String> _deliveryLines(
  BuildContext context,
  AudienceItemDeliveryProjection projection,
) {
  final l = context.l10n;
  final status = projection.status;
  final lines = <String>[];
  switch (status.canonical) {
    case BotAudienceCanonicalItemRemoved():
      lines.add(l.audienceRemoved);
    case BotAudienceCanonicalItemUnavailable(:final reason):
      lines.add('${l.audienceSourceUnavailable} (${reason.name})');
    case BotAudienceCanonicalItemPresent(:final eligibility):
      if (eligibility case BotItemEligibilityNotAuthorized(:final reason)) {
        lines.add('${l.audienceNotAuthorized} (${reason.name})');
      }
  }
  final ledger = projection.ledger;
  if (ledger == null) {
    lines.add(l.audienceNoRecord);
    return lines;
  }
  final canonicalLineCount = lines.length;
  if (projection.currentRevisionAccepted) lines.add(l.audienceCurrentAccepted);
  if (projection.historicalRevisionAccepted) {
    lines.add(l.audienceHistoricalAccepted);
  }
  lines.add('${l.audienceObserved}: ${ledger.observedRevision}');
  void presentation(String label, BotItemPresentation value) {
    switch (value) {
      case BotItemPresentationNone():
        break;
      case BotItemPresentationText(:final revision, :final integrity):
        lines.add(
          '$label: $revision · ${integrity == BotTextIntegrity.truncated ? l.audienceTruncated : l.audienceFull}',
        );
      case BotItemPresentationFile(:final revision):
        lines.add('$label: $revision');
    }
  }

  presentation(l.audienceProjected, ledger.projected);
  presentation(l.audienceAccepted, ledger.accepted);
  String result(BotPlatformResult value) => switch (value) {
    BotPlatformResultNotStarted() => l.audienceNotStarted,
    BotPlatformResultInFlight() => l.audienceInFlight,
    BotPlatformResultAccepted() => l.audiencePlatformAccepted,
    BotPlatformResultRejected(:final diagnostic) =>
      '${l.audiencePlatformRejected} (${diagnostic.code})',
    BotPlatformResultUnknown(:final diagnostic) =>
      '${l.audiencePlatformUnknown} (${diagnostic.code})',
  };
  final platformLines = <String>[];
  switch (ledger.platform) {
    case BotItemPlatformNone():
      break;
    case BotItemPlatformBlocked(:final reason):
      platformLines.add('${l.audienceBlocked} (${reason.name})');
    case BotItemPlatformCard(:final latestOperation):
      platformLines.add(
        '${latestOperation.action.name} · ${latestOperation.contentRevision}: ${result(latestOperation.result)}',
      );
    case BotItemPlatformFile(
      :final contentRevision,
      :final upload,
      :final message,
      :final outcome,
      :final localStop,
    ):
      if (outcome == BotFileOutcome.partial) {
        platformLines.add(l.audiencePartial);
      }
      platformLines.add(
        '${l.audienceUpload}: ${result(upload)} · ${l.audienceMessage}: ${result(message)} · $contentRevision',
      );
      if (localStop != null) platformLines.add(localStop.name);
  }
  lines.insertAll(canonicalLineCount, platformLines);
  return lines;
}

class _PublicArtifactBlock extends ConsumerWidget {
  const _PublicArtifactBlock({
    required this.item,
    required this.artifact,
    required this.lease,
  });
  final ThreadItemView item;
  final ThreadPublicArtifactItemStateView artifact;
  final TimelineDisplayLease lease;
  bool _current() {
    if (lease.isRetired) return false;
    final current = lease.payloadOf(item.id)?.item;
    final state = current?.state;
    return current?.threadId == item.threadId &&
        current?.revision == item.revision &&
        state is ThreadPublicArtifactItemStateView &&
        state.publicationId == artifact.publicationId &&
        state.toolCallId == artifact.toolCallId &&
        state.displayName == artifact.displayName &&
        state.resource == artifact.resource;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(appGraphProvider).artifacts;
    final key = actions.keyOf(item);
    final observed = ref.watch(publicArtifactSaveProvider(key));
    final result = observed?.result;
    final l = context.l10n;
    final outcome = switch (result?.outcome) {
      PublicArtifactSaveOutcome.saved => l.artifactSaved,
      PublicArtifactSaveOutcome.savedNotOpened => l.artifactSavedNotOpened,
      PublicArtifactSaveOutcome.handedToSystem => l.artifactHandedToSystem,
      PublicArtifactSaveOutcome.failed => l.artifactSaveFailed,
      PublicArtifactSaveOutcome.cancelled ||
      PublicArtifactSaveOutcome.retired ||
      null => null,
    };
    return Card(
      key: ValueKey(
        'public-artifact:${item.threadId}:${item.id}:${item.revision}',
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.artifactPublished,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Tooltip(
              message: artifact.displayName,
              child: Text(
                artifact.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '${artifact.resource.mediaType} · ${artifact.resource.byteLen} B',
            ),
            Text(
              item.saved ? l.artifactHistorySaved : l.artifactHistoryPending,
            ),
            SelectableText(
              '${artifact.publicationId}\n${artifact.toolCallId}\n${artifact.resource.id}\n${artifact.resource.contentDigest}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              l.artifactTrustWarning,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (outcome != null) Text(outcome),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: ValueKey(
                    'public-artifact-save:${item.threadId}:${item.id}:${item.revision}',
                  ),
                  onPressed: observed?.running == true
                      ? null
                      : () => unawaited(_save(context, actions, false)),
                  child: Text(l.artifactSave),
                ),
                TextButton(
                  key: ValueKey(
                    'public-artifact-save-open:${item.threadId}:${item.id}:${item.revision}',
                  ),
                  onPressed: observed?.running == true
                      ? null
                      : () => unawaited(_save(context, actions, true)),
                  child: Text(l.artifactSaveOpen),
                ),
              ],
            ),
            if (observed?.running == true) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    PublicArtifactActions actions,
    bool open,
  ) async {
    try {
      await actions.save(item, openAfterSave: open, isCurrent: _current);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.artifactSaveFailed)),
        );
      }
    }
  }
}
