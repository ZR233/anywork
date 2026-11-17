import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:material_ui/material_ui.dart';

import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/display_member_controller.dart';
import '../widgets/completion_run_view.dart';
import '../../../../presentation/view_models/timeline_session_owner.dart';
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
  final TimelineDisplayLease content;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String)? readAttachment;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;
  final VoidCallback Function(TimelineMemberDisplay)? registerMemberDisplay;
  @override
  State<CompletionRunConnector> createState() => _MembersState();
}

class _MembersState extends State<CompletionRunConnector>
    implements TimelineGroupDisplay, TimelineMemberDisplay {
  VoidCallback? _unregister;
  VoidCallback? _unregisterMember;
  final Set<TimelineMemberDisplay> _members = {};
  final Map<String, GlobalKey> _anchors = {};
  CompletionRunScrollScope? _scrollScope;
  DisplayMemberController? _listenedController;
  (String, double)? _anchor;
  bool _navigating = false;
  double _leadingSpace = 0;
  double _trailingSpace = 0;
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
  String? get before =>
      isCurrent ? _controller?.page?.before?.toString() : null;
  @override
  bool get loading => isCurrent && (_controller?.loading ?? true);
  @override
  Object? get error => isCurrent ? _controller?.error : null;
  @override
  Iterable<ChatAtom> get atoms => isCurrent
      ? _controller?.page?.entries.map((entry) => entry.record.atom) ?? const []
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
    if (widget.unit.state == DisplayBlockState.sealed) {
      _controller?.requireSealed();
    }
    _listenedController = _controller;
    _listenedController?.addListener(_pageChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = CompletionRunScrollScope.maybeOf(context);
    if (identical(scope, _scrollScope)) return;
    _scrollScope?.notifications.removeListener(_scrolled);
    _scrollScope = scope;
    scope?.notifications.addListener(_scrolled);
  }

  Rect? _rect(String key) {
    final box = _anchors[key]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  double? _contentOffset(String key) {
    final target = _anchors[key]?.currentContext?.findRenderObject();
    if (target == null) return null;
    return RenderAbstractViewport.maybeOf(target)
        ?.getOffsetToReveal(target, 0)
        .offset;
  }

  void _scrolled() {
    final scope = _scrollScope;
    if (scope == null) return;
    final notification = scope.notifications.value;
    final delta = switch (notification) {
      ScrollUpdateNotification(:final scrollDelta) => scrollDelta ?? 0,
      OverscrollNotification(:final overscroll) => overscroll,
      _ => 0.0,
    };
    _navigate(delta, fromUpdate: notification is ScrollUpdateNotification);
  }

  void _pointerScrolled(PointerSignalEvent event) {
    final scope = _scrollScope;
    final controller = _controller;
    if (event is! PointerScrollEvent ||
        scope == null ||
        controller == null ||
        controller.loading ||
        _navigating ||
        !isCurrent ||
        !scope.controller.hasClients) {
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        HardwareKeyboard.instance.logicalKeysPressed.any(
          ScrollConfiguration.of(context).pointerAxisModifiers.contains,
        )) {
      return;
    }
    final delta = event.scrollDelta.dy;
    final position = scope.controller.position;
    final older =
        delta < 0 &&
        position.pixels <= position.minScrollExtent &&
        controller.page?.before != null;
    final newer =
        delta > 0 &&
        position.pixels >= position.maxScrollExtent &&
        controller.hasNewer;
    if (!older && !newer) return;
    // Flutter's Scrollable yields a wheel event at its boundary. Compete for
    // that event only when another member page exists, so inner scrollables
    // keep priority and the outer timeline can scroll when no page is due.
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      event.respond(allowPlatformDefault: !_navigate(delta, fromUpdate: false));
    });
  }

  bool _navigate(double delta, {required bool fromUpdate}) {
    final scope = _scrollScope;
    final controller = _controller;
    if (scope == null ||
        controller == null ||
        controller.loading ||
        _navigating ||
        !isCurrent ||
        delta == 0 ||
        !scope.controller.hasClients) {
      return false;
    }
    final entries = controller.page?.entries;
    if (entries == null || entries.isEmpty) return false;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (viewport is! RenderBox) return false;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + scope.controller.position.viewportDimension;
    final first = _rect(entries.first.memberKey);
    final last = _rect(entries.last.memberKey);
    final older =
        delta < 0 &&
        first != null &&
        first.top >= top - 1 &&
        controller.page?.before != null;
    final newer =
        delta > 0 &&
        last != null &&
        last.bottom <= bottom + 1 &&
        controller.hasNewer;
    if (!older && !newer && controller.window is! LatestDisplayMembers) {
      return false;
    }
    final visible = entries.where((entry) {
      final rect = _rect(entry.memberKey);
      return rect != null && rect.bottom > top && rect.top < bottom;
    }).toList();
    // A retained edge spacer can temporarily occupy the whole viewport after
    // returning through overlapping pages. Its nearest member is still the
    // stable boundary anchor, even before it becomes visible again.
    if (visible.isEmpty && !older && !newer) return false;
    final key = visible.isEmpty
        ? (newer ? entries.last : entries.first).memberKey
        : (newer ? visible.last : visible.first).memberKey;
    final offset = _contentOffset(key);
    if (offset == null) return false;
    final position = scope.controller.position;
    final readingPixels = (older || newer) && fromUpdate
        ? position.pixels - delta
        : position.pixels;
    // Content coordinates exclude the platform's transient overscroll stretch.
    // Screen-space deltas would bake that paint transform into the new offset.
    _anchor = (
      key,
      offset -
          readingPixels.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
    );
    _navigating = true;
    if (older || newer) {
      setState(() {
        _leadingSpace = newer ? bottom - top : 0;
        _trailingSpace = older ? bottom - top : 0;
      });
    }
    if (older) {
      controller.older();
    } else if (newer) {
      controller.newer();
    } else {
      controller.holdLatest();
    }
    return true;
  }

  void _pageChanged() {
    if (_controller?.loading != false || !_navigating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isCurrent) return;
      final scroll = _scrollScope?.controller;
      final anchor = _anchor;
      _anchor = null;
      if (scroll != null && scroll.hasClients && anchor != null) {
        final offset = _contentOffset(anchor.$1);
        final position = scroll.position;
        if (offset != null) {
          scroll.jumpTo(
            (offset - anchor.$2).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
        }
      }
      _navigating = false;
    });
  }

  @override
  void didUpdateWidget(covariant CompletionRunConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unit.state == DisplayBlockState.sealed) {
      _controller?.requireSealed();
    }
  }

  @override
  void dispose() {
    _scrollScope?.notifications.removeListener(_scrolled);
    _listenedController?.removeListener(_pageChanged);
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

  Widget _memberList(DisplayMemberController controller) {
    final keys =
        controller.page?.entries.map((entry) => entry.memberKey).toSet() ??
        <String>{};
    _anchors.removeWhere((key, _) => !keys.contains(key));
    return Listener(
      onPointerSignal: _pointerScrolled,
      behavior: HitTestBehavior.translucent,
      child: Column(
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
          SizedBox(height: _leadingSpace),
          for (final entry
              in controller.page?.entries ?? const <DisplayMemberHead>[])
            KeyedSubtree(
              key: _anchors.putIfAbsent(entry.memberKey, GlobalKey.new),
              child: ValueListenableBuilder<DisplayMemberHead?>(
                valueListenable: controller.member(entry.memberKey),
                builder: (_, value, _) => value == null
                    ? const SizedBox.shrink()
                    : _member(controller, value),
              ),
            ),
          SizedBox(height: _trailingSpace),
        ],
      ),
    );
  }

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
      registerDisplay: (member) {
        _members.add(member);
        return () => _members.remove(member);
      },
    );
  }
}
