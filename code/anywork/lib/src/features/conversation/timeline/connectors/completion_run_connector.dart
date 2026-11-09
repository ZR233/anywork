import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/display_member_controller.dart';
import 'timeline_member_atom.dart';

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
    this.registerMemberDisplay,
    super.key,
  });
  final TimelineDisplayUnit unit;
  final String threadId;
  final ConversationContent content;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String)? readAttachment;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;
  final VoidCallback Function(TimelineMemberDisplay)? registerMemberDisplay;
  @override
  State<CompletionRunConnector> createState() => _MembersState();
}

class _MembersState extends State<CompletionRunConnector> implements TimelineGroupDisplay, TimelineMemberDisplay {
  VoidCallback? _unregister;
  VoidCallback? _unregisterMember;
  final Set<TimelineMemberDisplay> _members = {};
  DisplayMemberController? get _controller => widget.unit.expansion.members;
  @override
  String get unitId => widget.unit.id;
  @override
  DisplayBlockRef? get blockReference => widget.unit.memberReference;
  @override
  bool get isCurrent => mounted && !widget.unit.expansion.isRetired &&
    widget.unit.expansion.expanded == true &&
    (widget.unit.expansion.isDisplayActive?.call() ?? true);
  @override
  bool get expanded => isCurrent && widget.unit.expansion.expanded == true;
  @override
  String? get before => isCurrent ? _controller?.page?.before?.toString() : null;
  @override
  bool get loading => isCurrent && (_controller?.loading ?? true);
  @override
  Object? get error => isCurrent ? _controller?.error : null;
  @override
  Iterable<ChatAtom> get atoms => isCurrent
    ? _controller?.page?.entries.map((entry) => entry.atom) ?? const [] : const [];
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
    final intent = widget.unit.expansion;
    _unregister = intent.registerDisplay?.call(this);
    _unregisterMember = widget.registerMemberDisplay?.call(this);
    final open = intent.openDisplayMembers;
    if (open != null) {
      intent.members ??= DisplayMemberController(
        reference: blockReference!,
        demand: const ReadDemand(maxItems: 12, maxBytes: 32 * 1024),
        open: open,
      );
    }
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
      builder: (_, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.error case final error?)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(error.toString()),
              TextButton(onPressed: controller.retry, child: const Text('重试')),
            ]),
          if (controller.loading) const LinearProgressIndicator(),
          Wrap(children: [
            if (controller.page?.before case final before?)
              TextButton(
                onPressed: () => controller.select(BeforeDisplayMembers(memberOrder: before)),
                child: const Text('更早成员'),
              ),
            if (controller.window is BeforeDisplayMembers)
              TextButton(
                onPressed: () => controller.select(const LatestDisplayMembers()),
                child: const Text('最新成员'),
              ),
          ]),
          for (final entry in controller.page?.entries ?? const <DisplayMemberHead>[])
            TimelineMemberAtom(
              key: ValueKey((blockReference, entry.memberKey, controller.disclosure(entry.memberKey))),
              atom: entry.atom,
              disclosure: controller.disclosure(entry.memberKey),
              executionPresent: widget.unit.executionPresent,
              content: widget.content,
              retirement: widget.unit.expansion.retirement,
              isActive: () => isCurrent && widget.unit.expansion.expanded == true,
              images: widget.images,
              readAttachment: widget.readAttachment,
              monotonicMicros: widget.monotonicMicros,
              onContentLayout: widget.onContentLayout,
              registerDisplay: (member) {
                _members.add(member);
                return () => _members.remove(member);
              },
            ),
        ],
      ),
    );
  }
}
