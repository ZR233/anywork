import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../state/timeline_display_unit.dart';
import '../state/content_reference_identity.dart';
import '../widgets/timeline_content_range_view.dart';
import '../widgets/timeline_reasoning_view.dart';

/// Reads a body through the Current or History owner of the enclosing renderer.
/// The disclosure generation revokes every request and watch at the same owner.
class TimelineOwnedBodyConnector extends StatefulWidget {
  const TimelineOwnedBodyConnector({
    required this.itemId,
    required this.contentKey,
    required this.label,
    required this.witness,
    this.historyReference,
    this.currentReference,
    this.disclosed = false,
    this.showCopy = true,
    this.bodyBuilder,
    this.frameBody,
    super.key,
  }) : assert(
         (historyReference == null) != (currentReference == null),
         'exactly one body owner is required',
       );

  final String itemId;
  final String contentKey;
  final String label;
  final HistoryEventBodyRef? historyReference;
  final CurrentContentRef? currentReference;
  final bool disclosed;
  final bool showCopy;
  final Widget Function(String text)? bodyBuilder;
  final Widget Function(Widget body)? frameBody;
  final Widget Function(String text, Widget child) witness;

  @override
  State<TimelineOwnedBodyConnector> createState() =>
      _TimelineOwnedBodyConnectorState();
}

class _TimelineOwnedBodyConnectorState
    extends State<TimelineOwnedBodyConnector> {
  static const _windowBytes = 64 * 1024;

  TimelineExpansionIntent? _intent;
  Object? _generation;
  CurrentBodyWatch? _watch;
  // ignore: cancel_subscriptions
  StreamSubscription<ContentWindow>? _subscription;
  Future<void>? _watchCancellation;
  ContentWindow? _window;
  Object? _error;
  bool _loading = false;
  bool _declaredRead = false;
  int _request = 0;
  ContentWindow? _reportedWindow;
  ValueChanged<ContentWindow>? _reportedRead;
  Object? _reportedQualification;

  bool get _active =>
      mounted &&
      _intent != null &&
      _intent!.bodyActive &&
      identical(_generation, _intent!.bodyGeneration) &&
      _intent!.current != null &&
      !_intent!.isRetired;

  @override
  void didUpdateWidget(covariant TimelineOwnedBodyConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    Object? identity(TimelineOwnedBodyConnector value) =>
        value.historyReference != null
        ? historyBodyIdentity(value.historyReference!)
        : currentContentIdentity(value.currentReference!);
    if (identity(oldWidget) != identity(widget)) {
      _cancel();
      _changed();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TimelineGroupBodyIntent.of(context);
    final declared = widget.disclosed || TimelineBodyReadIntent.of(context);
    if (identical(next, _intent)) {
      if (declared && !_declaredRead) {
        _declaredRead = true;
        _changed();
      }
      return;
    }
    _intent?.removeListener(_changed);
    _cancel();
    _intent = next;
    _generation = next?.bodyGeneration;
    _declaredRead = declared;
    next?.addListener(_changed);
    _changed();
  }

  void _changed() {
    final nextGeneration = _intent?.bodyGeneration;
    if (!identical(nextGeneration, _generation)) {
      _generation = nextGeneration;
      _cancel();
      if (mounted) setState(() {});
    }
    if (!_active) {
      _cancel();
      return;
    }
    if (widget.historyReference case final history?) {
      final initial = TimelineInitialBodyReads.read(context, history);
      if (_window == null && _error == null && initial != null) {
        _window = initial.data;
        _error = initial.error;
      }
      if (_window != null || _error != null) return;
    }
    if (_watch == null && !_loading && _error == null) {
      unawaited(_start(_declaredRead));
    }
  }

  Future<void> _start(bool disclosed) async {
    if (!disclosed || !_active) return;
    final history = widget.historyReference;
    if (history != null) {
      await _loadHistory(0);
      return;
    }
    await _openCurrent(0);
  }

  Future<void> _loadHistory(int offset) async {
    final intent = _intent;
    final reference = widget.historyReference;
    if (!_active || intent?.readHistoryBody == null || reference == null) {
      return;
    }
    final request = ++_request;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final window = await intent!.readHistoryBody!(
        generation!,
        reference,
        ContentRange(offset: offset, maxBytes: _windowBytes),
      );
      if (!_eligible(request, generation)) return;
      setState(() {
        _window = window;
        _loading = false;
      });
    } catch (error) {
      if (!_eligible(request, generation)) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openCurrent(int offset) async {
    final intent = _intent;
    final reference = widget.currentReference;
    if (!_active || intent?.watchCurrentBody == null || reference == null) {
      return;
    }
    final request = ++_request;
    final generation = _generation;
    await _closeWatch();
    if (!_eligible(request, generation)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final watch = intent!.watchCurrentBody!(
        generation!,
        reference,
        ContentRange(offset: offset, maxBytes: _windowBytes),
      );
      _watch = watch;
      _subscription = watch.windows.listen(
        (window) {
          if (!_eligible(request, generation)) return;
          setState(() {
            _window = window;
            _loading = false;
          });
        },
        onError: (Object error, StackTrace _) {
          if (!_eligible(request, generation)) return;
          setState(() {
            _error = error;
            _loading = false;
          });
          unawaited(_closeWatch());
        },
        onDone: () {
          if (mounted && _eligible(request, generation)) {
            setState(() => _loading = false);
          }
        },
      );
    } catch (error) {
      if (!_eligible(request, generation)) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  bool _eligible(int request, Object? generation) =>
      _active && request == _request && identical(generation, _generation);

  Future<void> _closeWatch() async {
    final watch = _watch;
    _watch = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _watchCancellation ??= subscription.cancel();
    }
    if (watch != null) {
      watch.requestClose();
      await watch.close();
    }
    final cancellation = _watchCancellation;
    _watchCancellation = null;
    if (cancellation != null) await cancellation;
  }

  void _cancel() {
    _request++;
    _window = null;
    _error = null;
    _loading = false;
    unawaited(_closeWatch());
  }

  void _next() {
    final window = _window;
    if (window == null || window.bytes.isEmpty) return;
    final offset = window.offset + window.bytes.length;
    if (offset >= window.availableThrough) return;
    if (widget.historyReference != null) {
      unawaited(_loadHistory(offset));
    } else {
      unawaited(_openCurrent(offset));
    }
  }

  Future<void> _copy() async {
    final window = _window;
    if (window == null) return;
    await Clipboard.setData(
      ClipboardData(text: utf8.decode(window.bytes, allowMalformed: true)),
    );
  }

  @override
  void dispose() {
    _intent?.removeListener(_changed);
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onRead = TimelineBodyReadIntent.onReadOf(context);
    final qualification = TimelineBodyReadQualification.of(context);
    final window = _window;
    if (window != null &&
        onRead != null &&
        (!identical(window, _reportedWindow) ||
            onRead != _reportedRead ||
            !identical(qualification, _reportedQualification))) {
      _reportedWindow = window;
      _reportedRead = onRead;
      _reportedQualification = qualification;
      // A semantic reader may update its enclosing card. Publish after layout,
      // and retain the same body/disclosure qualification as the read itself.
      final generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_active &&
            identical(generation, _generation) &&
            identical(window, _window) &&
            onRead == TimelineBodyReadIntent.onReadOf(context) &&
            identical(
              qualification,
              TimelineBodyReadQualification.of(context),
            )) {
          onRead(window);
        }
      });
    }
    if (TimelineBodyReadIntent.summaryOf(context)) {
      // A summary is part of the member header, not a document window.
      // Keep the existing read and layout witness, but no range or actions.
      final text = window == null
          ? ''
          : utf8.decode(window.bytes, allowMalformed: true);
      final label = text.trim().isEmpty ? widget.label : text;
      final summary = Tooltip(
        message: _error == null ? label : '$label\n$_error',
        child: TimelineReasoningSummary(text: label),
      );
      return window == null ? summary : widget.witness(text, summary);
    }
    final end = _window == null ? 0 : _window!.offset + _window!.bytes.length;
    final canNext =
        _window != null &&
        end < _window!.availableThrough &&
        !_loading &&
        _error == null;
    return TimelineContentRangeView(
      itemId: widget.itemId,
      contentKey: widget.contentKey,
      label: widget.label,
      disclosed: widget.disclosed || TimelineBodyReadIntent.of(context),
      loading: _loading,
      active: _active,
      canRead:
          _intent?.readHistoryBody != null || _intent?.watchCurrentBody != null,
      window: _window,
      error: _error,
      onExpansionChanged: (expanded) {
        if (expanded) {
          _declaredRead = true;
          unawaited(_start(true));
        }
      },
      onNext: canNext ? _next : null,
      onCopy: widget.showCopy && window != null
          ? () => unawaited(_copy())
          : null,
      witness: widget.witness,
      bodyBuilder:
          widget.bodyBuilder ?? TimelineBodyReadIntent.bodyBuilderOf(context),
      frameBody: widget.frameBody,
    );
  }
}
