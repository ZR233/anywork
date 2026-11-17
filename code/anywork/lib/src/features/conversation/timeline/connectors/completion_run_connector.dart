import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:material_ui/material_ui.dart';

import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/display_member_controller.dart';
import 'timeline_member_atom.dart';
import '../../../../presentation/view_models/timeline_session_owner.dart';

/// Borrows the stable block demand from the original display lease.
class CompletionRunConnector extends StatefulWidget {
  const CompletionRunConnector({
    required this.unit,
    required this.threadId,
    required this.content,
    required this.images,
    this.readAttachment,
    this.monotonicMicros,
    this.onContentLayout,
    this.onCurrentContentLayout,
    this.onCurrentContentUnmounted,
    this.registerMemberDisplay,
    super.key,
  });
  final TimelineDisplayUnit unit;
  final String threadId;
  final TimelineDisplayLease content;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String)? readAttachment;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;
  final void Function(String, int)? onCurrentContentLayout;
  final void Function(String)? onCurrentContentUnmounted;
  final VoidCallback Function(TimelineMemberDisplay)? registerMemberDisplay;
  @override
  State<CompletionRunConnector> createState() => _MembersState();
}

class _MembersState extends State<CompletionRunConnector>
    implements TimelineGroupDisplay, TimelineMemberDisplay {
  VoidCallback? _unregister;
  VoidCallback? _unregisterMember;
  final Set<TimelineMemberDisplay> _members = {};
  DisplayMemberController? get _controller => widget.unit.expansion.members;
  @override
  String get unitId => widget.unit.id;
  @override
  DisplayBlockRef? get blockReference => widget.unit.memberReference;
  @override
  bool get isCurrent =>
      mounted &&
      !widget.unit.expansion.isRetired &&
      widget.unit.expansion.expanded == true &&
      (widget.unit.expansion.isDisplayActive?.call() ?? true);
  @override
  bool get expanded => isCurrent && widget.unit.expansion.expanded == true;
  @override
  bool get loading => isCurrent && (_controller?.loading ?? true);
  @override
  Object? get error => isCurrent ? _controller?.error : null;
  @override
  Iterable<ChatAtom> get atoms => isCurrent
      ? _controller?.entries.map((entry) => entry.record.atom) ?? const []
      : const [];
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent) return;
    for (final member in _members) {
      yield* member.windows;
    }
  }

  @override
  void initState() {
    super.initState();
    _bindDisplay();
  }

  void _bindDisplay() {
    _unregister?.call();
    _unregisterMember?.call();
    final intent = widget.unit.expansion;
    _unregister = intent.registerDisplay?.call(this);
    _unregisterMember = widget.registerMemberDisplay?.call(this);
    final open = intent.openDisplayMembers;
    if (open != null) {
      intent.members ??= DisplayMemberController(
        reference: blockReference!,
        groupClosed: (widget.unit.body as WorkDisplayBlock).groupClosed,
        // Transport budget only; the group accepts all batches.
        demand: const ReadDemand(maxItems: 12, maxBytes: 32 * 1024),
        open: open,
      );
    }
    if (widget.unit.state == DisplayBlockState.sealed) {
      _controller?.requireSealed();
    }
  }

  @override
  void didUpdateWidget(covariant CompletionRunConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindDisplay();
  }

  @override
  void dispose() {
    _unregister?.call();
    _unregisterMember?.call();
    _members.clear();
    // The display lease, not this parent Widget position, owns the member demand.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const Text('成员读取尚未就绪');
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) => _memberList(controller),
    );
  }

  Widget _memberList(DisplayMemberController controller) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controller.error case final error?)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error.toString()),
            TextButton(onPressed: controller.retry, child: const Text('重试')),
          ],
        ),
      if (controller.loading) const LinearProgressIndicator(),
      for (final entry in controller.entries)
        ValueListenableBuilder<DisplayMemberHead?>(
          key: ValueKey(entry.memberKey),
          valueListenable: controller.member(entry.memberKey),
          builder: (_, value, _) => value == null
              ? const SizedBox.shrink()
              : _member(controller, value),
        ),
    ],
  );

  Widget _member(DisplayMemberController controller, DisplayMemberHead entry) {
    if (controller.awaitingSealed &&
        entry.record.contentSource is CurrentAtomSource) {
      return const Text('正在读取封存观察…');
    }
    return TimelineMemberAtom(
      key: ValueKey((
        blockReference,
        entry.memberKey,
        controller.disclosure(entry.memberKey),
      )),
      record: entry.record,
      displayId: entry.memberKey,
      disclosure: controller.disclosure(entry.memberKey),
      executionPresent: widget.unit.executionPresent,
      threadId: widget.threadId,
      currentReader: widget.content.current,
      retirement: widget.unit.expansion.retirement,
      isActive: () => isCurrent && widget.unit.expansion.expanded == true,
      images: widget.images,
      readAttachment: widget.readAttachment,
      monotonicMicros: widget.monotonicMicros,
      onContentLayout: widget.onContentLayout,
      onCurrentContentLayout: widget.onCurrentContentLayout,
      onCurrentContentUnmounted: widget.onCurrentContentUnmounted,
      registerDisplay: (member) {
        _members.add(member);
        return () => _members.remove(member);
      },
    );
  }
}
