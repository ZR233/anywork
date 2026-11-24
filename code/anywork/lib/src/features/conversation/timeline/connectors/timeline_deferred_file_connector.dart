import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../platform/local_file_dialogs.dart';
import 'timeline_file_download.dart';

class TimelineDeferredFileState {
  const TimelineDeferredFileState({
    this.progress,
    this.selecting = false,
    this.completed = false,
    this.paused = false,
    this.error,
    this.onDownload,
    this.onPauseOrResume,
    this.onStop,
  });

  final double? progress;
  final bool selecting;
  final bool completed;
  final bool paused;
  final String? error;
  final VoidCallback? onDownload;
  final VoidCallback? onPauseOrResume;
  final VoidCallback? onStop;
}

class TimelineDeferredFileConnector extends StatefulWidget {
  const TimelineDeferredFileConnector({
    super.key,
    required this.itemId,
    required this.index,
    required this.filename,
    required this.size,
    required this.isActive,
    required this.builder,
  });

  final String itemId;
  final int index;
  final String filename;
  final int size;
  final bool Function() isActive;
  final Widget Function(TimelineDeferredFileState) builder;

  @override
  State<TimelineDeferredFileConnector> createState() =>
      _TimelineDeferredFileConnectorState();
}

class _DownloadAttempt {
  _DownloadAttempt(this.transfer);

  final TimelineFileDownload transfer;
  StreamSubscription<int>? subscription;
  Future<void>? stopping;
  int written = 0;
  bool paused = false;
  bool changingPause = false;
}

class _TimelineDeferredFileConnectorState
    extends State<TimelineDeferredFileConnector> {
  TimelineFileDownloadScope? _scope;
  Object? _selection;
  _DownloadAttempt? _attempt;
  bool _completed = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TimelineFileDownloadScope.maybeOf(context);
    if (_scope?.start != next?.start ||
        _scope?.pickSavePath != next?.pickSavePath) {
      _retire();
    }
    _scope = next;
  }

  @override
  void didUpdateWidget(covariant TimelineDeferredFileConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemId != oldWidget.itemId ||
        widget.index != oldWidget.index ||
        widget.filename != oldWidget.filename ||
        widget.size != oldWidget.size ||
        !widget.isActive()) {
      _retire();
    }
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  void _retire() {
    _selection = null;
    final attempt = _attempt;
    _attempt = null;
    _completed = false;
    _error = null;
    if (attempt != null) {
      unawaited(attempt.subscription?.cancel());
      if (attempt.stopping == null) unawaited(_stop(attempt));
    }
  }

  bool _owns(_DownloadAttempt attempt) =>
      mounted && identical(_attempt, attempt);

  bool _currentSelection(Object selection) =>
      mounted && identical(_selection, selection) && widget.isActive();

  Future<void> _download() async {
    final scope = _scope;
    if (scope == null ||
        _selection != null ||
        _attempt != null ||
        !widget.isActive()) {
      return;
    }
    final selection = Object();
    setState(() {
      _selection = selection;
      _completed = false;
      _error = null;
    });
    try {
      final path = await (scope.pickSavePath ?? pickLocalSavePath)(
        widget.filename,
      );
      if (path == null || !_currentSelection(selection)) return;
      final attempt = _DownloadAttempt(
        scope.start(
          itemId: widget.itemId,
          index: widget.index,
          destination: path,
        ),
      );
      setState(() => _attempt = attempt);
      unawaited(_observeFinished(attempt));
      attempt.subscription = attempt.transfer.progress.listen(
        (written) {
          if (_owns(attempt) && widget.isActive()) {
            setState(() => attempt.written = written);
          }
        },
        onError: (Object _, StackTrace _) {
          // The transfer's terminal failure is reported through finished.
        },
      );
    } catch (error) {
      if (_currentSelection(selection)) setState(() => _error = '$error');
    } finally {
      if (mounted && identical(_selection, selection)) {
        setState(() => _selection = null);
      }
    }
  }

  Future<void> _observeFinished(_DownloadAttempt attempt) async {
    Object? failure;
    try {
      await attempt.transfer.finished;
    } catch (error) {
      failure = error;
    }
    // Stop may still be cleaning up when the transfer reports its termination.
    final stopping = attempt.stopping;
    var stopped = false;
    if (stopping != null) {
      try {
        await stopping;
        stopped = true;
      } catch (_) {
        // A failed stop does not suppress an independent transfer failure.
      }
    }
    if (!_owns(attempt)) return;
    unawaited(attempt.subscription?.cancel());
    setState(() {
      _attempt = null;
      _completed = widget.isActive() && failure == null;
      _error = widget.isActive() && !stopped && failure != null
          ? '$failure'
          : null;
    });
  }

  Future<void> _togglePause(_DownloadAttempt attempt) async {
    if (!_owns(attempt) ||
        !widget.isActive() ||
        attempt.changingPause ||
        attempt.stopping != null) {
      return;
    }
    setState(() {
      attempt.changingPause = true;
      _error = null;
    });
    try {
      if (attempt.paused) {
        await attempt.transfer.resume();
      } else {
        await attempt.transfer.pause();
      }
      if (_owns(attempt)) setState(() => attempt.paused = !attempt.paused);
    } catch (error) {
      if (_owns(attempt)) setState(() => _error = '$error');
    } finally {
      if (_owns(attempt)) setState(() => attempt.changingPause = false);
    }
  }

  Future<void> _stop(_DownloadAttempt attempt) async {
    if (attempt.stopping != null) return;
    final stopping = Future<void>.sync(attempt.transfer.stop);
    attempt.stopping = stopping;
    if (_owns(attempt)) setState(() => _error = null);
    try {
      await stopping;
    } catch (error) {
      attempt.stopping = null;
      if (_owns(attempt)) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    final active = widget.isActive();
    return widget.builder(
      TimelineDeferredFileState(
        progress: attempt == null
            ? null
            : widget.size == 0
            ? 0
            : attempt.written.clamp(0, widget.size) / widget.size,
        selecting: _selection != null,
        completed: _completed,
        paused: attempt?.paused ?? false,
        error: _error,
        onDownload:
            active && _scope != null && attempt == null && _selection == null
            ? () => unawaited(_download())
            : null,
        onPauseOrResume:
            active &&
                attempt != null &&
                !attempt.changingPause &&
                attempt.stopping == null
            ? () => unawaited(_togglePause(attempt))
            : null,
        onStop: active && attempt != null && attempt.stopping == null
            ? () => unawaited(_stop(attempt))
            : null,
      ),
    );
  }
}
