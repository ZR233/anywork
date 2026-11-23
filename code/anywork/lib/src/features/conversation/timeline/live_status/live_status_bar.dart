import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../presentation/view_models/timeline_session_owner.dart';
import '../connectors/interaction_details_connector.dart';
import '../connectors/timeline_member_atom.dart';
import '../state/timeline_current_projection.dart';
import '../state/timeline_display_unit.dart';
import '../view_models/display_member_controller.dart';
import '../view_models/timeline_view_model.dart';
import '../widgets/completion_run_view.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_activity_viewport.dart';
import 'live_status_state.dart';
import 'live_status_view_model.dart';

/// 自包含的会话底部实时状态栏组件唯一挂载入口：
/// 外层外壳只需传入 `threadId`，所有 FRB 源状态监听、状态机转换、分页与驱动状态同步
/// 均收敛于组件专属 `LiveStatusViewModel` 与 `LiveStatusProjection` 内部。
class LiveStatusBar extends ConsumerWidget {
  const LiveStatusBar({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aggregate = ref.watch(liveStatusViewModelProvider(threadId));
    if (aggregate == null) return const SizedBox.shrink();

    final barState = aggregate.barState;
    final client = ref.read(anyworkClientProvider);
    final conversations = client.conversations;
    final session = conversations.existingSession(threadId);
    if (session == null) return const SizedBox.shrink();

    final sessionState = ref.watch(threadSessionStoreProvider(threadId));
    final owner = ref.read(timelineSessionOwnerProvider);
    final detailLease = owner.lease(threadId);

    bool active() =>
        detailLease != null &&
        identical(owner.lease(threadId), detailLease) &&
        !detailLease.isRetired;

    Future<Uint8List> readAttachment(String id) async {
      if (!active()) throw const StaleConversationScope();
      final bytes = await client.readAttachmentBytes(threadId, id);
      if (!active()) throw const StaleConversationScope();
      return bytes;
    }

    final children = <Widget>[];

    final presenting = switch (barState) {
      LiveStatusPresenting() => barState,
      LiveStatusDockMasked(:final obscured) => obscured,
      LiveStatusHidden() => null,
    };
    final masked = barState is LiveStatusDockMasked;
    if (!masked && presenting != null) {
      final surface = presenting.surface;
      final Widget? workBar =
          detailLease != null &&
              (surface.liveOpenWork != null || surface.liveWorkAtoms.isNotEmpty)
          ? _LiveWorkSection(
              key: ValueKey(('live-work', threadId, detailLease.generation)),
              threadId: threadId,
              lease: detailLease,
              workBlock: surface.liveOpenWork,
              liveWorkAtoms: surface.liveWorkAtoms,
              primaryActivity: aggregate.primaryActivity,
              isActive: active,
              readAttachment: readAttachment,
              monotonicMicros: () => owner.monotonicMicros,
              onCurrentContentLayout: (id, micros) {
                if (active()) {
                  owner.recordCurrentContentLayout(detailLease, id, micros);
                }
              },
              onCurrentContentUnmounted: (id) {
                if (active()) {
                  owner.recordCurrentContentUnmounted(detailLease, id);
                }
              },
            )
          : null;

      final Widget? noticeWidget = surface.notices.isNotEmpty
          ? ConversationRealtimeNotices(
              key: const ValueKey('live-notices'),
              notices: surface.notices,
            )
          : null;

      final responseWidgets = <Widget>[
        if (detailLease != null)
          for (final atom in surface.liveResponseAtoms)
            TimelineMemberAtom(
              key: ValueKey('live-response:${atom.id}'),
              record: DisplayRecord(
                atom: TimelineCurrentProjection.toChatAtom(atom),
                contentSource: const CurrentAtomSource(),
                currentContents: atom.contents,
              ),
              displayId: atom.id,
              threadId: threadId,
              currentReader: detailLease.current,
              retirement: detailLease.retirement,
              isActive: active,
              images: detailLease.imageResources,
              readAttachment: readAttachment,
              executionPresent: true,
              monotonicMicros: () => owner.monotonicMicros,
              onCurrentContentLayout: (id, micros) {
                if (active()) {
                  owner.recordCurrentContentLayout(detailLease, id, micros);
                }
              },
              onCurrentContentUnmounted: (id) {
                if (active()) {
                  owner.recordCurrentContentUnmounted(detailLease, id);
                }
              },
            ),
      ];

      if (workBar != null ||
          noticeWidget != null ||
          responseWidgets.isNotEmpty) {
        children.add(
          ConversationActivityBar(
            leading: [?workBar],
            children: [?noticeWidget, ...responseWidgets],
          ),
        );
      }
    }

    if (aggregate.currentAtomsError case final error?) {
      children.add(ConversationActivityBar(children: [Text(error.toString())]));
    }

    final tools = aggregate.activityTools;
    if (tools != null && !masked) {
      final notifier = ref.read(liveStatusViewModelProvider(threadId).notifier);
      children.add(
        ConversationActivityBar(
          children: [
            if (!tools.expanded)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('live-activity-tools-open'),
                  onPressed: notifier.openActivityTools,
                  icon: const Icon(Icons.build_outlined, size: 16),
                  label: Text('活动工具 ${tools.totalCount}'),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '活动工具 ${tools.loadedCount}/${tools.totalCount}',
                      key: const ValueKey('live-activity-tools-count'),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('live-activity-tools-close'),
                    onPressed: notifier.closeActivityTools,
                    child: const Text('收起'),
                  ),
                ],
              ),
              if (tools.error case final error?) Text(error.toString()),
              if (tools.loading)
                const LinearProgressIndicator()
              else
                for (final tool in tools.entries)
                  Text('${tool.name} · ${tool.summary} · ${tool.state.name}'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('live-activity-tools-first'),
                    onPressed: tools.hasPrevious
                        ? notifier.loadFirstActivityTools
                        : null,
                    child: const Text('第一页'),
                  ),
                  TextButton(
                    key: const ValueKey('live-activity-tools-previous'),
                    onPressed: tools.hasPrevious
                        ? notifier.loadPreviousActivityTools
                        : null,
                    child: const Text('上一页'),
                  ),
                  TextButton(
                    key: const ValueKey('live-activity-tools-next'),
                    onPressed: tools.hasNext
                        ? notifier.loadNextActivityTools
                        : null,
                    child: const Text('下一页'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final reference = sessionState.businessRefs?.interactions;
    if (barState.showInteractionDetails &&
        reference != null &&
        detailLease != null) {
      children.add(
        InteractionDetailsConnector(
          key: ValueKey((
            'interaction-details',
            detailLease,
            detailLease.generation,
          )),
          openCurrent: () =>
              detailLease.openCurrentScope(generation: detailLease.generation),
          reference: reference,
          isCurrent: () =>
              identical(conversations.existingSession(threadId), session) &&
              conversations.visibleThreadId.value == threadId &&
              session.state.businessRefs?.interactions == reference &&
              !detailLease.isRetired &&
              identical(
                ref.read(timelineSessionOwnerProvider).lease(threadId),
                detailLease,
              ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return ConversationActivityViewport(
      key: ValueKey(threadId),
      children: children,
    );
  }
}

class _LiveWorkSection extends StatefulWidget {
  const _LiveWorkSection({
    required this.threadId,
    required this.lease,
    required this.workBlock,
    required this.liveWorkAtoms,
    required this.primaryActivity,
    required this.isActive,
    required this.readAttachment,
    required this.monotonicMicros,
    required this.onCurrentContentLayout,
    required this.onCurrentContentUnmounted,
    super.key,
  });

  final String threadId;
  final TimelineDisplayLease lease;
  final DisplayBlock? workBlock;
  final List<CurrentAtom> liveWorkAtoms;
  final ConversationActivityView? primaryActivity;
  final bool Function() isActive;
  final Future<Uint8List> Function(String) readAttachment;
  final int Function() monotonicMicros;
  final void Function(String, int) onCurrentContentLayout;
  final void Function(String) onCurrentContentUnmounted;

  @override
  State<_LiveWorkSection> createState() => _LiveWorkSectionState();
}

class _LiveWorkSectionState extends State<_LiveWorkSection> {
  final TimelineExpansionIntent _intent = TimelineExpansionIntent();
  final Object _visibility = Object();
  bool _expanded = false;

  WorkDisplayBlock? get _workBody => widget.workBlock?.body is WorkDisplayBlock
      ? widget.workBlock!.body as WorkDisplayBlock
      : null;

  WorkTiming _timing() {
    if (_workBody case final body?) return body.timing;
    int? earliestMillis;
    for (final atom in widget.liveWorkAtoms) {
      final startedAt = atom.startedAt;
      if (startedAt == null) continue;
      final millis = startedAt * Duration.millisecondsPerSecond;
      if (earliestMillis == null || millis < earliestMillis) {
        earliestMillis = millis;
      }
    }
    return WorkTiming(startedAtMillis: earliestMillis, finishedAtMillis: null);
  }

  DisplayBlock _effectiveBlock() {
    if (widget.workBlock case final block?) return block;
    return DisplayBlock(
      id: 'live-current-work',
      blockOrder: 0,
      body: WorkDisplayBlock(
        members: const DisplayBlockRef(
          blockId: 'live-current-work',
          cut: HistoryCut(''),
          anchorSeq: 0,
          headSeq: 0,
          afterSeq: 0,
        ),
        timing: _timing(),
        executionPresent: true,
        memberCount: 0,
        unfinishedCount: widget.liveWorkAtoms.length,
        groupClosed: false,
      ),
    );
  }

  void _updateIntentCurrent() {
    _intent.current = TimelineDisplayUnit(
      block: _effectiveBlock(),
      expansion: _intent,
    );
  }

  void _ensureMembers() {
    final workBody = _workBody;
    if (!_expanded || workBody == null || _intent.isRetired) return;
    _intent.members ??= DisplayMemberController(
      reference: workBody.members,
      groupClosed: false,
      demand: const ReadDemand(maxItems: 12, maxBytes: 32 * 1024),
      open: (reference, demand, _) => widget.lease.openLiveWorkMembers(
        reference: reference,
        demand: demand,
      ),
    );
  }

  void _closeMembers() {
    final previous = _intent.members;
    _intent.members = null;
    previous?.retire();
    if (previous != null) unawaited(previous.close());
  }

  @override
  void initState() {
    super.initState();
    _intent.expanded = false;
    widget.lease.bindLiveWorkIntent(_intent);
    _updateIntentCurrent();
    _intent.setBodyVisible(_visibility, false);
  }

  @override
  void didUpdateWidget(covariant _LiveWorkSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateIntentCurrent();
    if (!_expanded) return;
    final oldWorkBody = oldWidget.workBlock?.body is WorkDisplayBlock
        ? oldWidget.workBlock!.body as WorkDisplayBlock
        : null;
    final newWorkBody = _workBody;
    if (newWorkBody == null) {
      _closeMembers();
      return;
    }
    if (_intent.members == null) {
      _ensureMembers();
    } else if (oldWorkBody?.members != newWorkBody.members ||
        !_sameLiveAtomRefs(oldWidget.liveWorkAtoms, widget.liveWorkAtoms)) {
      _intent.members!.rebase(
        newWorkBody.members,
        groupClosed: false,
        force: oldWorkBody?.members == newWorkBody.members,
      );
    }
  }

  @override
  void dispose() {
    _intent.setBodyVisible(_visibility, false);
    _intent.retire();
    super.dispose();
  }

  void _onExpandedChanged(bool expanded) {
    if (_expanded == expanded) return;
    setState(() {
      _expanded = expanded;
      _intent.expanded = expanded;
      _intent.setBodyVisible(_visibility, expanded);
      if (expanded) {
        _ensureMembers();
      }
    });
  }

  ConversationActivityView? _filterWorkHeaderActivity(
    ConversationActivityView? primary,
  ) {
    if (primary == null || primary.errorMessage != null) return null;
    return switch (primary.kind) {
      ConversationActivityKind.responding ||
      ConversationActivityKind.compacting ||
      ConversationActivityKind.stopping ||
      ConversationActivityKind.awaitingApproval ||
      ConversationActivityKind.awaitingInput ||
      ConversationActivityKind.storageBlocked => null,
      ConversationActivityKind.preparing ||
      ConversationActivityKind.thinking ||
      ConversationActivityKind.planning ||
      ConversationActivityKind.runningTool => primary,
    };
  }

  Widget _buildLiveAtom(CurrentAtom atom) => TimelineMemberAtom(
    key: ValueKey(('live-atom', atom.id)),
    record: DisplayRecord(
      atom: TimelineCurrentProjection.toChatAtom(atom),
      contentSource: const CurrentAtomSource(),
      currentContents: atom.contents,
    ),
    displayId: atom.id,
    threadId: widget.threadId,
    currentReader: widget.lease.current,
    retirement: _intent.retirement,
    isActive: () => _expanded && widget.isActive(),
    images: widget.lease.imageResources,
    readAttachment: widget.readAttachment,
    executionPresent: true,
    monotonicMicros: widget.monotonicMicros,
    onCurrentContentLayout: widget.onCurrentContentLayout,
    onCurrentContentUnmounted: widget.onCurrentContentUnmounted,
  );

  @override
  Widget build(BuildContext context) {
    final workHeaderActivity = _filterWorkHeaderActivity(
      widget.primaryActivity,
    );
    return CompletionRunView(
      id: widget.workBlock?.id ?? 'live-current-work',
      location: WorkDisplayLocation.live,
      state: DisplayBlockState.open,
      executionPresent: true,
      timing: _timing(),
      activity: workHeaderActivity,
      thinkingSummary: workHeaderActivity?.thinkingSummary,
      hasUnfinishedMembers: true,
      initiallyExpanded: _expanded,
      onExpandedChanged: _onExpandedChanged,
      childBuilder: (_) {
        if (_intent.isRetired) return const SizedBox.shrink();
        final controller = _intent.members;
        return TimelineGroupBodyIntent(
          intent: _intent,
          child: controller == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final atom in widget.liveWorkAtoms)
                      _buildLiveAtom(atom),
                  ],
                )
              : ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) {
                    final representedIds = <String>{};
                    final representedCallIds = <String>{};
                    for (final entry in controller.entries) {
                      representedIds.add(entry.record.atom.id);
                      final callId =
                          entry.record.callId ?? entry.record.atom.tool?.callId;
                      if (callId != null) representedCallIds.add(callId);
                    }
                    final extraAtoms = <CurrentAtom>[
                      for (final atom in widget.liveWorkAtoms)
                        if (!representedIds.contains(atom.id) &&
                            (atom.tool?.callId == null ||
                                !representedCallIds.contains(
                                  atom.tool!.callId,
                                )))
                          atom,
                    ];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (controller.error case final error?)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(error.toString()),
                              TextButton(
                                onPressed: controller.retry,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        if (controller.loading) const LinearProgressIndicator(),
                        for (final entry in controller.entries)
                          ValueListenableBuilder<DisplayMemberHead?>(
                            key: ValueKey(entry.memberKey),
                            valueListenable: controller.member(entry.memberKey),
                            builder: (_, value, _) => value == null
                                ? const SizedBox.shrink()
                                : TimelineMemberAtom(
                                    key: ValueKey((
                                      controller.reference,
                                      entry.memberKey,
                                      controller.disclosure(entry.memberKey),
                                    )),
                                    record: value.record,
                                    displayId: entry.memberKey,
                                    disclosure: controller.disclosure(
                                      entry.memberKey,
                                    ),
                                    executionPresent: true,
                                    threadId: widget.threadId,
                                    currentReader: widget.lease.current,
                                    retirement: _intent.retirement,
                                    isActive: () =>
                                        _expanded && widget.isActive(),
                                    images: widget.lease.imageResources,
                                    readAttachment: widget.readAttachment,
                                    monotonicMicros: widget.monotonicMicros,
                                    onCurrentContentLayout:
                                        widget.onCurrentContentLayout,
                                    onCurrentContentUnmounted:
                                        widget.onCurrentContentUnmounted,
                                  ),
                          ),
                        for (final atom in extraAtoms) _buildLiveAtom(atom),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

bool _sameLiveAtomRefs(List<CurrentAtom> a, List<CurrentAtom> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.kind != y.kind ||
        x.lifecycle.runtimeType != y.lifecycle.runtimeType ||
        x.tool?.callId != y.tool?.callId ||
        x.contents.length != y.contents.length) {
      return false;
    }
    for (var j = 0; j < x.contents.length; j++) {
      if (x.contents[j].role != y.contents[j].role ||
          x.contents[j].reference != y.contents[j].reference) {
        return false;
      }
    }
  }
  return true;
}
