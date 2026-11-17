import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show Key, ValueKey, ValueNotifier;
import 'package:flutter/widgets.dart' show ScrollController, WidgetsBinding;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/live_status/live_status_state.dart'
    show LiveStatusView;
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_display_diagnostics.dart';
import '../../features/conversation/timeline/state/timeline_display_unit.dart';
import '../../features/conversation/timeline/state/timeline_history_projection.dart';
import '../../features/conversation/timeline/state/timeline_current_projection.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/view_models/timeline_message_controller.dart';

export '../../features/conversation/timeline/state/timeline_view_state.dart';

const Object _unset = Object();

ClientResourceId _newTimelineResourceId() {
  final random = Random.secure();
  final identity = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return ClientResourceId(identity, 0);
}

/// Component futures may fail after a partial mutation. Their response cannot be replayed.
final class _TimelineApplyFailure implements Exception {
  const _TimelineApplyFailure(this.cause);
  final Object cause;
}

/// One presentation generation. Only its component controller owns loaded messages.
final class TimelineDisplayLease implements TimelineUiControllers {
  TimelineDisplayLease({
    required this.threadId,
    required this.generation,
    required this.demand,
    required this.history,
    required this.current,
    this.selectionId,
    this.selectionStartedMicros,
  }) : _controller = InMemoryChatController(),
       imageResources = TimelineImageResources(threadId: threadId) {
    _presentation = TimelineMessageController(
      _controller!,
      generation: generation,
      onUnitCreated: _bindUnit,
      onUnitRetired: _retireUnit,
      expansionForBlock: expansionForBlock,
    );
    _historyQueries = openHistoryScope();
    _currentQueries = openCurrentScope();
  }

  final ClientResourceId resourceId = _newTimelineResourceId();

  @override
  final String threadId;
  final int generation;
  final ReadDemand demand;
  late final int _historyRowLimit = max(demand.maxItems * 8, 128);
  final HistoryReader history;
  final CurrentReader current;
  LiveStatusView? liveStatus;
  final int? selectionId;
  final int? selectionStartedMicros;
  final TimelineImageResources imageResources;
  InMemoryChatController? _controller;
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  TimelineMessageController? _presentation;
  final Set<TimelineGroupDisplay> _groupDisplays = {};
  final Completer<void> _released = Completer<void>();
  final ValueNotifier<bool> retirement = ValueNotifier(false);
  final ValueNotifier<Object?> currentCollectionError = ValueNotifier(null);

  /// Published only by this display's serial admission, never directly by the transport.
  final ValueNotifier<CurrentRunSnapshot?> live = ValueNotifier(null);
  final Map<String, TimelineExpansionIntent> _expansions = {};
  final Set<String> _terminalHistoryEntities = {};
  final Set<Object> _ownedQueries = {};
  final Map<Object, Future<void>> _closingQueries = {};
  final Map<Object, (Object, StackTrace?)> _queryCleanupErrors = {};
  HistoryReadScope? _historyQueries;
  CurrentReadScope? _currentQueries;
  CurrentProjection? _latestCurrentProjection;
  CurrentRevision? _latestCurrentRevision;
  CurrentCollectionRef? _atomCollection;
  CurrentCollectionRef? _sourceCollection;
  List<CurrentAtom> _loadedCurrentAtoms = const [];
  List<ChatSourceState> _loadedCurrentSources = const [];
  String? _currentAtomsContinuation;
  String? _currentSourcesContinuation;
  Future<void>? _currentAtomsLoading;
  Future<void>? _currentSourcesLoading;
  CurrentCollectionRef? _currentAtomsLoadingRef;
  CurrentCollectionRef? _currentSourcesLoadingRef;
  String? _before;
  int? _firstOrder;
  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  bool _hasOlder = false;
  bool _mounted = false;
  bool _retired = false;
  bool _disposed = false;
  int _mutations = 0;
  Object? get queryCleanupError {
    if (_queryCleanupErrors.isEmpty) return null;
    if (_queryCleanupErrors.length == 1) {
      final error = _queryCleanupErrors.values.single.$1;
      if (error is! CloseReport) return error;
    }
    return _queryCleanupReport;
  }

  CloseReport get _queryCleanupReport => CloseReport(
    unresolved: [
      for (final scope in _ownedQueries) ...[
        // A retained scope's live snapshot supersedes an earlier close report.
        if (_queryCleanupErrors[scope] case (final CloseReport report, _)) ...[
          ...report.unresolved,
        ] else if (_queryCleanupErrors[scope] case (final error, final stack))
          UnresolvedResource(
            resourceId: resourceId,
            owner: 'timeline-display:$threadId',
            attemptId: AttemptId(generation),
            reason: error,
            ownership: ClientOwnership.owned,
            stages: [
              ClientResourceStage(
                owner: 'timeline-display:$threadId',
                phase: ClientClosePhase.close,
                ownership: ClientOwnership.owned,
                error: error,
                stackTrace: stack,
              ),
            ],
          ),
      ],
    ],
  );
  final Set<TimelineChildrenDisplay> _childrenDisplays = {};
  final Set<TimelineCurrentDisplay> _currentDisplays = {};
  TimelineContentLayout? _firstContentLayout;
  int _appliedSets = 0;
  int _appliedPrepends = 0;
  int _appliedAppends = 0;

  TimelineContentLayout? get firstContentLayout => _firstContentLayout;
  int get appliedSets => _appliedSets;
  int get appliedPrepends => _appliedPrepends;
  int get appliedAppends => _appliedAppends;
  TimelineExpansionIntent expansionForBlock(String blockId) =>
      _expansions.putIfAbsent(blockId, TimelineExpansionIntent.new);
  bool isBlockExpanded(String blockId) =>
      _expansions[blockId]?.expanded ?? false;
  void setBlockExpanded(String blockId, bool expanded) {
    if (_retired) return;
    expansionForBlock(blockId).expanded = expanded;
  }

  TimelineDisplayUnit liveUnit(LiveDisplayBlock block, bool executionPresent) {
    final unit = TimelineDisplayUnit.live(
      block: block,
      executionPresent: executionPresent,
      expansion: expansionForBlock(block.id),
    );
    unit.expansion.current = unit;
    _bindUnit(unit);
    return unit;
  }

  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) async {
    final scope = _historyQueries;
    if (scope == null || _retired) {
      throw const StaleConversationScope();
    }
    return HistoryGroupMembers.open(
      scope,
      reference: reference,
      window: window,
      demand: demand,
      currentAtoms: () {
        final direct = _latestCurrentProjection?.atoms ?? const <CurrentAtom>[];
        return direct.isNotEmpty ? direct : _loadedCurrentAtoms;
      },
      currentOwnerId: () => _latestCurrentRevision?.ownerId,
    );
  }

  Iterable<TimelineGroupDisplay> get groupDisplays => _retired
      ? const []
      : _groupDisplays.where((display) => display.isCurrent);

  void _bindUnit(TimelineDisplayUnit unit) {
    final intent = unit.expansion;
    // The same disclosure capability crosses live/history parents. Its queries
    // and callbacks are installed once, independent of header replacements.
    if (intent.isDisplayActive != null) return;
    intent.readHistoryBody = (generation, reference, range) async {
      final scope = _historyQueries;
      if (_retired ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration) ||
          scope == null ||
          !scope.isActive) {
        throw const StaleConversationScope();
      }
      final value = await scope.readBody(
        reference: reference,
        offset: range.offset,
        maxBytes: range.maxBytes,
      );
      if (_retired ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration) ||
          !scope.isActive) {
        throw const StaleConversationScope();
      }
      return ContentWindow(
        offset: value.offset,
        bytes: value.bytes,
        generation:
            '${reference.bodyId}:${reference.byteStart}:${reference.byteLength}',
        availableThrough: value.totalLength,
        sealed: true,
      );
    };
    intent.readCurrentBody = (generation, reference, range) async {
      final scope = _currentQueries;
      if (_retired ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration) ||
          scope == null ||
          !scope.isActive) {
        throw const StaleConversationScope();
      }
      final value = await scope.readBody(reference: reference, range: range);
      if (_retired ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration) ||
          !scope.isActive) {
        throw const StaleConversationScope();
      }
      return value;
    };
    intent.watchCurrentBody = (generation, reference, range) {
      final scope = _currentQueries;
      if (_retired ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration) ||
          scope == null ||
          !scope.isActive) {
        throw const StaleConversationScope();
      }
      return scope.watchBody(reference: reference, range: range);
    };
    intent.isDisplayActive = () => !_retired && intent.current != null;
    intent.registerDisplay = (display) {
      if (_retired) return () {};
      _groupDisplays.add(display);
      return () => _groupDisplays.remove(display);
    };
    intent.openDisplayMembers = (reference, window, demand) {
      if (_retired || intent.isRetired || !intent.bodyActive) {
        throw const StaleConversationScope();
      }
      return openDisplayMembers(
        reference: reference,
        window: window,
        demand: demand,
      );
    };
  }

  void _retireUnit(TimelineDisplayUnit unit) {
    _groupDisplays.removeWhere((display) => display.unitId == unit.id);
  }

  Iterable<TimelineChildrenDisplay> get childrenDisplays sync* {
    if (_retired) return;
    for (final display in _childrenDisplays) {
      if (display.isCurrent) yield display;
    }
  }

  /// Registers only a resource borrow. It neither opens a Children scope nor copies messages.
  void Function() registerChildrenDisplay(TimelineChildrenDisplay display) {
    if (_retired) return () {};
    _childrenDisplays.add(display);
    return () => _childrenDisplays.remove(display);
  }

  Iterable<TimelineCurrentDisplay> get currentDisplays sync* {
    if (_retired) return;
    for (final display in _currentDisplays) {
      if (display.isCurrent) yield display;
    }
  }

  /// Borrows one mounted resource. Enumeration never opens its read scope.
  void Function() registerCurrentDisplay(TimelineCurrentDisplay display) {
    if (_retired) return () {};
    _currentDisplays.add(display);
    return () => _currentDisplays.remove(display);
  }

  void _recordBatch(TimelineApplyPlacement placement) {
    switch (placement) {
      case TimelineApplyPlacement.set:
        _appliedSets++;
      case TimelineApplyPlacement.prepend:
        _appliedPrepends++;
      case TimelineApplyPlacement.append:
        _appliedAppends++;
    }
  }

  @override
  Key get chatKey => ValueKey('timeline-chat:$threadId:$generation');
  @override
  ChatController get controller =>
      _controller ?? (throw StateError('Timeline display is released'));
  @override
  ScrollController get scrollController => _scrollController;
  @override
  bool get isRetired => _retired;
  bool get isMounted => _mounted;
  bool get isReleased => _released.isCompleted;
  TimelineDisplayMode get mode => _mode;
  String? get olderCursor => _before;
  bool get hasOlder => _hasOlder;
  int get loadedCount => _controller?.messages.length ?? 0;
  Future<void> get released => _released.future;

  HistoryReadScope openHistoryScope({int? generation}) {
    if (_retired) throw const StaleConversationScope();
    final scope = HistoryReadScope(
      threadId: threadId,
      generation: generation ?? this.generation,
      reader: history,
      isEligible: () => !_retired,
    );
    _ownedQueries.add(scope);
    return scope;
  }

  CurrentReadScope openCurrentScope({int? generation}) {
    if (_retired) throw const StaleConversationScope();
    final scope = CurrentReadScope(
      threadId: threadId,
      generation: generation ?? this.generation,
      reader: current,
      isEligible: () => !_retired,
    );
    _ownedQueries.add(scope);
    return scope;
  }

  @override
  void bind() {
    if (_disposed) throw StateError('Timeline display was already released');
    _mounted = true;
  }

  @override
  Future<void> unbind() {
    _mounted = false;
    _releaseIfReady();
    return _released.future;
  }

  /// The controller cannot be disposed while an accepted public operation is
  /// settling, including a selection change re-entered from an operation stream.
  Future<T> _mutate<T>(Future<T> Function() operation) async {
    if (_retired) throw StateError('Timeline display is retired');
    _mutations++;
    try {
      return await operation();
    } finally {
      _mutations--;
      _releaseIfReady();
    }
  }

  Future<void> retire() {
    if (!_retired) {
      _retired = true;
      _presentation?.retireDisplays();
      for (final intent in _expansions.values) {
        intent.retire();
      }
      _childrenDisplays.clear();
      _groupDisplays.clear();
      _currentDisplays.clear();
      imageResources.retire();
      retirement.value = true;
    }
    for (final scope in _ownedQueries.toList()) {
      unawaited(_settleQueries(scope));
    }
    _releaseIfReady();
    return _released.future;
  }

  Future<void> _settleQueries(Object scope) {
    if (!_ownedQueries.contains(scope)) return Future.value();
    final existing = _closingQueries[scope];
    if (existing != null) return existing;
    final completion = Completer<void>();
    final task = completion.future;
    _closingQueries[scope] = task;
    completion.complete(_closeQuery(scope, task));
    return task;
  }

  Future<void> _closeQuery(Object scope, Future<void> closing) async {
    try {
      final report = await switch (scope) {
        HistoryQueryScope value => () async {
          value.retire();
          return value.close();
        }(),
        CurrentQueryScope value => () async {
          value.retire();
          return value.close();
        }(),
        _ => throw StateError('Unknown timeline query scope'),
      };
      if (report.complete) {
        _ownedQueries.remove(scope);
        _queryCleanupErrors.remove(scope);
      } else {
        _queryCleanupErrors[scope] = (report, null);
      }
    } catch (error, stack) {
      _queryCleanupErrors[scope] = (error, stack);
    } finally {
      if (identical(_closingQueries[scope], closing)) {
        _closingQueries.remove(scope);
      }
      _releaseIfReady();
    }
  }

  void _releaseIfReady() {
    if (_disposed ||
        !_retired ||
        _mounted ||
        _mutations != 0 ||
        _ownedQueries.isNotEmpty) {
      return;
    }
    _disposed = true;
    final controller = _controller!;
    controller.operationsStream.listen(
      (_) {},
      onDone: () {
        if (!_released.isCompleted) _released.complete();
      },
    );
    _presentation?.dispose();
    _presentation = null;
    imageResources.release();
    live.dispose();
    currentCollectionError.dispose();
    _expansions.clear();
    retirement.dispose();
    controller.dispose();
    _controller = null;
    _scrollController.dispose();
  }
}

/// The only presentation consumer. Page results and timeline batches commit
/// serially; network reads stay outside that commit chain and never hold credit.
final class TimelineSessionOwner {
  TimelineSessionOwner({required this.client});

  final AnyworkClient client;
  final LatestValue<TimelineSessionViewState?> source = LatestValue(null);
  Observation? _consumerObservation;
  ConversationSession? _observedSession;
  String? _observedThread;
  TimelineDisplayLease? _current;
  final Set<TimelineDisplayLease> _retiring = {};
  final Set<TimelineDisplayLease> _preparingDisplays = {};
  Future<void> _commits = Future.value();
  Future<void>? _olderInFlight;
  Object? _olderRequestKey;
  int _selection = 0;
  int _generation = 0;
  bool _bindingConsumer = false;
  bool _closed = false;
  Future<CloseReport>? _closing;
  Future<CloseReport>? _retryingCleanup;
  ReadDemand? _readDemand;
  final Stopwatch _layoutClock = Stopwatch()..start();
  String? _selectionTarget;
  int _visibleSelectionId = 0;
  int? _selectionStartedMicros;

  int get monotonicMicros => _layoutClock.elapsedMicroseconds;

  /// Called at AppGraph's accepted visible selection boundary, before opening its read demand.
  void noteVisibleSelection(String? threadId) {
    if (_closed || _selectionTarget == threadId) return;
    _selectionTarget = threadId;
    _visibleSelectionId++;
    _selectionStartedMicros = threadId == null ? null : monotonicMicros;
  }

  /// Receives a timestamp captured after a real nonempty content subtree completed layout.
  /// The witness must check actual visibility at frame end; this owner rechecks original identity.
  void recordContentLayout(
    TimelineDisplayLease lease,
    String itemId,
    int layoutCompletedMicros,
  ) {
    final started = lease.selectionStartedMicros;
    final selectionId = lease.selectionId;
    if (_closed ||
        !identical(_current, lease) ||
        lease.isRetired ||
        !lease.isMounted ||
        lease.firstContentLayout != null ||
        _selectionTarget != lease.threadId ||
        selectionId != _visibleSelectionId ||
        started == null ||
        selectionId == null ||
        layoutCompletedMicros < started ||
        layoutCompletedMicros > monotonicMicros ||
        !lease.controller.messages.any((message) => message.id == itemId)) {
      return;
    }
    lease._firstContentLayout = TimelineContentLayout(
      selectionId: selectionId,
      generation: lease.generation,
      itemId: itemId,
      selectionStartedMicros: started,
      layoutCompletedMicros: layoutCompletedMicros,
    );
  }

  /// Updated from the actual viewport before the first consumer is attached.
  void updateReadDemand(ReadDemand demand) {
    if (_closed) return;
    _readDemand = demand;
    final session = _observedSession;
    if (session != null && _consumerObservation == null) {
      _attachConsumer(_selection, session);
    }
  }

  /// A synchronous borrow of the original visible selection's layout witness.
  /// This does not open a read, advance a page, mount content or retain a lease.
  ({
    String threadId,
    int selectionId,
    int generation,
    TimelineContentLayout? firstContentLayout,
  })?
  get visibleLayoutSnapshot {
    final current = _current;
    final selectionId = current?.selectionId;
    if (_closed ||
        current == null ||
        current.isRetired ||
        !current.isMounted ||
        _selectionTarget != current.threadId ||
        selectionId == null ||
        selectionId != _visibleSelectionId) {
      return null;
    }
    return (
      threadId: current.threadId,
      selectionId: selectionId,
      generation: current.generation,
      firstContentLayout: current.firstContentLayout,
    );
  }

  TimelineDisplayLease? lease(String threadId) {
    final value = _current;
    return value?.threadId == threadId && !value!.isRetired ? value : null;
  }

  bool _selected(int selection, ConversationSession session) =>
      !_closed &&
      _selection == selection &&
      identical(_observedSession, session);

  Future<void> _serialize(Future<void> Function() commit) {
    final queued = Stopwatch()..start();
    final result = _commits.then((_) {
      developer.Timeline.instantSync(
        'conversation.admission',
        arguments: {
          'owner': 'timeline',
          'threadId': _observedSession?.threadId ?? '',
          'queueWaitMicros': queued.elapsedMicroseconds,
        },
      );
      return commit();
    });
    // A failed frame remains visible to its consumer. It does not poison a later
    // independent reset/page commit or discard the real in-flight operation.
    _commits = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void select(String? threadId) {
    if (_closed) return;
    final session = threadId == null
        ? null
        : client.conversations.existingSession(threadId);
    if (_observedThread == threadId &&
        identical(_observedSession, session) &&
        _consumerObservation != null) {
      return;
    }
    final selection = ++_selection;
    final previousConsumer = _consumerObservation;
    final previous = _current;
    final preparing = _preparingDisplays.toList();
    _consumerObservation = null;
    _current = null;
    _olderInFlight = null;
    _observedThread = threadId;
    _observedSession = session;
    if (previous != null) _trackRetirement(previous);
    for (final display in preparing) {
      _trackRetirement(display);
    }
    // Publish ownership before invoking cancellation or retirement callbacks.
    // Reentry owns a new selection and may only be followed by cleanup of these
    // captured old handles, never by writing into the new selection.
    previousConsumer?.cancel();
    if (previous != null) _retire(previous);
    for (final display in preparing) {
      _retire(display);
    }
    if (_closed || _selection != selection) return;
    if (threadId == null) {
      source.publish(null);
      return;
    }
    source.publish(
      TimelineSessionViewState(
        threadId: threadId,
        generation: 0,
        mode: TimelineDisplayMode.live,
        connection: TimelineConnectionPhase.idle,
      ),
    );
    if (session == null || !_selected(selection, session)) return;
    if (_selected(selection, session)) _attachConsumer(selection, session);
  }

  final Set<_TimelineRead> _reads = {};
  void _attachConsumer(
    int selection,
    ConversationSession session, {
    int restarts = 0,
  }) {
    final demand = _readDemand;
    if (_bindingConsumer || !_selected(selection, session) || demand == null) {
      return;
    }
    _bindingConsumer = true;
    try {
      final read = _TimelineRead(this, selection, session, restarts);
      _reads.add(read);
      _consumerObservation = read;
      final done = Completer<void>();
      read.task = done.future;
      done.complete(_runReader(read, demand));
    } finally {
      _bindingConsumer = false;
      final selected = _observedSession;
      if (!_closed &&
          _selection != selection &&
          selected != null &&
          _consumerObservation == null) {
        _attachConsumer(_selection, selected);
      }
    }
  }

  void refresh(String threadId) {
    final selected = _observedSession;
    if (_closed || selected?.threadId != threadId) return;
    _consumerObservation?.cancel();
    _consumerObservation = null;
    _attachConsumer(_selection, selected!);
  }

  bool _ownsRead(_TimelineRead read) =>
      !read.isCancelled &&
      _selected(read.selection, read.session) &&
      identical(_consumerObservation, read);

  Future<void> _runReader(_TimelineRead read, ReadDemand demand) async {
    try {
      if (_ownsRead(read)) {
        _publishState(connection: TimelineConnectionPhase.opening);
      }
      final history = await client.conversations.openHistoryReader(
        read.session.threadId,
      );
      read.history = history;
      if (!_ownsRead(read)) return;
      final current = await client.conversations.openCurrentReader(
        read.session.threadId,
        demand: demand,
      );
      read.current = current;
      if (!_ownsRead(read)) return;
      if (history.metadata.historyProtocolVersion != historyProtocolVersion ||
          history.metadata.readerId.isEmpty ||
          current.metadata.currentProtocolVersion != currentProtocolVersion ||
          current.metadata.readerId.isEmpty) {
        throw const ConversationContinuityError(
          'Unsupported history or current reader handshake',
        );
      }
      final initial = await history.timelinePage(
        demand: HistoryDemand(
          maxRows: demand.maxItems,
          maxBytes: demand.maxBytes,
        ),
      );
      if (!_ownsRead(read)) return;
      final initialView = current.initialView;
      await _serialize(
        () =>
            _set(read, initial.entries, initialView, olderCursor: initial.next),
      );
      unawaited(_runCurrentWatch(read, demand));
      var cut = initial.cut;
      while (_ownsRead(read)) {
        HistoryCut changed;
        try {
          changed = await history.waitChanged(cut);
        } catch (error) {
          if (!_ownsRead(read)) break;
          rethrow;
        }
        if (!_ownsRead(read)) break;
        cut = changed;
        final page = await history.timelinePage(
          cut: changed,
          demand: HistoryDemand(
            maxRows: demand.maxItems,
            maxBytes: demand.maxBytes,
          ),
        );
        final view = await current.snapshot(demand);
        if (!_ownsRead(read)) break;
        await _serialize(() => _applyLatestHistory(read, page, view));
      }
    } catch (error) {
      if (_ownsRead(read)) {
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error is _TimelineApplyFailure ? error.cause : error,
        );
        _restart(read);
      }
    } finally {
      await read.close();
    }
  }

  Future<void> _runCurrentWatch(_TimelineRead read, ReadDemand demand) async {
    try {
      final reader = read.current;
      if (reader == null || !_ownsRead(read)) return;
      final watch = await reader.watch(
        after: reader.initialView.revision,
        demand: demand,
      );
      read.currentWatch = watch;
      if (!_ownsRead(read)) return;
      read.currentSubscription = watch.frames.listen(
        (frame) {
          if (!_ownsRead(read)) return;
          switch (frame) {
            case ResetCurrentFrame(:final view):
              unawaited(
                _serialize(() {
                  _applyCurrentView(read, view);
                }),
              );
            case ProjectionCurrentFrame(:final revision, :final projection):
              unawaited(
                _serialize(() {
                  _applyCurrentProjection(read, revision, projection);
                }),
              );
            case NotificationCurrentFrame():
              break;
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!_ownsRead(read)) return;
          _publishState(
            connection: TimelineConnectionPhase.failed,
            connectionError: error,
          );
          _restart(read);
        },
        onDone: () {
          if (_ownsRead(read)) {
            _publishState(
              connection: TimelineConnectionPhase.failed,
              connectionError: const ConversationStreamEnded(),
            );
            _restart(read);
          }
        },
      );
    } catch (error) {
      if (!_ownsRead(read)) return;
      _publishState(
        connection: TimelineConnectionPhase.failed,
        connectionError: error,
      );
      read.cancel();
    }
  }

  void _restart(_TimelineRead read) {
    if (!_ownsRead(read) || read.restarts >= 1) {
      read.cancel();
      return;
    }
    read.cancel();
    _attachConsumer(read.selection, read.session, restarts: read.restarts + 1);
  }

  Future<void> _applyCurrentView(_TimelineRead read, CurrentView view) async {
    final current = _current;
    if (!_ownsRead(read) ||
        current == null ||
        current.isRetired ||
        !identical(current.history, read.history) ||
        !identical(current.current, read.current)) {
      return;
    }
    await current._admitCurrentProject(view);
  }

  Future<void> _applyCurrentProjection(
    _TimelineRead read,
    CurrentRevision revision,
    CurrentProjection projection,
  ) async {
    final current = _current;
    if (!_ownsRead(read) ||
        current == null ||
        current.isRetired ||
        !identical(current.history, read.history) ||
        !identical(current.current, read.current)) {
      return;
    }
    await current._admitCurrentProjection(revision, projection);
  }

  void _admitTerminalHistory(Iterable<HistoryTimelineEntry> entries) {
    for (final entry in entries) {
      final head = entry.head;
      final entity = switch (head) {
        SingleHistoryRow(:final head) => head,
        MemberHistoryRow(:final head) => head,
        _ => null,
      };
      if (entity?.state.kind == HistoryEntityStateKind.knownTerminal ||
          entity?.observation.kind == HistoryObservationKind.boundary ||
          entity?.observation.kind ==
              HistoryObservationKind.unavailableLegacy) {
        _terminalHistoryEntities.add(entity!.entityId);
      }
    }
  }

  CurrentRunSnapshot _filterCurrentSnapshot(CurrentRunSnapshot snapshot) {
    if (_terminalHistoryEntities.isEmpty) return snapshot;
    final blocks = [
      for (final block in snapshot.blocks)
        if (!_currentBelongsToTerminal(block)) block,
    ];
    if (blocks.length == snapshot.blocks.length) return snapshot;
    return CurrentRunSnapshot(
      revision: snapshot.revision,
      layoutRevision: snapshot.layoutRevision,
      readyFrontier: snapshot.readyFrontier,
      executionPresent: snapshot.executionPresent,
      currentWorkId: blocks.any((block) => block.id == snapshot.currentWorkId)
          ? snapshot.currentWorkId
          : null,
      blocks: blocks,
      currentAtoms: snapshot.currentAtoms,
      older: snapshot.older,
    );
  }

  CurrentRunSnapshot _snapshotCurrent(
    CurrentRevision revision,
    CurrentProjection projection,
  ) {
    final atoms = projection.atoms.isNotEmpty
        ? projection.atoms
        : _loadedCurrentAtoms;
    final snapshot = CurrentRunSnapshot(
      revision: revision.revision,
      layoutRevision: revision.revision,
      readyFrontier: 0,
      executionPresent: projection.executionPresent,
      currentWorkId: null,
      blocks: const [],
      currentAtoms: atoms,
      older: null,
    );
    return _filterCurrentSnapshot(snapshot);
  }

  Future<void> _applyCurrentRows(
    CurrentRevision revision,
    CurrentProjection projection,
  ) async {
    if (_retired) return;
    final atoms = projection.atoms.isNotEmpty
        ? projection.atoms
        : _loadedCurrentAtoms;
    final history = [
      for (final message in _controller?.messages ?? const <Message>[])
        (message.metadata?[timelineDisplayUnitKey] as TimelineDisplayUnit)
            .block,
    ];
    final overlay = TimelineCurrentProjection.overlayHistory(
      history,
      atoms: atoms,
      ownerId: revision.ownerId,
    );
    final snapshot = _snapshotCurrent(revision, projection);
    await _mutate(() async {
      if (_retired) return;
      if (overlay.isNotEmpty) {
        await _presentation!.replaceBlocks(overlay);
      }
      if (_retired) return;
      live.value = snapshot;
    });
  }

  Future<void> _admitCurrentProject(CurrentView view) async {
    await _admitCurrentProjection(view.revision, view.projection);
  }

  Future<void> _admitCurrentProjection(
    CurrentRevision revision,
    CurrentProjection projection,
  ) async {
    if (_retired) return;
    _latestCurrentRevision = revision;
    _latestCurrentProjection = projection;
    final scope = _currentQueries;
    if (scope == null) return;
    final atomRef = projection.collections
        .where((reference) => reference.collection == 'atoms')
        .firstOrNull;
    final sourceRef = projection.collections
        .where((reference) => reference.collection == 'sources')
        .firstOrNull;
    if (atomRef != _atomCollection) {
      _atomCollection = atomRef;
      _loadedCurrentAtoms = const [];
      _currentAtomsContinuation = null;
    }
    if (sourceRef != _sourceCollection) {
      _sourceCollection = sourceRef;
      _loadedCurrentSources = const [];
      _currentSourcesContinuation = null;
    }
    try {
      await Future.wait([
        if (atomRef != null && _loadedCurrentAtoms.isEmpty)
          _loadCurrentAtoms(scope, atomRef, reset: true),
        if (sourceRef != null && _loadedCurrentSources.isEmpty)
          _loadCurrentSources(scope, sourceRef, reset: true),
      ]);
      if (_retired) return;
      currentCollectionError.value = null;
    } catch (error) {
      if (!_retired) currentCollectionError.value = error;
    }
    if (!_retired) await _applyCurrentRows(revision, projection);
  }

  Future<void> loadNextCurrentAtoms() async {
    final scope = _currentQueries;
    if (scope == null) {
      return;
    }
    final atomRef = _atomCollection;
    final sourceRef = _sourceCollection;
    await Future.wait([
      if (atomRef != null && _currentAtomsContinuation != null)
        _loadCurrentAtoms(scope, atomRef, reset: false),
      if (sourceRef != null && _currentSourcesContinuation != null)
        _loadCurrentSources(scope, sourceRef, reset: false),
    ]);
    final projection = _latestCurrentProjection;
    final revision = _latestCurrentRevision;
    if (!_retired && projection != null && revision != null) {
      await _applyCurrentRows(revision, projection);
    }
  }

  bool get hasMoreCurrentAtoms =>
      _currentAtomsContinuation != null || _currentSourcesContinuation != null;

  List<ChatSourceState> get currentSources {
    final direct =
        _latestCurrentProjection?.sources ?? const <ChatSourceState>[];
    return direct.isEmpty ? _loadedCurrentSources : direct;
  }

  Future<void> _loadCurrentAtoms(
    CurrentReadScope scope,
    CurrentCollectionRef reference, {
    required bool reset,
  }) async {
    if (_retired || !scope.isActive) throw const StaleConversationScope();
    final existing = _currentAtomsLoading;
    if (existing != null) {
      if (_currentAtomsLoadingRef == reference) return existing;
      return existing.then(
        (_) => _loadCurrentAtoms(scope, reference, reset: reset),
      );
    }
    final completion = Completer<void>();
    _currentAtomsLoading = completion.future;
    _currentAtomsLoadingRef = reference;
    completion.complete(() async {
      try {
        final page = await scope.pageCollection(
          reference: reference,
          continuation: reset ? null : _currentAtomsContinuation,
          demand: demand,
        );
        if (_retired || reference != _atomCollection) return;
        if (page.revision != reference.revision) {
          throw const StaleConversationScope();
        }
        final atoms = <CurrentAtom>[];
        for (final entry in page.entries) {
          atoms.add(await _decodeCurrentAtom(scope, entry));
        }
        if (_retired || reference != _atomCollection) return;
        final combined = reset
            ? atoms
            : <CurrentAtom>[..._loadedCurrentAtoms, ...atoms];
        final limit = max(demand.maxItems * 4, 256);
        _loadedCurrentAtoms = List.unmodifiable(
          combined.length > limit
              ? combined.sublist(combined.length - limit)
              : combined,
        );
        _currentAtomsContinuation = page.continuation;
        final projection = _latestCurrentProjection;
        final revision = _latestCurrentRevision;
        if (projection != null && revision != null) {}
      } finally {
        _currentAtomsLoading = null;
        _currentAtomsLoadingRef = null;
      }
    }());
    return completion.future;
  }

  Future<CurrentAtom> _decodeCurrentAtom(
    CurrentReadScope scope,
    CurrentCollectionEntry entry,
  ) async {
    final payload = switch (entry.payload) {
      InlineCurrentPayload() => entry.payload,
      DeferredCurrentPayload(:final reference, :final byteLength) =>
        InlineCurrentPayload(
          bytes: await _readCurrentPayload(scope, reference, byteLength),
        ),
    };
    return decodeCurrentAtomPayload(payload);
  }

  Future<void> _loadCurrentSources(
    CurrentReadScope scope,
    CurrentCollectionRef reference, {
    required bool reset,
  }) async {
    if (_retired || !scope.isActive) throw const StaleConversationScope();
    final existing = _currentSourcesLoading;
    if (existing != null) {
      if (_currentSourcesLoadingRef == reference) return existing;
      return existing.then(
        (_) => _loadCurrentSources(scope, reference, reset: reset),
      );
    }
    final completion = Completer<void>();
    _currentSourcesLoading = completion.future;
    _currentSourcesLoadingRef = reference;
    completion.complete(() async {
      try {
        final page = await scope.pageCollection(
          reference: reference,
          continuation: reset ? null : _currentSourcesContinuation,
          demand: demand,
        );
        if (_retired || reference != _sourceCollection) return;
        if (page.revision != reference.revision) {
          throw const StaleConversationScope();
        }
        final sources = <ChatSourceState>[];
        for (final entry in page.entries) {
          final payload = switch (entry.payload) {
            InlineCurrentPayload() => entry.payload,
            DeferredCurrentPayload(:final reference, :final byteLength) =>
              InlineCurrentPayload(
                bytes: await _readCurrentPayload(scope, reference, byteLength),
              ),
          };
          sources.add(decodeCurrentSourcePayload(payload));
        }
        if (_retired || reference != _sourceCollection) return;
        final combined = reset
            ? sources
            : <ChatSourceState>[..._loadedCurrentSources, ...sources];
        final limit = max(demand.maxItems * 4, 256);
        _loadedCurrentSources = List.unmodifiable(
          combined.length > limit
              ? combined.sublist(combined.length - limit)
              : combined,
        );
        _currentSourcesContinuation = page.continuation;
      } finally {
        _currentSourcesLoading = null;
        _currentSourcesLoadingRef = null;
      }
    }());
    return completion.future;
  }

  Future<List<int>> _readCurrentPayload(
    CurrentReadScope scope,
    CurrentContentRef reference,
    int byteLength,
  ) async {
    if (byteLength > demand.maxBytes) {
      throw const ConversationContinuityError(
        'Current collection entry exceeds the active demand',
      );
    }
    final bytes = <int>[];
    while (bytes.length < byteLength) {
      final remaining = byteLength - bytes.length;
      final window = await scope.readBody(
        reference: reference,
        range: ContentRange(
          offset: bytes.length,
          maxBytes: remaining < 64 * 1024 ? remaining : 64 * 1024,
        ),
      );
      if (window.offset != bytes.length ||
          window.availableThrough != byteLength ||
          window.bytes.isEmpty) {
        throw const ConversationContinuityError(
          'Current collection body is discontinuous',
        );
      }
      bytes.addAll(window.bytes);
      if (window.sealed && bytes.length < byteLength) {
        throw const ConversationContinuityError(
          'Sealed Current collection body is incomplete',
        );
      }
    }
    return bytes;
  }

  int? get _firstLoadedOrder {
    final messages = _controller?.messages;
    if (messages == null || messages.isEmpty) return null;
    final unit =
        messages.first.metadata?[timelineDisplayUnitKey]
            as TimelineDisplayUnit?;
    return unit?.blockOrder;
  }

  Future<void> _applyLatestHistory(
    _TimelineRead read,
    HistoryTimelinePage page,
    CurrentView view,
  ) async {
    final current = _current;
    if (!_ownsRead(read) ||
        current == null ||
        current.isRetired ||
        !identical(current.history, read.history)) {
      return;
    }
    final blocks = TimelineHistoryProjection.blocks(page.entries.reversed);
    final resetWindow =
        current.loadedCount + blocks.length > current._historyRowLimit;
    await current._mutate(() async {
      current._admitTerminalHistory(page.entries);
      try {
        if (resetWindow) {
          await current._presentation!.applyBlocks(
            blocks,
            TimelineApplyPlacement.set,
          );
        } else {
          await current._presentation!.replaceBlocks(blocks);
        }
      } catch (error) {
        throw _TimelineApplyFailure(error);
      }
      current.live.value = current._snapshotCurrent(
        view.revision,
        view.projection,
      );
      if (resetWindow) {
        current._before = page.next;
        current._hasOlder = page.next != null;
        current._recordBatch(TimelineApplyPlacement.set);
      }
    });
    current._firstOrder = current._firstLoadedOrder;
    await current._admitCurrentProject(view);
    if (!_ownsRead(read)) return;
    _markPresentedInputs(read.session.threadId, blocks, const []);
    _publishState(
      connection: TimelineConnectionPhase.ready,
      connectionError: null,
      hasNewOutput: current.mode == TimelineDisplayMode.history,
    );
  }

  Future<void> _set(
    _TimelineRead read,
    List<HistoryTimelineEntry> entries,
    CurrentView currentView, {
    required String? olderCursor,
  }) async {
    final session = read.session;
    final next = TimelineDisplayLease(
      threadId: session.threadId,
      generation: ++_generation,
      demand: _readDemand!,
      history: read.history!,
      current: read.current!,
      selectionId: _selectionTarget == session.threadId
          ? _visibleSelectionId
          : null,
      selectionStartedMicros: _selectionTarget == session.threadId
          ? _selectionStartedMicros
          : null,
    );
    _preparingDisplays.add(next);
    next._admitTerminalHistory(entries);
    final live = next._snapshotCurrent(
      currentView.revision,
      currentView.projection,
    );
    try {
      final presentation = next._presentation!;
      await next._mutate(() async {
        try {
          await presentation.applyBlocks(
            TimelineHistoryProjection.blocks(entries.reversed),
            TimelineApplyPlacement.set,
          );
        } catch (error) {
          throw _TimelineApplyFailure(error);
        }
        if (_ownsRead(read)) {
          next.live.value = next._filterCurrentSnapshot(live);
        }
      });
    } catch (_) {
      _preparingDisplays.remove(next);
      _retire(next);
      rethrow;
    }
    _preparingDisplays.remove(next);
    if (!_ownsRead(read)) {
      _retire(next);
      return;
    }
    final blocks = TimelineHistoryProjection.blocks(entries.reversed);
    next._before = olderCursor;
    next._firstOrder = blocks.firstOrNull?.blockOrder;
    next._recordBatch(TimelineApplyPlacement.set);
    next._hasOlder = olderCursor != null;
    final previous = _current;
    next._mode = previous?.mode ?? TimelineDisplayMode.live;
    _current = next;
    _markPresentedInputs(session.threadId, blocks, live.blocks);
    _olderInFlight = null;
    await next._admitCurrentProject(currentView);
    if (previous != null) _retire(previous);
    _publishState(isLoadingOlder: false, olderError: null, hasNewOutput: false);
  }

  void _markPresentedInputs(
    String threadId,
    List<DisplayBlock> history,
    List<LiveDisplayBlock> tail,
  ) {
    final inputIds = <String>[
      for (final block in history)
        if (block.body case SingleDisplayBlock(:final record))
          if (record.atom.source case InputChatSource(:final inputId)) inputId,
      for (final block in tail)
        if (block.body case SingleDisplayBlock(:final record))
          if (record.atom.source case InputChatSource(:final inputId)) inputId,
    ];
    if (inputIds.isEmpty) return;
    client.drafts.existingComposer(threadId)?.markInputsPresented(inputIds);
    client.drafts.startDraft.markInputsPresented(inputIds);
  }

  void _trackRetirement(TimelineDisplayLease lease) {
    if (_retiring.add(lease)) {
      lease.released.then((_) => _retiring.remove(lease));
    }
  }

  void _retire(TimelineDisplayLease lease) {
    _trackRetirement(lease);
    unawaited(lease.retire());
  }

  Future<void> retire() {
    final current = _current;
    select(null);
    return current?.released ?? Future.value();
  }

  void _publishState({
    TimelineConnectionPhase? connection,
    Object? connectionError = _unset,
    Object? olderError = _unset,
    bool? isLoadingOlder,
    bool? hasNewOutput,
  }) {
    final current = source.value;
    if (current == null) return;
    final display = _current;
    final next = current.copyWith(
      generation: display?.generation ?? current.generation,
      mode: display?.mode ?? current.mode,
      connection: connection ?? current.connection,
      connectionError: identical(connectionError, _unset)
          ? current.connectionError
          : connectionError,
      olderCursor: display?.olderCursor,
      hasOlder: display?.hasOlder ?? false,
      isLoadingOlder: isLoadingOlder ?? current.isLoadingOlder,
      olderError: identical(olderError, _unset)
          ? current.olderError
          : olderError,
      hasNewOutput: hasNewOutput ?? current.hasNewOutput,
    );
    if (next != current) source.publish(next);
  }

  Future<void> dispatch(String threadId, TimelineCommand command) {
    final current = lease(threadId);
    if (current == null) return Future.value();
    switch (command) {
      case TimelineEnterHistory():
        current._mode = TimelineDisplayMode.history;
        _publishState();
      case TimelineReturnLive():
        return returnToLive(threadId);
    }
    return Future.value();
  }

  /// Reading intent changes no Session, consumer, query scope or loaded window.
  Future<void> returnToLive(String threadId) async {
    final current = lease(threadId);
    if (current == null) return;
    current._mode = TimelineDisplayMode.live;
    _publishState(hasNewOutput: false);
  }

  /// Returns a mounted composer to Chat's latest edge without waiting for paint.
  void prepareComposerSubmissionDisplay(
    String threadId, {
    required TimelineDisplayLease lease,
  }) {
    bool current() =>
        identical(this.lease(threadId), lease) &&
        lease.isMounted &&
        !lease.isRetired;
    if (!current()) return;

    final scroll = lease.scrollController;
    if (scroll.hasClients &&
        scroll.position.hasContentDimensions &&
        scroll.position.viewportDimension > 0) {
      scroll.jumpTo(scroll.position.minScrollExtent);
    }

    if (!current()) return;
    lease._mode = TimelineDisplayMode.live;
    _publishState(hasNewOutput: false);
    if (!current()) return;
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> loadOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation: generation, retry: false);
  Future<void> retryOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation: generation, retry: true);
  Future<void> _requestOlder(
    String threadId, {
    required int generation,
    required bool retry,
  }) {
    final current = lease(threadId);
    if (current == null || current.generation != generation) {
      return Future.value();
    }
    return _readSlot((
      current,
      'history',
    ), () => _loadOlder(current, retry: retry));
  }

  /// Main paging is single-flight and revalidates the captured display lease.
  Future<void> _readSlot(Object key, Future<void> Function() operation) {
    final existing = _olderInFlight;
    if (existing != null) {
      if (_olderRequestKey == key) return existing;
      return existing.then(
        (_) => _readSlot(key, operation),
        onError: (Object _, StackTrace _) => _readSlot(key, operation),
      );
    }
    final completion = Completer<void>();
    final task = completion.future;
    _olderInFlight = task;
    _olderRequestKey = key;
    void release() {
      if (identical(_olderInFlight, task)) {
        _olderInFlight = null;
        _olderRequestKey = null;
      }
    }

    unawaited(
      task.then<void>(
        (_) => release(),
        onError: (Object _, StackTrace _) => release(),
      ),
    );
    completion.complete(Future<void>.sync(operation));
    return task;
  }

  Future<void> _loadOlder(
    TimelineDisplayLease current, {
    required bool retry,
  }) async {
    // A different read intent may have queued this operation before selection
    // retired its lease. Revalidate before publishing loading on the new page.
    if (!identical(_current, current) || current.isRetired) return;
    if (!current.hasOlder ||
        current._before == null ||
        (!retry && source.value?.olderError != null)) {
      return;
    }
    final before = current._before!;
    _publishState(isLoadingOlder: true, olderError: null);
    try {
      final scope = current._historyQueries;
      if (scope == null) {
        throw const StaleConversationScope();
      }
      final demand = _readDemand ?? current.demand;
      final page = await scope.timelinePage(
        cursor: before,
        demand: HistoryDemand(
          maxRows: demand.maxItems,
          maxBytes: demand.maxBytes,
        ),
      );
      if (!identical(_current, current) ||
          current.isRetired ||
          !scope.isActive) {
        return;
      }
      await _serialize(() async {
        if (!identical(_current, current) ||
            current.isRetired ||
            !scope.isActive ||
            current._before != before) {
          return;
        }
        if (page.next == before || page.entries.any((e) => e.rowKey.isEmpty)) {
          throw const ConversationContinuityError('Invalid history page');
        }
        final blocks = TimelineHistoryProjection.blocks(page.entries.reversed);
        current._admitTerminalHistory(page.entries);
        var order = 0;
        final ids = <String>{};
        for (final block in blocks) {
          if (block.id.isEmpty ||
              !ids.add(block.id) ||
              block.blockOrder <= order ||
              block.blockOrder.bitLength > 63) {
            throw const ConversationContinuityError('Invalid history range');
          }
          order = block.blockOrder;
        }
        if (blocks.isNotEmpty &&
            current._firstOrder != null &&
            blocks.last.blockOrder >= current._firstOrder!) {
          throw const ConversationContinuityError('History pages overlap');
        }
        await current._mutate(() async {
          try {
            await current._presentation!.applyBlocks(
              blocks,
              TimelineApplyPlacement.prepend,
            );
            await current._presentation!.trimNewest(
              current.loadedCount > current._historyRowLimit
                  ? current.loadedCount - current._historyRowLimit
                  : 0,
            );
          } catch (error) {
            throw _TimelineApplyFailure(error);
          }
        });
        if (!identical(_current, current) ||
            current.isRetired ||
            !scope.isActive) {
          return;
        }
        if (blocks.isNotEmpty) {
          current._firstOrder = blocks.first.blockOrder;
        }
        current.live.value = current._filterCurrentSnapshot(
          current.live.value!,
        );
        current._before = page.next;
        current._hasOlder = page.next != null;
        current._recordBatch(TimelineApplyPlacement.prepend);
      });
      if (identical(_current, current) &&
          !current.isRetired &&
          scope.isActive) {
        _publishState(isLoadingOlder: false, olderError: null);
      }
    } catch (error) {
      if (identical(_current, current) && !current.isRetired) {
        _publishState(
          isLoadingOlder: false,
          olderError: error is _TimelineApplyFailure ? error.cause : error,
        );
        if (error is _TimelineApplyFailure) refresh(current.threadId);
      }
    } finally {
      if (identical(_current, current) &&
          source.value?.isLoadingOlder == true) {
        _publishState(isLoadingOlder: false);
      }
    }
  }

  Future<CloseReport> close({ClientCloseBudget? budget}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    final closing = completion.future;
    // Install the shared result before cancellation, display retirement or
    // publishing null can synchronously call close again.
    _closing = closing;
    unawaited(
      Future<CloseReport>.sync(() {
        _closed = true;
        ++_selection;
        final leases = <TimelineDisplayLease>{
          ..._retiring,
          ..._preparingDisplays,
          ?_current,
        };
        _current = null;
        for (final lease in leases) {
          _trackRetirement(lease);
        }
        _detach();
        if (source.value != null) source.publish(null);
        for (final lease in leases) {
          _retire(lease);
        }
        return _join(leases, budget);
      }).then<void>(
        (report) {
          if (!report.complete && identical(_closing, closing)) _closing = null;
          completion.complete(report);
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_closing, closing)) _closing = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return closing;
  }

  Future<CloseReport> _join(
    Set<TimelineDisplayLease> leases,
    ClientCloseBudget? budget, {
    List<_TimelineRead>? reads,
    Set<_TimelineRead> retryReads = const {},
  }) async {
    final capturedReads = reads ?? _reads.toList();
    final pending = Future.wait<void>([
      _commits,
      for (final read in capturedReads)
        read.join(retry: retryReads.contains(read)),
      ?_olderInFlight,
      for (final lease in leases) lease.released,
    ]);
    if (budget == null) {
      await pending;
    } else {
      try {
        await pending.timeout(budget.remaining);
      } on TimeoutException {
        // All owners and native close obligations remain retained for retry.
      }
    }
    return CloseReport(
      unresolved: [
        for (final read in capturedReads)
          if (_reads.contains(read))
            UnresolvedResource(
              resourceId: read.resourceId,
              owner: 'timeline-reader:${read.session.threadId}',
              attemptId: AttemptId(read.selection),
              reason:
                  read.closeError?.$1 ??
                  read.requestError?.$1 ??
                  StateError('Reader is still closing'),
              ownership: ClientOwnership.owned,
              stages: [
                if (read.requestError case final failure?)
                  ClientResourceStage(
                    owner: 'timeline-reader:${read.session.threadId}',
                    phase: ClientClosePhase.closeRequest,
                    ownership: ClientOwnership.owned,
                    error: failure.$1,
                    stackTrace: failure.$2,
                  ),
                if (read.closeErrors.isEmpty)
                  ClientResourceStage(
                    owner: 'timeline-reader:${read.session.threadId}',
                    phase: ClientClosePhase.close,
                    ownership: ClientOwnership.owned,
                    pending: read.closePending,
                  )
                else
                  for (final failure in read.closeErrors)
                    ClientResourceStage(
                      owner: 'timeline-reader:${read.session.threadId}',
                      phase: ClientClosePhase.close,
                      ownership: ClientOwnership.owned,
                      pending: read.closePending,
                      error: failure.$1,
                      stackTrace: failure.$2,
                    ),
              ],
            ),
        for (final lease in leases)
          if (!lease.isReleased) ...[
            ...lease._queryCleanupReport.unresolved,
            UnresolvedResource(
              resourceId: lease.resourceId,
              owner: 'timeline-display:${lease.threadId}',
              attemptId: AttemptId(lease.generation),
              reason: StateError('Display is not released'),
              ownership: ClientOwnership.owned,
              stages: [
                ClientResourceStage(
                  owner: 'timeline-display:${lease.threadId}',
                  phase: ClientClosePhase.consumer,
                  ownership: ClientOwnership.owned,
                  pending: true,
                ),
              ],
            ),
          ],
      ],
    );
  }

  /// Retries failed cleanup on this timeline owner's original resources.
  ///
  /// Only reader attempts already failed at entry are retried. Pending attempts
  /// are joined, and successful readers are not closed again. Retiring queries
  /// and displays rejoin their original cleanup without reopening business
  /// resources or disposing a controller still borrowed by a mounted widget.
  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) {
    final existing = _retryingCleanup;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    final retrying = completion.future;
    _retryingCleanup = retrying;
    unawaited(
      Future<CloseReport>.sync(() {
        final reads = _reads.where((read) => read.cleanupRequested).toList();
        final retryReads = reads.where((read) => read.canRetryClose).toSet();
        final leases = _retiring.toSet();
        for (final lease in leases) {
          _retire(lease);
        }
        return _join(leases, budget, reads: reads, retryReads: retryReads);
      }).then<void>(
        (report) {
          if (identical(_retryingCleanup, retrying)) _retryingCleanup = null;
          completion.complete(report);
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_retryingCleanup, retrying)) _retryingCleanup = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return retrying;
  }
}

final class _TimelineRead implements Observation {
  _TimelineRead(this.owner, this.selection, this.session, this.restarts);
  final ClientResourceId resourceId = _newTimelineResourceId();
  final TimelineSessionOwner owner;
  final int selection;
  final ConversationSession session;
  final int restarts;
  HistoryReader? history;
  CurrentReader? current;
  CurrentWatch? currentWatch;
  // ignore: cancel_subscriptions
  StreamSubscription<CurrentFrame>? currentSubscription;
  Future<void>? _currentSubscriptionCancel;
  Future<void>? task;
  final List<(Object, StackTrace)> closeErrors = [];
  (Object, StackTrace)? get closeError => closeErrors.firstOrNull;
  (Object, StackTrace)? requestError;
  Future<void>? _closeAttempt;
  bool _closePending = false;
  bool _stopRequested = false;

  bool get cleanupRequested => isCancelled || _closeAttempt != null;
  bool get closePending => _closeAttempt == null || _closePending;
  bool get canRetryClose =>
      _closeAttempt != null && !_closePending && closeError != null;
  @override
  bool isCancelled = false;
  @override
  bool get isPaused => false;
  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    _requestStop();
  }

  void _requestStop() {
    if (_stopRequested) return;
    _stopRequested = true;
    try {
      history?.requestClose();
      current?.requestClose();
      currentWatch?.requestClose();
      requestError = null;
    } catch (error, stack) {
      requestError = (error, stack);
    }
  }

  @override
  void pause() => throw UnsupportedError('Timeline reader cannot be paused');
  @override
  void resume() {}
  Future<void> close() => _closeAttempt ?? _startCloseAttempt();

  Future<void> _startCloseAttempt() {
    final retry = _closeAttempt != null;
    final completion = Completer<void>();
    final closing = completion.future;
    _closeAttempt = closing;
    _closePending = true;
    isCancelled = true;
    if (retry) _stopRequested = false;
    completion.complete(
      Future<void>.sync(() async {
        _requestStop();
        try {
          final currentReader = current;
          currentReader?.requestClose();
          currentWatch?.requestClose();
          await Future.wait<void>([
            if (history != null) history.close(),
            if (currentReader != null) currentReader.close(),
            if (currentWatch != null) currentWatch!.close(),
          ]);
          if (currentSubscription != null) {
            await (_currentSubscriptionCancel ??= currentSubscription!
                .cancel());
          }
          closeErrors.clear();
          requestError = null;
          owner._reads.remove(this);
        } catch (error, stack) {
          closeErrors.add((error, stack));
        } finally {
          if (identical(_closeAttempt, closing)) _closePending = false;
        }
      }),
    );
    return closing;
  }

  Future<void> join({bool retry = false}) {
    if (retry && canRetryClose) unawaited(_startCloseAttempt());
    cancel();
    return _joinAttempt();
  }

  Future<void> _joinAttempt() async {
    await task;
    await _closeAttempt;
  }
}

final class HistoryGroupMembers implements DisplayMembers {
  HistoryGroupMembers._(
    this.scope,
    this.reference,
    this.demand,
    this.currentAtoms,
    this.currentOwnerId,
  );

  static Future<HistoryGroupMembers> open(
    HistoryReadScope scope, {
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
    required List<CurrentAtom> Function() currentAtoms,
    required String? Function() currentOwnerId,
  }) async {
    if (reference.blockId.isEmpty || !scope.isActive) {
      throw const StaleConversationScope();
    }
    return HistoryGroupMembers._(
      scope,
      reference,
      demand,
      currentAtoms,
      currentOwnerId,
    );
  }

  final HistoryReadScope scope;
  final DisplayBlockRef reference;
  final ReadDemand demand;
  final List<CurrentAtom> Function() currentAtoms;
  final String? Function() currentOwnerId;
  String? _next;
  int _revision = 0;
  bool _closed = false;

  @override
  Future<DisplayMemberPage?> next() async {
    if (_closed || !scope.isActive || _next != null && _next!.isEmpty) {
      return null;
    }
    final page = await scope.groupPage(
      groupId: reference.blockId,
      cursor: _next,
      demand: HistoryDemand(
        maxRows: demand.maxItems,
        maxBytes: demand.maxBytes,
      ),
    );
    _next = page.next;
    final members = page.members.reversed.toList();
    final entries = <DisplayMemberHead>[];
    for (final member in members) {
      if (member.headSeq > _revision) _revision = member.headSeq;
      final ownerId = currentOwnerId();
      final projected = TimelineHistoryProjection.block(member);
      final block = projected == null || ownerId == null
          ? projected
          : TimelineCurrentProjection.overlayHistory(
              [projected],
              atoms: currentAtoms(),
              ownerId: ownerId,
            ).single;
      if (block?.body case final SingleDisplayBlock single) {
        entries.add(
          DisplayMemberHead(
            memberKey: member.rowKey,
            memberOrder: member.anchorSeq,
            record: single.record,
          ),
        );
      }
    }
    return DisplayMemberPage(
      block: reference,
      revision: _revision,
      sealed: page.next == null,
      entries: entries,
      nextCursor: page.next,
    );
  }

  @override
  void requestClose() {
    _closed = true;
  }

  @override
  Future<void> close() async {
    requestClose();
  }
}
