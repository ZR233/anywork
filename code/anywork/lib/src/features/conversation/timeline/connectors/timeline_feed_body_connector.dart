import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../state/timeline_display_unit.dart';
import '../widgets/timeline_content_range_view.dart';

class TimelineFeedContent extends InheritedWidget {
  const TimelineFeedContent({
    required this.identity,
    required this.isActive,
    required this.readBodyWindow,
    required super.child,
    super.key,
  });

  final Object identity;
  final bool Function() isActive;
  final Future<BodyWindow> Function(
    BodyRef, {
    required int offset,
    required int maxBytes,
  })
  readBodyWindow;

  static TimelineFeedContent? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TimelineFeedContent>();

  @override
  bool updateShouldNotify(TimelineFeedContent oldWidget) =>
      !identical(identity, oldWidget.identity);
}

class TimelineFeedBodyConnector extends StatefulWidget {
  const TimelineFeedBodyConnector({
    super.key,
    required this.itemId,
    required this.reference,
    required this.label,
    required this.witness,
    this.disclosed = false,
    this.showCopy = true,
    this.showInlineCopy = false,
    this.bodyBuilder,
    this.frameBody,
  });

  final String itemId;
  final BodyRef reference;
  final String label;
  final bool disclosed;
  final bool showCopy;
  final bool showInlineCopy;
  final Widget Function(String text)? bodyBuilder;
  final Widget Function(Widget body)? frameBody;
  final Widget Function(String text, Widget child) witness;

  @override
  State<TimelineFeedBodyConnector> createState() => _TimelineFeedBodyState();
}

class _TimelineFeedBodyState extends State<TimelineFeedBodyConnector> {
  TimelineFeedContent? _content;
  TimelineExpansionIntent? _group;
  Object? _groupGeneration;
  Object? _qualification;
  BodyWindow? _window;
  int _byteLength = 0;
  Object? _error;
  int _request = 0;
  bool _loading = false;
  bool _expanded = false;

  bool get _disclosed => widget.disclosed || TimelineBodyReadIntent.of(context);
  bool get _active =>
      mounted &&
      (_content?.isActive() ?? false) &&
      (_group == null ||
          _group!.bodyActive &&
              identical(_groupGeneration, _group!.bodyGeneration));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final content = TimelineFeedContent.of(context);
    final group = TimelineGroupBodyIntent.of(context);
    final qualification = TimelineBodyReadQualification.of(context);
    if (!identical(_group, group)) {
      _group?.removeListener(_groupChanged);
      _group = group;
      _groupGeneration = group?.bodyGeneration;
      group?.addListener(_groupChanged);
      _reset();
    }
    if (!identical(_content?.identity, content?.identity) ||
        !identical(_qualification, qualification)) {
      _reset();
    }
    _content = content;
    _qualification = qualification;
    _scheduleInitial();
  }

  void _groupChanged() {
    _groupGeneration = _group?.bodyGeneration;
    _reset();
    _scheduleInitial();
  }

  @override
  void dispose() {
    _group?.removeListener(_groupChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(TimelineFeedBodyConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) _reset();
    _scheduleInitial();
  }

  void _reset() {
    _request++;
    _window = null;
    _byteLength = 0;
    _error = null;
    _loading = false;
  }

  void _scheduleInitial() {
    if (!_active ||
        (!_disclosed && !_expanded) ||
        _window != null ||
        _error != null ||
        _loading) {
      return;
    }
    final request = _request;
    scheduleMicrotask(() {
      if (_active && request == _request && !_loading) unawaited(_read(0));
    });
  }

  Future<void> _read(int offset) async {
    final content = _content;
    if (!_active || content == null || _loading) return;
    final request = ++_request;
    final reference = widget.reference;
    final onRead = TimelineBodyReadIntent.onReadOf(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await content.readBodyWindow(
        reference,
        offset: offset,
        maxBytes: timelineBodyWindowMaxBytes,
      );
      if (!_active || request != _request) return;
      final encoded = value.bytesBase64;
      final bytes = encoded == null
          ? utf8.encode(value.text ?? '')
          : base64Decode(encoded);
      if (value.offset != offset || (!value.eof && bytes.isEmpty)) {
        throw StateError('Body window did not advance');
      }
      if (value.totalBytes != reference.byteLength ||
          bytes.length > timelineBodyWindowMaxBytes ||
          value.offset + bytes.length > value.totalBytes ||
          value.eof != (value.offset + bytes.length == value.totalBytes)) {
        throw StateError('Body window does not match its fixed reference');
      }
      setState(() {
        _window = value;
        _byteLength = bytes.length;
        _loading = false;
      });
      onRead?.call(value);
    } catch (error) {
      if (!_active || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    return TimelineContentRangeView(
      itemId: widget.itemId,
      contentKey: widget.reference.bodyKey,
      label: widget.label,
      disclosed: _disclosed,
      loading: _loading,
      active: _active,
      canRead: _active,
      window: window,
      error: _error,
      showInlineCopy: widget.showInlineCopy,
      bodyBuilder:
          TimelineBodyReadIntent.bodyBuilderOf(context) ?? widget.bodyBuilder,
      frameBody: widget.frameBody,
      witness: widget.witness,
      onExpansionChanged: (expanded) {
        _expanded = expanded;
        if (expanded && _window == null) unawaited(_read(0));
        if (!expanded && !_disclosed) setState(_reset);
      },
      onNext: window == null
          ? null
          : () => unawaited(_read(window.offset + _byteLength)),
      onCopy: window == null || !widget.showCopy
          ? null
          : () {
              unawaited(
                Clipboard.setData(
                  ClipboardData(
                    text:
                        window.text ??
                        utf8.decode(
                          base64Decode(window.bytesBase64 ?? ''),
                          allowMalformed: true,
                        ),
                  ),
                ),
              );
            },
    );
  }
}
