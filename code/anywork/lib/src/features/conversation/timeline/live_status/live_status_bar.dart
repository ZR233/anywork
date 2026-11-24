import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../presentation/view_models/timeline_session_owner.dart';
import '../connectors/interaction_details_connector.dart';
import '../connectors/timeline_member_atom.dart';
import '../connectors/work_group_member_list.dart';
import '../state/timeline_current_projection.dart';
import '../state/timeline_display_unit.dart';
import '../view_models/display_member_controller.dart';
import '../view_models/timeline_view_model.dart';
import '../widgets/completion_run_view.dart';
import 'live_status_machine.dart';
import 'live_status_state.dart';
import 'live_status_surface_view.dart';
import 'live_status_view_model.dart';

/// 自包含的会话底部实时状态栏组件唯一挂载入口：
/// 外层外壳只需传入 `threadId`，所有源状态监听、状态机转换、分页与驱动状态同步
/// 均收敛于 [LiveStatusViewModel] 与 [LiveStatusMachine]，视觉表面统一由 [LiveStatusSurfaceView] 承载。
class LiveStatusBar extends ConsumerWidget {
  const LiveStatusBar({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aggregate = ref.watch(liveStatusViewModelProvider(threadId));
    if (aggregate == null) return const SizedBox.shrink();

    final client = ref.read(anyworkClientProvider);
    final conversations = client.conversations;
    final session = conversations.existingSession(threadId);
    if (session == null) return const SizedBox.shrink();

    final reference = ref.watch(
      threadSessionStoreProvider(threadId)
          .select((session) => session.businessRefs?.interactions),
    );
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

    final Widget? detailsSlot =
        aggregate.gate.showInteractionDetails &&
            reference != null &&
            detailLease != null
        ? InteractionDetailsConnector(
            key: ValueKey((
              'interaction-details',
              detailLease,
              detailLease.generation,
            )),
            openCurrent: () => detailLease.openCurrentScope(
              generation: detailLease.generation,
            ),
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
          )
        : null;

    return LiveStatusSurfaceView(
      viewportKey: ValueKey(threadId),
      gate: aggregate.gate,
      liveWorkBuilder: detailLease == null
          ? null
          : (_, work) => _LiveWorkGroupHost(
              key: ValueKey(detailLease),
              threadId: threadId,
              lease: detailLease,
              phase: work,
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
            ),
      responseBuilder: detailLease == null
          ? null
          : (_, response) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final atom in response.responseAtoms)
                  TimelineMemberAtom(
                    key: ValueKey(('live-response', atom.id)),
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
                        owner.recordCurrentContentLayout(
                          detailLease,
                          id,
                          micros,
                        );
                      }
                    },
                    onCurrentContentUnmounted: (id) {
                      if (active()) {
                        owner.recordCurrentContentUnmounted(detailLease, id);
                      }
                    },
                  ),
              ],
            ),
      interactionDetailsSlot: detailsSlot,
    );
  }
}

/// 实时开放工作组的租约与成员分页桥接壳：自身不绘制任何业务外观，只向共享
/// [CompletionRunView] + [WorkGroupMemberList] 注入 [TimelineExpansionIntent]。
class _LiveWorkGroupHost extends StatefulWidget {
  const _LiveWorkGroupHost({
    required this.threadId,
    required this.lease,
    required this.phase,
    required this.isActive,
    required this.readAttachment,
    required this.monotonicMicros,
    required this.onCurrentContentLayout,
    required this.onCurrentContentUnmounted,
    super.key,
  });

  final String threadId;
  final TimelineDisplayLease lease;
  final LiveWorkPhase phase;
  final bool Function() isActive;
  final Future<Uint8List> Function(String) readAttachment;
  final int Function() monotonicMicros;
  final void Function(String, int) onCurrentContentLayout;
  final void Function(String) onCurrentContentUnmounted;

  @override
  State<_LiveWorkGroupHost> createState() => _LiveWorkGroupHostState();
}

class _LiveWorkGroupHostState extends State<_LiveWorkGroupHost> {
  final TimelineExpansionIntent _intent = TimelineExpansionIntent();
  final Object _visibility = Object();
  bool _expanded = false;
  Widget? _memberList;

  WorkDisplayBlock get _workBody => widget.phase.block.body as WorkDisplayBlock;

  void _updateIntentCurrent() {
    _intent.current = TimelineDisplayUnit(
      block: widget.phase.block,
      expansion: _intent,
    );
  }

  void _updateMembers() {
    if (!_expanded || _intent.isRetired) return;
    final reference = _workBody.members;
    final controller = _intent.members ??= DisplayMemberController(
      reference: reference,
      groupClosed: false,
      demand: const ReadDemand(maxItems: 12, maxBytes: 32 * 1024),
      readHistory: widget.phase.id != 'live-work:${widget.threadId}',
      open: _intent.openDisplayMembers!,
    );
    controller.rebase(reference, groupClosed: false);
    _updateCurrentMembers();

    // The header and connection attention can update without rebuilding the
    // member subtree. Its controller notifies the list or the changed row.
    _memberList ??= TimelineGroupBodyIntent(
      intent: _intent,
      child: WorkGroupMemberList(
        controller: controller,
        showLoadingIndicator: false,
        blockReference: null,
        executionPresent: true,
        threadId: widget.threadId,
        currentReader: widget.lease.current,
        retirement: _intent.retirement,
        isActive: () => _expanded && widget.isActive(),
        images: widget.lease.imageResources,
        readAttachment: (id) => widget.readAttachment(id),
        monotonicMicros: () => widget.monotonicMicros(),
        onCurrentContentLayout: (id, time) =>
            widget.onCurrentContentLayout(id, time),
        onCurrentContentUnmounted: (id) => widget.onCurrentContentUnmounted(id),
      ),
    );
  }

  void _updateCurrentMembers() {
    final current = widget.lease.live.value;
    _intent.members?.updateLive(
      atoms: LiveStatusMachine.workMembers(current),
      current: current,
    );
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
  void didUpdateWidget(covariant _LiveWorkGroupHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateIntentCurrent();
    _updateMembers();
  }

  @override
  void dispose() {
    if (_expanded) widget.lease.live.removeListener(_updateCurrentMembers);
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
        widget.lease.live.addListener(_updateCurrentMembers);
        _updateMembers();
      } else {
        widget.lease.live.removeListener(_updateCurrentMembers);
        _memberList = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => CompletionRunView(
    id: widget.phase.id,
    location: WorkDisplayLocation.live,
    state: DisplayBlockState.open,
    executionPresent: widget.phase.executionPresent,
    timing: widget.phase.timing,
    activity: widget.phase.activity,
    thinkingSummary: widget.phase.thinkingSummary,
    initiallyExpanded: _expanded,
    onExpandedChanged: _onExpandedChanged,
    childBuilder: (_) => _memberList ?? const SizedBox.shrink(),
  );
}
