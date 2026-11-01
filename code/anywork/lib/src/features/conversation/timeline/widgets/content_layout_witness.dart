import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A witness of one decoded body, never of its row, controls or placeholder.
/// Layout supplies the timestamp; composition only qualifies actual visibility,
/// including when an ancestor reuses a retained layer without repainting this body.
class ContentLayoutWitness extends SingleChildRenderObjectWidget {
  /// MetaData marker for controls/diagnostics inside an otherwise real body.
  static const nonContent = #timelineContentLayoutNonContent;

  const ContentLayoutWitness({
    super.key,
    required this.itemId,
    required this.monotonicMicros,
    required this.onContentLayout,
    required this.isDisplayActive,
    required super.child,
  });

  final String itemId;
  final int Function() monotonicMicros;
  final void Function(String itemId, int layoutCompletedMicros) onContentLayout;
  final bool Function()? isDisplayActive;

  @override
  RenderObject createRenderObject(BuildContext context) => _ContentLayoutRender(
    itemId,
    monotonicMicros,
    onContentLayout,
    isDisplayActive,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _ContentLayoutRender).update(
      itemId,
      monotonicMicros,
      onContentLayout,
      isDisplayActive,
    );
  }
}

class _ContentLayoutRender extends RenderProxyBox {
  // Segment the laid-out string, not Markdown. Keep every original UTF-16
  // offset, including each WidgetSpan's U+FFFC, but never select those slots.
  static final _textRuns = RegExp(r'[^\s\uFFFC]+', unicode: true);

  _ContentLayoutRender(
    this._itemId,
    this._clock,
    this._onLayout,
    this._isActive,
  );
  String _itemId;
  int Function() _clock;
  void Function(String, int) _onLayout;
  bool Function()? _isActive;
  VoidCallback? _removeCompositionCallback;
  _LayoutCandidate? _candidate;
  Object? _revealRequest;
  bool _reported = false;

  void update(
    String itemId,
    int Function() clock,
    void Function(String, int) onLayout,
    bool Function()? isActive,
  ) {
    if (_itemId == itemId &&
        _clock == clock &&
        _onLayout == onLayout &&
        _isActive == isActive) {
      return;
    }
    _itemId = itemId;
    _clock = clock;
    _onLayout = onLayout;
    _isActive = isActive;
    _candidate = null;
    _revealRequest = null;
    _reported = false;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_reported) return;
    final candidate = _LayoutCandidate(_clock());
    _candidate = candidate;
    final itemId = _itemId;
    final onLayout = _onLayout;
    final isActive = _isActive;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!identical(_candidate, candidate)) return;
      _candidate = null;
      if (!candidate.composited ||
          !attached ||
          !(isActive?.call() ?? true) ||
          !_hasVisibleContent()) {
        return;
      }
      _reported = true;
      _removeCompositionCallback?.call();
      _removeCompositionCallback = null;
      onLayout(itemId, candidate.completedMicros);
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _removeCompositionCallback?.call();
    _removeCompositionCallback = null;
    if (_reported) return;
    // Flutter invokes this even when an ancestor is added through addRetained.
    // Observe the existing layer; no extra compositing or visibility layer is needed.
    _removeCompositionCallback = context.addCompositionCallback(_didComposite);
  }

  void _didComposite(Layer layer) {
    if (_reported ||
        !attached ||
        !layer.attached ||
        !(_isActive?.call() ?? true)) {
      return;
    }
    final candidate = _candidate;
    if (candidate != null) {
      candidate.composited = _hasVisibleContent();
    } else if (_hasVisibleContent()) {
      // A cached body can be revealed by scroll, viewport resize or an ancestor
      // clip without running its paint/layout again. Request one real layout,
      // never reuse the old invisible timestamp or substitute notification time.
      if (_revealRequest != null) return;
      final request = Object();
      _revealRequest = request;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!identical(_revealRequest, request)) return;
        _revealRequest = null;
        // Composition callbacks may observe but must not mutate the layer tree.
        // Defer invalidation until the frame has ended, then take the next real layout.
        if (attached && !_reported && (_isActive?.call() ?? true)) {
          markNeedsLayout();
        }
      });
    }
  }

  bool _hasVisibleContent() {
    var found = false;
    void visit(RenderObject render) {
      if (found ||
          (render is RenderMetaData &&
              render.metaData == ContentLayoutWitness.nonContent)) {
        return;
      }
      final text = render is RenderParagraph && _hasVisibleText(render);
      final image =
          render is RenderImage &&
          render.image != null &&
          _visible(render, Offset.zero & render.size);
      if (text || image) {
        found = true;
        return;
      }
      render.visitChildren(visit);
    }

    if (child != null) visit(child!);
    return found;
  }

  bool _hasVisibleText(RenderParagraph paragraph) {
    final source = paragraph.text.toPlainText(
      includeSemanticsLabels: false,
      includePlaceholders: true,
    );
    for (final run in _textRuns.allMatches(source)) {
      // RegExp match offsets address the original UTF-16 paragraph string.
      // Tight selections exclude whitespace and WidgetSpan boxes, while Flutter
      // handles shaping, surrogate pairs, wrapping and bidi geometry.
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: run.start, extentOffset: run.end),
      );
      for (final box in boxes) {
        if (_visible(paragraph, box.toRect())) return true;
      }
    }
    return false;
  }

  bool _visible(RenderBox content, Rect region) {
    if (!content.attached || !content.hasSize || content.size.isEmpty) {
      return false;
    }
    RenderObject childOnPath = content;
    RenderObject? ancestor = content.parent;
    var visible = region;
    if (!visible.isFinite || visible.isEmpty) return false;
    while (ancestor != null) {
      if ((ancestor is RenderOffstage && ancestor.offstage) ||
          (ancestor is RenderOpacity && ancestor.opacity <= 0) ||
          (ancestor is RenderAnimatedOpacity && ancestor.opacity.value <= 0)) {
        return false;
      }
      // Keep clipping in each ancestor's coordinates, including animated
      // disclosures and nested viewports. Paint alone may still traverse clips.
      visible = MatrixUtils.transformRect(
        childOnPath.getTransformTo(ancestor),
        visible,
      );
      if (!visible.isFinite || visible.isEmpty) return false;
      final clip = ancestor.describeApproximatePaintClip(childOnPath);
      if (clip != null) visible = visible.intersect(clip);
      if (ancestor is RenderAbstractViewport && ancestor is RenderBox) {
        visible = visible.intersect(Offset.zero & (ancestor as RenderBox).size);
      } else if (ancestor is RenderView) {
        visible = visible.intersect(ancestor.paintBounds);
      }
      if (visible.isEmpty) return false;
      childOnPath = ancestor;
      ancestor = ancestor.parent;
    }
    return true;
  }

  @override
  void detach() {
    _removeCompositionCallback?.call();
    _removeCompositionCallback = null;
    _candidate = null;
    _revealRequest = null;
    super.detach();
  }
}

class _LayoutCandidate {
  _LayoutCandidate(this.completedMicros);
  final int completedMicros;
  bool composited = false;
}
