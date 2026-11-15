import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../state/content_reference_identity.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_display_diagnostics.dart';
import '../widgets/timeline_content_range_view.dart';
import '../widgets/timeline_reasoning_view.dart';
import '../../../../shared/studio_driver_keys.dart';

typedef ChatContentRead = Future<ContentWindow> Function(
  ContentRef reference,
  ContentRange range,
);

/// Owns content-window IO, request eligibility and the diagnostic borrow.
class TimelineContentRangeConnector extends StatefulWidget {
  const TimelineContentRangeConnector({
    super.key,
    required this.itemId,
    required this.contentKey,
    required this.label,
    required this.reference,
    required this.witness,
    required this.readContent,
    this.isDisplayActive,
    this.registerDisplay,
  });

  final String itemId;
  final String contentKey;
  final String label;
  final ContentRef reference;
  final Widget Function(String text, Widget child) witness;
  final ChatContentRead? readContent;
  final bool Function()? isDisplayActive;
  final VoidCallback Function(TimelineCurrentWindowDisplay display)?
  registerDisplay;

  @override
  State<TimelineContentRangeConnector> createState() =>
      _TimelineContentRangeConnectorState();
}

class _TimelineContentRangeConnectorState
    extends State<TimelineContentRangeConnector>
    implements TimelineCurrentWindowDisplay {
  ContentWindow? _window;
  Object? _error;
  bool _loading = false;
  bool _expanded = false;
  bool _immediate = false;
  bool _scheduled = false;
  bool _scrollable = false;
  static const _pageBudget = 64 * 1024;
  // Only byte offsets and measured extents survive eviction, never body text.
  final _pageOffsets = <int>[0];
  final _pageHeights = <int, double>{};
  final _pages = <int, ContentWindow>{};
  String? _bodyGeneration;
  int? _availableThrough;
  bool? _sealed;
  int? _errorOffset;
  int _scrollEpoch = 0;
  int _request = 0;
  VoidCallback? _unregisterDisplay;
  TimelineExpansionIntent? _group;
  Object? _groupGeneration;
  Object? _readQualification;
  bool get _groupActive =>
      _group == null ||
      _group!.bodyActive && identical(_groupGeneration, _group!.bodyGeneration);

  bool get _displayActive =>
      mounted &&
      _expanded &&
      _groupActive &&
      (widget.isDisplayActive?.call() ?? true);

  void _groupChanged() {
    if (_groupActive) return;
    _request++;
    _unregister();
    _window = null;
    _error = null;
    _loading = false;
    if (_scrollable) {
      _clearPages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_groupActive) setState(() {});
      });
    }
  }

  void _clearPages() {
    _pages.clear();
    _pageOffsets
      ..clear()
      ..add(0);
    _pageHeights.clear();
    _bodyGeneration = null;
    _availableThrough = null;
    _sealed = null;
    _errorOffset = null;
    _scrollEpoch++;
  }

  @override
  String get id => widget.itemId;

  @override
  ContentRef get reference => widget.reference;

  @override
  int get offset => _window?.offset ?? 0;

  @override
  ContentWindow? get window => _displayActive ? _window : null;

  @override
  Object? get error => _displayActive ? _error : null;

  void _unregister() {
    final unregister = _unregisterDisplay;
    _unregisterDisplay = null;
    unregister?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = TimelineBodyReadIntent.scrollableOf(context);
    final group = TimelineGroupBodyIntent.of(context);
    final qualification = TimelineBodyReadQualification.of(context);
    final changed =
        !identical(group, _group) ||
        !identical(_groupGeneration, group?.bodyGeneration) ||
        !identical(qualification, _readQualification);
    if (changed) {
      _group?.removeListener(_groupChanged);
      _group = group;
      _groupGeneration = group?.bodyGeneration;
      _readQualification = qualification;
      group?.addListener(_groupChanged);
      if (_immediate) {
        _request++;
        _unregister();
        _window = null;
        _error = null;
        _loading = false;
        _clearPages();
        _readOnMount();
      }
    }
    if (!_immediate && TimelineBodyReadIntent.of(context)) {
      _immediate = true;
      _readOnMount();
    }
  }

  void _readOnMount() {
    _expanded = true;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _displayActive) unawaited(_load(0));
    });
  }

  @override
  void didUpdateWidget(covariant TimelineContentRangeConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.contentKey != widget.contentKey ||
        contentReferenceIdentity(oldWidget.reference) !=
            contentReferenceIdentity(widget.reference)) {
      _unregister();
      _request++;
      _window = null;
      _error = null;
      _loading = false;
      _clearPages();
      _expanded = false;
      if (_immediate) _readOnMount();
    } else if (oldWidget.registerDisplay != widget.registerDisplay) {
      _unregister();
      if (_displayActive) {
        _unregisterDisplay = widget.registerDisplay?.call(this);
      }
    }
  }

  @override
  void dispose() {
    _group?.removeListener(_groupChanged);
    _unregister();
    super.dispose();
  }

  Future<void> _load(int offset) async {
    final group = _group;
    final groupRead = _group?.readBody;
    final generation = _groupGeneration;
    final qualification = _readQualification;
    final read = groupRead == null
        ? widget.readContent
        : (ContentRef reference, ContentRange range) =>
              groupRead(generation!, reference, range);
    if (!mounted ||
        read == null ||
        _loading ||
        !_groupActive ||
        !(widget.isDisplayActive?.call() ?? true)) {
      return;
    }
    final request = ++_request;
    final reference = widget.reference;
    final isActive = widget.isDisplayActive;
    final onRead = TimelineBodyReadIntent.onReadOf(context);
    bool eligible() =>
        mounted &&
        _groupActive &&
        _expanded &&
        request == _request &&
        identical(group, _group) &&
        identical(generation, _groupGeneration) &&
        identical(qualification, _readQualification) &&
        (isActive?.call() ?? true) &&
        (widget.isDisplayActive?.call() ?? true) &&
        contentReferenceIdentity(widget.reference) ==
            contentReferenceIdentity(reference);
    setState(() {
      _loading = true;
      _error = null;
    });
    _unregisterDisplay ??= widget.registerDisplay?.call(this);
    try {
      final value = await read(
        reference,
        ContentRange(offset: offset, maxBytes: _pageBudget),
      );
      if (!eligible()) return;
      if (_scrollable) _acceptPage(offset, value);
      setState(() {
        _window = value;
        _errorOffset = null;
      });
      if (mounted && eligible()) {
        onRead?.call(value);
      }
    } catch (error) {
      if (!eligible()) return;
      setState(() {
        _error = error;
        _errorOffset = offset;
      });
    } finally {
      if (eligible()) setState(() => _loading = false);
    }
  }

  void _acceptPage(int offset, ContentWindow value) {
    final rawEnd = value.offset + value.bytes.length;
    if (value.offset != offset ||
        value.bytes.length > _pageBudget ||
        value.availableThrough < rawEnd ||
        (value.bytes.isEmpty && rawEnd < value.availableThrough) ||
        (_bodyGeneration != null && value.generation != _bodyGeneration) ||
        (_availableThrough != null &&
            value.availableThrough != _availableThrough) ||
        (_sealed != null && value.sealed != _sealed)) {
      throw StateError('正文范围或代次不一致，请重新展开详情后重试');
    }
    final end = offset + _textByteLength(value);
    if (end == offset && rawEnd < value.availableThrough) {
      throw StateError('正文范围不足以解码一个字符，请重新展开详情后重试');
    }
    final index = _pageOffsets.indexOf(offset);
    if (index < 0 ||
        (index + 1 < _pageOffsets.length && _pageOffsets[index + 1] != end)) {
      throw StateError('正文范围边界不一致，请重新展开详情后重试');
    }
    _bodyGeneration ??= value.generation;
    _availableThrough ??= value.availableThrough;
    _sealed ??= value.sealed;
    _pages.remove(offset);
    _pages[offset] = value;
    while (_pages.length > 3) {
      _pages.remove(_pages.keys.first);
    }
    if (index == _pageOffsets.length - 1 && end < value.availableThrough) {
      _pageOffsets.add(end);
    }
  }

  // A range can end inside a UTF-8 scalar. Leave at most three incomplete
  // bytes for the next bounded read rather than rendering replacement glyphs
  // or retaining a decoder that depends on evicted predecessor pages.
  int _textByteLength(ContentWindow value) {
    final bytes = value.bytes;
    if (bytes.isEmpty ||
        value.offset + bytes.length == value.availableThrough) {
      return bytes.length;
    }
    var start = bytes.length - 1;
    while (start > 0 &&
        bytes.length - start < 4 &&
        bytes[start] & 0xc0 == 0x80) {
      start--;
    }
    final lead = bytes[start];
    final expected = lead >= 0xc2 && lead <= 0xdf
        ? 2
        : lead >= 0xe0 && lead <= 0xef
        ? 3
        : lead >= 0xf0 && lead <= 0xf4
        ? 4
        : 1;
    return bytes.length - start < expected ? start : bytes.length;
  }

  void _pageLaidOut(int offset, double height) {
    if (!_displayActive) return;
    _pageHeights[offset] = height;
    final page = _pages.remove(offset);
    if (page != null) {
      _pages[offset] = page;
      _window = page;
    } else if (!_loading && _error == null) {
      unawaited(_load(offset));
    }
  }

  void _onExpansionChanged(bool expanded) {
    // This is read/diagnostic demand, not the ExpansionTile's UI state.
    _expanded = expanded;
    if (!expanded) {
      _unregister();
      if (_scrollable) {
        _request++;
        _window = null;
        _error = null;
        _loading = false;
        _clearPages();
      }
    } else {
      unawaited(_load(_window?.offset ?? 0));
    }
  }

  void _next() {
    final window = _window;
    if (window == null ||
        !_expanded ||
        _loading ||
        !(widget.isDisplayActive?.call() ?? true)) {
      return;
    }
    unawaited(_load(window.offset + window.bytes.length));
  }

  void _copy() {
    final window = _window;
    if (window == null ||
        !_expanded ||
        _loading ||
        !(widget.isDisplayActive?.call() ?? true)) {
      return;
    }
    final text = utf8.decode(window.bytes, allowMalformed: true);
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_scrollable) return _buildScrollable(context);
    if (TimelineBodyReadIntent.summaryOf(context)) {
      return widget.witness(
        _window == null
            ? ''
            : utf8.decode(_window!.bytes, allowMalformed: true),
        TimelineReasoningSummary(
          text:
              _error?.toString() ??
              (_window == null
                  ? ''
                  : utf8.decode(_window!.bytes, allowMalformed: true)),
        ),
      );
    }
    return TimelineContentRangeView(
      key: ValueKey(contentReferenceIdentity(widget.reference)),
      itemId: widget.itemId,
      contentKey: widget.contentKey,
      label: widget.label,
      initiallyExpanded: _immediate,
      disclosed: _immediate,
      loading: _loading,
      active: widget.isDisplayActive?.call() ?? true,
      canRead: widget.readContent != null,
      window: _window,
      error: _error,
      onExpansionChanged: _onExpansionChanged,
      onNext: _next,
      onCopy: _copy,
      witness: widget.witness,
      bodyBuilder: TimelineBodyReadIntent.bodyBuilderOf(context),
    );
  }

  Widget _buildScrollable(BuildContext context) {
    if (!_displayActive) return const SizedBox.shrink();
    final bodyBuilder = TimelineBodyReadIntent.bodyBuilderOf(context);
    final epoch = _scrollEpoch;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 1),
          if (_error != null) ...[
            Text(
              _error.toString(),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => unawaited(_load(_errorOffset ?? 0)),
              child: const Text('重试读取'),
            ),
          ],
          if (widget.readContent == null && _group?.readBody == null)
            const Text('内容读取尚未就绪')
          else
            Flexible(
              child: ListView.builder(
                key: ValueKey((widget.itemId, widget.contentKey, epoch)),
                primary: false,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                addAutomaticKeepAlives: false,
                itemCount: _pageOffsets.length,
                itemBuilder: (context, index) {
                  final offset = _pageOffsets[index];
                  final page = _pages[offset];
                  final text = page == null
                      ? null
                      : utf8.decode(
                          page.bytes.sublist(0, _textByteLength(page)),
                          allowMalformed: true,
                        );
                  return _TimelineScrollPage(
                    key: ValueKey(offset),
                    // At most three page slots can intersect the 320px view,
                    // including very short provider ranges. Complete short
                    // bodies keep their natural height.
                    minHeight: _pageOffsets.length > 1 ? 160 : 0,
                    placeholderHeight: _pageHeights[offset] ?? 160,
                    onLayout: (height) {
                      if (epoch == _scrollEpoch) _pageLaidOut(offset, height);
                    },
                    child: text == null
                        ? null
                        : widget.witness(
                            text,
                            KeyedSubtree(
                              key: index == 0
                                  ? StudioDriverKeys.timelineContentWindow(
                                      widget.itemId,
                                      widget.contentKey,
                                    )
                                  : ValueKey(('body-page', offset)),
                              child: bodyBuilder?.call(text) ?? Text(text),
                            ),
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Measures only mounted lazy children. Evicted pages retain their geometry so
/// returning through the official ListView does not collapse the scroll range.
class _TimelineScrollPage extends StatefulWidget {
  const _TimelineScrollPage({
    super.key,
    required this.minHeight,
    required this.placeholderHeight,
    required this.onLayout,
    this.child,
  });
  final double minHeight;
  final double placeholderHeight;
  final ValueChanged<double> onLayout;
  final Widget? child;

  @override
  State<_TimelineScrollPage> createState() => _TimelineScrollPageState();
}

class _TimelineScrollPageState extends State<_TimelineScrollPage> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLayout(context.size!.height);
    });
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: widget.child ?? SizedBox(height: widget.placeholderHeight),
    );
  }
}
