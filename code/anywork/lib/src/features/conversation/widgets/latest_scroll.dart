import 'dart:async';

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_ui/material_ui.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../shared/studio_driver_keys.dart';

class LatestScrollScope extends StatefulWidget {
  const LatestScrollScope({super.key, required this.child});

  final Widget child;

  @override
  State<LatestScrollScope> createState() => _LatestScrollScopeState();
}

class _LatestScrollScopeState extends State<LatestScrollScope> {
  final _viewports = <LatestScrollViewportState>{};
  final _status = ValueNotifier((paused: false, hasNewOutput: false));
  bool _scheduled = false;

  void _scheduleStatus() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final paused = _viewports.where((viewport) => viewport._canResume);
      _status.value = (
        paused: paused.isNotEmpty,
        hasNewOutput: paused.any((viewport) => viewport.widget.hasNewOutput),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _resume() {
    for (final viewport in _viewports.toList()) {
      unawaited(viewport.requestLatest());
    }
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LatestScrollHost(state: this, child: widget.child);
}

class _LatestScrollHost extends InheritedWidget {
  const _LatestScrollHost({required this.state, required super.child});

  final _LatestScrollScopeState state;

  static _LatestScrollScopeState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LatestScrollHost>()?.state;

  @override
  bool updateShouldNotify(_LatestScrollHost oldWidget) =>
      !identical(state, oldWidget.state);
}

class ReturnToLatestButton extends StatelessWidget {
  const ReturnToLatestButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = _LatestScrollHost.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    return SelectionContainer.disabled(
      child: ValueListenableBuilder(
        valueListenable: scope._status,
        builder: (context, status, _) => ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (MediaQuery.textScalerOf(context).scale(20) + 16).clamp(
              kMinInteractiveDimension,
              double.infinity,
            ),
          ),
          child: status.paused
              ? Center(
                  child: FilledButton.tonalIcon(
                    key: StudioDriverKeys.timelineReturnLatest,
                    onPressed: scope._resume,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                    label: Text(
                      status.hasNewOutput
                          ? l10n.timelineJumpToLatestWithNewOutput
                          : l10n.timelineJumpToLatest,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class LatestScrollViewport extends StatefulWidget {
  const LatestScrollViewport({
    super.key,
    required this.controller,
    this.latestAtStart = false,
    this.enabled = true,
    this.isActive,
    this.historyPaused = false,
    this.hasNewOutput = false,
    this.onPause,
    this.onResume,
    this.onUserScroll,
    this.onMetricsChanged,
    this.onClearSelection,
    required this.child,
  });

  final ScrollController controller;
  final bool latestAtStart;
  final bool enabled;
  final bool Function()? isActive;
  final bool historyPaused;
  final bool hasNewOutput;
  final VoidCallback? onPause;
  final Future<bool> Function()? onResume;
  final ValueChanged<ScrollUpdateNotification>? onUserScroll;
  final VoidCallback? onMetricsChanged;
  final VoidCallback? onClearSelection;
  final Widget child;

  @override
  State<LatestScrollViewport> createState() => LatestScrollViewportState();
}

class LatestScrollViewportState extends State<LatestScrollViewport> {
  static const _edgeTolerance = 0.5;

  _LatestScrollScopeState? _scope;
  bool _tickersEnabled = true;
  bool _paused = false;
  bool _selected = false;
  bool _actionIntent = false;
  bool _restoring = false;
  bool _followScheduled = false;
  int _intent = 0;
  (double, double, double)? _dimensions;

  bool get _active =>
      mounted &&
      widget.enabled &&
      _tickersEnabled &&
      (widget.isActive?.call() ?? true);
  bool get _isPaused => _paused || widget.historyPaused;
  bool get _canResume => _active && _isPaused;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    if (!_active && _restoring) _pause();
    final scope = _LatestScrollHost.maybeOf(context);
    if (!identical(scope, _scope)) {
      _unregister();
      _scope = scope;
      scope?._viewports.add(this);
    }
    _scope?._scheduleStatus();
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(covariant LatestScrollViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      widget.controller,
      oldWidget.controller,
    );
    if (controllerChanged || !widget.enabled && oldWidget.enabled) {
      _intent++;
      _restoring = false;
      _paused = false;
      _selected = false;
      _actionIntent = false;
      _dimensions = null;
    } else if (!_active && _restoring) {
      _pause();
    }
    _scope?._scheduleStatus();
    if (controllerChanged || widget.enabled && !oldWidget.enabled) {
      _scheduleFollow();
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  void _unregister() {
    final scope = _scope;
    scope?._viewports.remove(this);
    scope?._scheduleStatus();
  }

  double _latestEdge(ScrollMetrics metrics) =>
      widget.latestAtStart ? metrics.minScrollExtent : metrics.maxScrollExtent;

  bool _atLatest(ScrollMetrics metrics) =>
      (widget.latestAtStart ? metrics.extentBefore : metrics.extentAfter) <=
      _edgeTolerance;

  void _runScrollAction(VoidCallback action) {
    _actionIntent = true;
    action();
    final controller = widget.controller;
    _actionIntent =
        controller.hasClients && controller.position.isScrollingNotifier.value;
  }

  void setSelection(bool selected) {
    if (_selected == selected) return;
    _selected = selected;
    if (selected && _active) _pause();
  }

  void _pause() {
    if (_paused && !_restoring) return;
    _paused = true;
    _intent++;
    _restoring = false;
    widget.onPause?.call();
    _scope?._scheduleStatus();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !_active) return false;
    if (notification is ScrollEndNotification) {
      _actionIntent = false;
    }
    final scroll = widget.controller;
    if (notification is! ScrollUpdateNotification ||
        !scroll.hasClients ||
        (notification.dragDetails == null &&
            scroll.position.userScrollDirection == ScrollDirection.idle &&
            !_actionIntent)) {
      return false;
    }
    final metrics = notification.metrics;
    final delta = notification.scrollDelta ?? 0;
    final towardLatest = widget.latestAtStart ? delta < 0 : delta > 0;
    if (towardLatest && _atLatest(metrics) && !_selected) {
      unawaited(requestLatest());
    } else if (delta != 0 && !towardLatest && !_atLatest(metrics)) {
      _pause();
    }
    widget.onUserScroll?.call(notification);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    final dimensions = (
      metrics.minScrollExtent,
      metrics.maxScrollExtent,
      metrics.viewportDimension,
    );
    if (dimensions == _dimensions) return false;
    _dimensions = dimensions;
    final scroll = widget.controller;
    if (!scroll.hasClients || !scroll.position.isScrollingNotifier.value) {
      _actionIntent = false;
    }
    widget.onMetricsChanged?.call();
    _scope?._scheduleStatus();
    _scheduleFollow();
    return false;
  }

  Future<void> requestLatest({bool force = false}) async {
    if (!_active || (!force && !_isPaused)) return;
    // The submission is already laid out at the latest edge. Reveal it while
    // the history owner resolves the new live window.
    if (force) _alignLatest();
    if (_restoring) return;
    final intent = ++_intent;
    _restoring = true;
    try {
      final resume = widget.onResume;
      if (resume != null && !await resume()) return;
      if (!_active || intent != _intent) return;
      if (_selected) widget.onClearSelection?.call();
      _selected = false;
      _paused = false;
      _scheduleFollow(explicit: true);
    } finally {
      if (intent == _intent) _restoring = false;
      _scope?._scheduleStatus();
    }
  }

  void _scheduleFollow({bool explicit = false}) {
    // The reversed list stays at its stable minimum as new rows arrive.
    if (!_active ||
        _followScheduled ||
        (!explicit && (_isPaused || widget.latestAtStart))) {
      return;
    }
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (_active && !_isPaused) _alignLatest();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _alignLatest() {
    final scroll = widget.controller;
    if (!scroll.hasClients) return;
    final position = scroll.position;
    if (position.hasContentDimensions &&
        position.viewportDimension > 0 &&
        !_atLatest(position)) {
      position.jumpTo(_latestEdge(position));
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      ScrollIntent: _UserScrollAction(
        controller: widget.controller,
        runScrollAction: _runScrollAction,
      ),
    },
    child: PrimaryScrollController(
      controller: widget.controller,
      automaticallyInheritForPlatforms: const <TargetPlatform>{},
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: _UserScrollbar(
              controller: widget.controller,
              runScrollAction: _runScrollAction,
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}

// ScrollAction uses a driven scroll activity. Mark the user input before
// delegating to Flutter so its updates are distinguishable from layout changes.
class _UserScrollAction extends ScrollAction {
  _UserScrollAction({required this.controller, required this.runScrollAction});

  final ScrollController controller;
  final void Function(VoidCallback) runScrollAction;

  @override
  void invoke(ScrollIntent intent, [BuildContext? context]) {
    if (context == null ||
        axisDirectionToAxis(intent.direction) != Axis.vertical) {
      super.invoke(intent, context);
      return;
    }
    final target = Scrollable.maybeOf(context);
    if (!controller.hasClients ||
        (target != null && !identical(target.position, controller.position))) {
      super.invoke(intent, context);
      return;
    }
    runScrollAction(() => super.invoke(intent, context));
  }
}

class _UserScrollbar extends RawScrollbar {
  const _UserScrollbar({
    required super.controller,
    required this.runScrollAction,
    required super.child,
  });

  final void Function(VoidCallback) runScrollAction;

  @override
  RawScrollbarState<RawScrollbar> createState() => _UserScrollbarState();
}

class _UserScrollbarState extends RawScrollbarState<RawScrollbar> {
  @override
  void handleTrackTapDown(TapDownDetails details) {
    (widget as _UserScrollbar).runScrollAction(
      () => super.handleTrackTapDown(details),
    );
  }
}
