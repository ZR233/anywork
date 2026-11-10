import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../state/content_reference_identity.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_display_diagnostics.dart';
import '../widgets/timeline_content_range_view.dart';
import '../widgets/timeline_reasoning_view.dart';

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
  int _request = 0;
  VoidCallback? _unregisterDisplay;
  TimelineExpansionIntent? _group;
  Object? _groupGeneration;
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
    final group = TimelineGroupBodyIntent.of(context);
    if (!identical(group, _group)) {
      _group?.removeListener(_groupChanged);
      _group = group;
      _groupGeneration = group?.bodyGeneration;
      group?.addListener(_groupChanged);
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
    if (contentReferenceIdentity(oldWidget.reference) !=
        contentReferenceIdentity(widget.reference)) {
      _unregister();
      _request++;
      _window = null;
      _error = null;
      _loading = false;
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
    final groupRead = _group?.readBody;
    final generation = _groupGeneration;
    final read = groupRead == null
        ? widget.readContent
        : (ContentRef reference, ContentRange range) =>
              groupRead(generation!, reference, range);
    if (read == null ||
        _loading ||
        !_groupActive ||
        !(widget.isDisplayActive?.call() ?? true)) {
      return;
    }
    final request = ++_request;
    final reference = widget.reference;
    final isActive = widget.isDisplayActive;
    bool eligible() =>
        mounted &&
        _groupActive &&
        _expanded &&
        request == _request &&
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
        ContentRange(offset: offset, maxBytes: 64 * 1024),
      );
      if (!eligible()) return;
      setState(() => _window = value);
    } catch (error) {
      if (!eligible()) return;
      setState(() => _error = error);
    } finally {
      if (eligible()) setState(() => _loading = false);
    }
  }

  void _onExpansionChanged(bool expanded) {
    // This is read/diagnostic demand, not the ExpansionTile's UI state.
    _expanded = expanded;
    if (!expanded) {
      _unregister();
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
}
