part of 'timeline_view.dart';

enum _TimelineLayoutChangeKind { expand, collapse, content }

/// A row reports presentation changes; only Timeline owns reading and scrolling.
class _TimelineItemLayoutScope extends InheritedWidget {
  const _TimelineItemLayoutScope({
    required this.itemId,
    required this.onChange,
    required super.child,
  });

  final String itemId;
  final void Function(String, BuildContext, _TimelineLayoutChangeKind) onChange;

  static void report(BuildContext context, _TimelineLayoutChangeKind kind) {
    final scope = context
        .getInheritedWidgetOfExactType<_TimelineItemLayoutScope>();
    scope?.onChange(scope.itemId, context, kind);
  }

  @override
  bool updateShouldNotify(_TimelineItemLayoutScope oldWidget) =>
      itemId != oldWidget.itemId || onChange != oldWidget.onChange;
}

class _TimelineLayoutTarget {
  const _TimelineLayoutTarget({
    required this.itemId,
    required this.context,
    required this.top,
    required this.threadId,
    required this.windowEpoch,
    required this.viewId,
    required this.readingGeneration,
  });

  final String itemId;
  final BuildContext context;
  final double top;
  final String? threadId;
  final int windowEpoch;
  final String? viewId;
  final int readingGeneration;
}

extension on _TimelineViewState {
  /// Kept-alive sliver children remain attached but have no paint transform.
  /// Follow Flutter's paint relationship before measuring any reading geometry.
  Rect? _paintedViewportRect(BuildContext? context) {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final box = context?.findRenderObject();
    if (viewport is! RenderBox ||
        !viewport.attached ||
        !viewport.hasSize ||
        !viewport.size.isFinite ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !box.size.isFinite ||
        box.size.isEmpty) {
      return null;
    }
    RenderObject child = box;
    while (child != viewport) {
      final parent = child.parent;
      if (parent == null || !parent.paintsChild(child)) return null;
      if (parent is RenderSliver && parent.geometry?.visible != true) {
        return null;
      }
      child = parent;
    }
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(viewport),
      Offset.zero & box.size,
    );
    return rect.isFinite ? rect : null;
  }

  void _invalidateIndexRestore() {
    _readingGeneration++;
    _observer.controller = null;
    _indexRestore = null;
    _programmaticScroll = false;
  }

  void _cancelLayoutRestore() {
    _invalidateIndexRestore();
    _restoreClamped = false;
    _pendingRestore = const _TimelineRestore.bottom();
    _settledAnchor = null;
  }

  _TimelineLayoutTarget? get _validLayoutTarget {
    final target = _pendingRestore.target;
    if (target == null ||
        target.threadId != widget.threadId ||
        target.viewId != widget.viewId ||
        target.windowEpoch != widget.windowEpoch ||
        target.readingGeneration != _readingGeneration ||
        !target.context.mounted ||
        (_anchorRowId(target.itemId) == null &&
            target.itemId !=
                'plan:${widget.planConfirmation?.interactionId}')) {
      return null;
    }
    return target;
  }

  double? _layoutTargetPixels(_TimelineLayoutTarget target) {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final rect = _paintedViewportRect(target.context);
    if (viewport is! RenderBox || rect == null || !_controller.hasClients) {
      return null;
    }
    // Reveal only the operation's leading edge, never the whole expanded row.
    final wanted = target.top.clamp(
      0.0,
      math.max(0.0, viewport.size.height - 40),
    );
    return _controller.position.pixels + rect.top - wanted;
  }

  void _handleItemLayoutChange(
    String itemId,
    BuildContext trigger,
    _TimelineLayoutChangeKind kind,
  ) {
    final explicit = kind != _TimelineLayoutChangeKind.content;
    if (!explicit &&
        (_followingBottom || _userScrollActive || _keyboardScrolling)) {
      _scheduleGeometrySync();
      return;
    }
    if (explicit) {
      _cancelLayoutRestore();
      if (_followingBottom) {
        _beginItemInspection();
      }
      _resumeAfterNewerPage = false;
    }
    final anchor = _captureAnchor();
    final rect = explicit ? _paintedViewportRect(trigger) : null;
    final target = rect != null
        ? _TimelineLayoutTarget(
            itemId: itemId,
            context: trigger,
            top: rect.top,
            threadId: widget.threadId,
            viewId: widget.viewId,
            windowEpoch: widget.windowEpoch,
            readingGeneration: _readingGeneration,
          )
        : _validLayoutTarget;
    if (anchor != null || target != null) {
      _pendingRestore = _TimelineRestore.anchor(anchor, target: target);
      _restoreClamped = true;
    }
    _scheduleGeometrySync();
  }

  bool _handleItemSizeChanged(SizeChangedLayoutNotification notification) {
    if (_detachedByUser && !_userScrollActive && !_keyboardScrolling) {
      final anchor = _pendingRestore.anchor ?? _settledAnchor;
      if (anchor != null || _validLayoutTarget != null) {
        _pendingRestore = _TimelineRestore.anchor(
          anchor,
          target: _validLayoutTarget,
        );
        _restoreClamped = true;
      }
    }
    _scheduleGeometrySync();
    return false;
  }

  Widget _layoutItem(String itemId, Widget child) => _TimelineItemLayoutScope(
    itemId: itemId,
    onChange: _handleItemLayoutChange,
    child: NotificationListener<SizeChangedLayoutNotification>(
      onNotification: _handleItemSizeChanged,
      child: SizeChangedLayoutNotifier(child: child),
    ),
  );
}
