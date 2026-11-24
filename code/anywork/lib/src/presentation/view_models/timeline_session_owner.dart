import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:flutter/foundation.dart' show Key, ValueKey, ValueNotifier;
import 'package:flutter/widgets.dart'
    show AsyncSnapshot, ConnectionState, ScrollController;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/live_status/live_status_state.dart'
    show LiveStatusView;
import '../../features/conversation/timeline/state/content_reference_identity.dart';
import '../../features/conversation/timeline/state/chat_item_presentation.dart';
import '../../features/conversation/timeline/state/timeline_history_item_content.dart';
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_display_diagnostics.dart';
import '../../features/conversation/timeline/state/timeline_display_unit.dart';
import '../../features/conversation/timeline/state/timeline_history_projection.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/state/work_group_event_folder.dart';
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
  TimelineDisplayLease._({
    required this._read,
    required this.threadId,
    required this.generation,
    required this.demand,
    required this.history,
    this.selectionId,
    this.selectionStartedMicros,
    this.initialHistoryContent,
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
  }

  final ClientResourceId resourceId = _newTimelineResourceId();
  final _TimelineRead _read;

  final String threadId;
  final int generation;
  final ReadDemand demand;
  late final int _historyRowLimit = max(demand.maxItems * 8, 128);
  final HistoryReader history;
  CurrentReader? get current => _read.current;
  LiveStatusView? liveStatus;
  final int? selectionId;
  final int? selectionStartedMicros;
  final TimelinePreparedHistoryItem? initialHistoryContent;
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
  final ValueNotifier<int> renderedCurrentAtoms = ValueNotifier(0);

  /// Published only by this display's serial admission, never directly by the transport.
  final ValueNotifier<CurrentAtomSnapshot?> live = ValueNotifier(null);

  /// Live, still-executing tail WorkRange routed to LiveStatusBar instead of
  /// mutating the immutable main Timeline.
  final ValueNotifier<DisplayBlock?> liveOpenWork = ValueNotifier(null);
  ({HistoryWorkRange range, HistoryCut cut})? _heldTailWork;
  final Map<String, TimelineExpansionIntent> _expansions = {};
  final Set<Object> _ownedQueries = {};
  final Map<Object, Future<void>> _closingQueries = {};
  final Map<Object, (Object, StackTrace?)> _queryCleanupErrors = {};
  HistoryReadScope? _historyQueries;
  CurrentReadScope? _currentQueries;
  CurrentProjection? _latestCurrentProjection;
  CurrentRevision? _latestCurrentRevision;
  CurrentCollectionRef? _atomCollection;
  // One bounded collection page. Continuations are intentionally not
  // concatenated into a second full Current state.
  List<CurrentAtom> _loadedCurrentAtoms = const [];
  Future<void>? _currentAtomsLoading;
  CurrentCollectionRef? _currentAtomsLoadingRef;
  final Set<String> _renderedCurrentAtomIds = {};
  HistoryCut? _historyCut;
  String? _before;
  int? _firstOrder;
  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  bool _hasOlder = false;
  bool _mounted = false;
  bool _retired = false;
  bool _disposed = false;
  int _mutations = 0;
  int _modeIntent = 0;
  int _liveWindowGeneration = 0;
  int _historyScrollIntent = 0;
  int? _liveReturnHistoryIntent;
  bool get _liveReturnPending =>
      _liveReturnHistoryIntent == _historyScrollIntent;
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
  TimelineContentLayout? _firstContentLayout;
  int _appliedSets = 0;
  int _appliedPrepends = 0;
  int _appliedAppends = 0;

  TimelineContentLayout? get firstContentLayout => _firstContentLayout;
  int get appliedSets => _appliedSets;
  int get appliedPrepends => _appliedPrepends;
  int get appliedAppends => _appliedAppends;
  Set<String> get renderedCurrentAtomIds =>
      Set.unmodifiable(_renderedCurrentAtomIds);
  TimelineExpansionIntent expansionForBlock(String blockId) {
    final existing = _expansions[blockId];
    if (existing != null && !existing.isRetired) return existing;
    final next = TimelineExpansionIntent();
    _expansions[blockId] = next;
    return next;
  }

  bool isBlockExpanded(String blockId) =>
      _expansions[blockId]?.expanded ?? false;
  void setBlockExpanded(String blockId, bool expanded) {
    if (_retired) return;
    expansionForBlock(blockId).expanded = expanded;
  }

  int enterHistoryMode() {
    if (_retired) throw StateError('Timeline display is retired');
    _mode = TimelineDisplayMode.history;
    _liveReturnHistoryIntent = null;
    return ++_modeIntent;
  }

  int requestLiveWindow() {
    if (_retired) throw StateError('Timeline display is retired');
    _liveReturnHistoryIntent = _historyScrollIntent;
    return ++_modeIntent;
  }

  void _setLiveOpenWork(DisplayBlock? next) {
    final current = liveOpenWork.value;
    if (current == null && next == null) return;
    if (current != null && next != null && sameDisplayBlock(current, next)) {
      return;
    }
    liveOpenWork.value = next;
  }

  bool _isCommittedInController(String blockId) =>
      _controller?.messages.any((message) => message.id == blockId) ?? false;

  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required ReadDemand demand,
  }) async {
    final scope = _historyQueries;
    if (scope == null || _retired) {
      throw const StaleConversationScope();
    }
    return HistoryWorkRangeMembers.open(
      scope,
      reference: reference,
      demand: demand,
    );
  }

  Iterable<TimelineGroupDisplay> get groupDisplays => _retired
      ? const []
      : _groupDisplays.where((display) => display.isCurrent);

  void bindLiveWorkIntent(TimelineExpansionIntent intent) =>
      _bindExpansionIntent(intent, requireLiveMode: false);

  void _bindUnit(TimelineDisplayUnit unit) =>
      _bindExpansionIntent(unit.expansion, requireLiveMode: true);

  void _bindExpansionIntent(
    TimelineExpansionIntent intent, {
    required bool requireLiveMode,
  }) {
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
      return historyBodyWindow(reference, value);
    };
    intent.readCurrentBody = (generation, reference, range) async {
      final scope = _currentQueries;
      if (_retired ||
          (requireLiveMode && _mode != TimelineDisplayMode.live) ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration) ||
          scope == null ||
          !scope.isActive) {
        throw const StaleConversationScope();
      }
      final value = await scope.readBody(reference: reference, range: range);
      if (_retired ||
          (requireLiveMode && _mode != TimelineDisplayMode.live) ||
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
          (requireLiveMode && _mode != TimelineDisplayMode.live) ||
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
    intent.openDisplayMembers = (reference, demand, _) {
      if (_retired || intent.isRetired || !intent.bodyActive) {
        throw const StaleConversationScope();
      }
      return openDisplayMembers(reference: reference, demand: demand);
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
    final reader = current;
    if (_retired || reader == null) throw const StaleConversationScope();
    final scope = CurrentReadScope(
      threadId: threadId,
      generation: generation ?? this.generation,
      reader: reader,
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
    liveOpenWork.dispose();
    currentCollectionError.dispose();
    renderedCurrentAtoms.dispose();
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
  _TimelineRead? _consumerObservation;
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

  /// Reached only after an actually mounted CurrentAtom body subtree completed
  /// layout. This is display evidence, not an execution or atom-existence guess.
  void recordCurrentContentLayout(
    TimelineDisplayLease lease,
    String itemId,
    int _,
  ) {
    if (_closed ||
        !identical(_current, lease) ||
        lease.isRetired ||
        lease.live.value?.currentAtoms.any((atom) => atom.id == itemId) !=
            true) {
      return;
    }
    if (lease._renderedCurrentAtomIds.add(itemId)) {
      lease.renderedCurrentAtoms.value++;
    }
  }

  void recordCurrentContentUnmounted(
    TimelineDisplayLease lease,
    String itemId,
  ) {
    if (!identical(_current, lease) || lease.isRetired) {
      return;
    }
    if (lease._renderedCurrentAtomIds.remove(itemId)) {
      lease.renderedCurrentAtoms.value++;
    }
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
      final opening = Completer<void>();
      read.currentOpening = opening.future;
      opening.complete(_openCurrent(read, demand));
      final initial = await history.timelinePage(
        demand: HistoryDemand(
          maxRows: demand.maxItems,
          maxBytes: demand.maxBytes,
        ),
      );
      if (!_ownsRead(read)) return;
      if (_hasOpenTailWork(initial)) {
        try {
          await read.currentOpening;
        } catch (_) {
          // Proceed with session activity facts if Current fails to open.
        }
        if (!_ownsRead(read)) return;
      }
      final initialCurrent = read.current?.initialView;
      final initialPartition = _partitionTimelinePage(
        read.session,
        initial,
        projection: initialCurrent?.projection,
        ownerId: initialCurrent?.revision.ownerId,
      );
      final content = await _prepareInitialHistoryItem(
        read,
        initialPartition.timelineBlocks,
      );
      if (!_ownsRead(read)) return;
      await _serialize(
        () => _set(
          read,
          initialPartition,
          cut: initial.cut,
          olderCursor: initial.next,
          initialContent: content,
          initialCurrent: initialCurrent,
        ),
      );
      unawaited(_connectCurrent(read, demand));
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
        final modeIntent = _current?._modeIntent;
        final page = await history.timelinePage(
          cut: changed,
          demand: HistoryDemand(
            maxRows: demand.maxItems,
            maxBytes: demand.maxBytes,
          ),
        );
        if (page.cut != changed) {
          throw const ConversationContinuityError(
            'History page changed its requested cut',
          );
        }
        final view = await read.current?.snapshot(demand);
        if (!_ownsRead(read) || modeIntent == null) break;
        await _serialize(
          () => _applyLatestHistory(read, page, view, modeIntent),
        );
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

  Future<TimelinePreparedHistoryItem?> _prepareInitialHistoryItem(
    _TimelineRead read,
    List<DisplayBlock> blocks,
  ) async {
    for (final block in blocks.reversed) {
      final body = block.body;
      if (body is! SingleDisplayBlock ||
          body.visibility != HistorySingleVisibility.content ||
          (body.record.atom.kind != ChatAtomKind.text &&
              body.record.atom.kind != ChatAtomKind.input)) {
        continue;
      }
      final item = ChatItemPresentation.forRecord(body.record, id: block.id);
      if (item.observationUnavailable || !item.needsHistoryBodyLoad) continue;
      final scope = HistoryReadScope(
        threadId: read.session.threadId,
        generation: read.selection,
        reader: read.history!,
        isEligible: () => _ownsRead(read),
      );
      final identity = timelineHistoryItemIdentity(item);
      try {
        final content = await readTimelineHistoryItem(scope, item);
        return (
          identity: identity,
          result: AsyncSnapshot.withData(ConnectionState.done, content),
        );
      } catch (error, stack) {
        if (!_ownsRead(read)) return null;
        return (
          identity: identity,
          result: AsyncSnapshot<TimelineHistoryItemContent>.withError(
            ConnectionState.done,
            error,
            stack,
          ),
        );
      } finally {
        scope.retire();
        await scope.close();
      }
    }
    return null;
  }

  Future<void> _openCurrent(_TimelineRead read, ReadDemand demand) async {
    try {
      final reader = await client.conversations.openCurrentReader(
        read.session.threadId,
        demand: demand,
      );
      read.current = reader;
      if (_ownsRead(read)) await _connectCurrent(read, demand);
    } catch (error) {
      read.currentError = error;
      if (_ownsRead(read)) _current?.currentCollectionError.value = error;
    }
  }

  Future<void> _connectCurrent(_TimelineRead read, ReadDemand demand) {
    final existing = read.currentConnecting;
    if (existing != null) return existing;
    final reader = read.current;
    if (reader == null ||
        !_ownsRead(read) ||
        !identical(_current?._read, read)) {
      return Future<void>.value();
    }
    final connected = Completer<void>();
    read.currentConnecting = connected.future;
    connected.complete(
      Future<void>.sync(() async {
        try {
          await _serialize(() => _applyCurrentView(read, reader.initialView));
          if (_ownsRead(read)) source.publish(source.value);
          await _runCurrentWatch(read, demand);
        } catch (error) {
          if (_ownsRead(read)) {
            _current?.currentCollectionError.value = error;
            _restart(read);
          }
        }
      }),
    );
    return connected.future;
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
              unawaited(_serialize(() => _applyCurrentView(read, view)));
            case ProjectionCurrentFrame(:final revision, :final projection):
              unawaited(
                _serialize(
                  () => _applyCurrentProjection(read, revision, projection),
                ),
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

  void _detach() {
    final consumer = _consumerObservation;
    _consumerObservation = null;
    _observedSession = null;
    consumer?.cancel();
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
}

extension TimelineDisplayCurrentAccess on TimelineDisplayLease {
  CurrentAtomSnapshot _snapshotCurrent(
    CurrentRevision revision,
    CurrentProjection projection, {
    required bool executionActive,
  }) {
    final atoms = projection.atoms.isNotEmpty
        ? projection.atoms
        : _loadedCurrentAtoms;
    return CurrentAtomSnapshot(
      revision: revision.revision,
      currentAtoms: atoms,
      ownerId: revision.ownerId,
      executionPresent: projection.executionPresent,
      executionActive: executionActive,
    );
  }

  Future<void> _applyCurrentRows(
    CurrentRevision revision,
    CurrentProjection projection,
  ) async {
    if (_retired) return;
    final atoms = projection.atoms.isNotEmpty
        ? projection.atoms
        : _loadedCurrentAtoms;
    final executionActive = _read.owner._isExecutionActive(
      _read.session,
      projection: projection,
      loadedAtoms: _loadedCurrentAtoms,
    );
    final streamingText = _read.owner._isTextStreaming(
      _read.session,
      projection: projection,
      loadedAtoms: atoms,
    );
    final snapshot = _snapshotCurrent(
      revision,
      projection,
      executionActive: executionActive,
    );
    final settledTail = (!executionActive || streamingText)
        ? _heldTailWork
        : null;
    if (settledTail != null) _heldTailWork = null;
    final DisplayBlock? settledBlock =
        settledTail != null &&
            _mode == TimelineDisplayMode.live &&
            !_isCommittedInController(settledTail.range.rangeId)
        ? TimelineHistoryProjection.block(
            WorkRangeTimelineItem(settledTail.range),
            cut: settledTail.cut,
          )
        : null;
    DisplayBlock? updatedLiveWork;
    if (executionActive && !streamingText && _heldTailWork != null) {
      final tail = _heldTailWork!;
      updatedLiveWork = TimelineHistoryProjection.liveOpenWorkBlock(
        tail.range,
        cut: tail.cut,
        unfinishedCount: atoms
            .where((atom) => atom.lifecycle is ActiveChatAtom)
            .length,
        summary: liveOpenWork.value?.body is WorkDisplayBlock
            ? (liveOpenWork.value!.body as WorkDisplayBlock).summary
            : null,
      );
    }
    await _mutate(() async {
      if (_retired) return;
      if (settledBlock != null) {
        await _presentation!.applyBlocks([
          settledBlock,
        ], TimelineApplyPlacement.append);
        if (_retired) return;
        _firstOrder ??= settledBlock.blockOrder;
        _recordBatch(TimelineApplyPlacement.append);
      }
      if (_retired) return;
      _setLiveOpenWork(updatedLiveWork);
      live.value = snapshot;
    });
    if (!_retired &&
        settledTail != null &&
        settledBlock == null &&
        _mode == TimelineDisplayMode.history) {
      _read.owner._publishState(hasNewOutput: true);
    }
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
    final scope = _currentQueries ??= openCurrentScope();
    final atomRef = projection.collections
        .where((reference) => reference.collection == 'atoms')
        .firstOrNull;
    if (atomRef != _atomCollection) {
      _atomCollection = atomRef;
      _loadedCurrentAtoms = const [];
      currentCollectionError.value = null;
    }
    if (!_retired) await _applyCurrentRows(revision, projection);
    if (atomRef != null && _loadedCurrentAtoms.isEmpty && !_retired) {
      unawaited(_loadCurrentAtomsPage(scope, atomRef, projection));
    }
  }

  Future<void> _loadCurrentAtomsPage(
    CurrentReadScope scope,
    CurrentCollectionRef reference,
    CurrentProjection projection,
  ) async {
    try {
      await _loadCurrentAtoms(scope, reference);
      final owner = _read.owner;
      await owner._serialize(() async {
        if (_retired ||
            !owner._ownsRead(_read) ||
            !identical(owner._current, this) ||
            reference != _atomCollection) {
          return;
        }
        final latestRevision = _latestCurrentRevision;
        if (latestRevision == null) return;
        currentCollectionError.value = null;
        try {
          await _applyCurrentRows(
            latestRevision,
            _latestCurrentProjection ?? projection,
          );
        } catch (error) {
          throw _TimelineApplyFailure(error);
        }
      });
    } catch (error) {
      final owner = _read.owner;
      if (!_retired &&
          owner._ownsRead(_read) &&
          identical(owner._current, this) &&
          reference == _atomCollection) {
        if (error is _TimelineApplyFailure) {
          owner._publishState(
            connection: TimelineConnectionPhase.failed,
            connectionError: error.cause,
          );
          owner._restart(_read);
        } else {
          currentCollectionError.value = error;
        }
      }
    }
  }

  Future<void> _loadCurrentAtoms(
    CurrentReadScope scope,
    CurrentCollectionRef reference,
  ) async {
    if (_retired || !scope.isActive || reference != _atomCollection) {
      throw const StaleConversationScope();
    }
    final existing = _currentAtomsLoading;
    if (existing != null) {
      if (_currentAtomsLoadingRef == reference) return existing;
      try {
        await existing;
      } catch (_) {
        // This failure belongs to a superseded collection reference. The new
        // reference still needs its own read and must expose its own result.
      }
      return _loadCurrentAtoms(scope, reference);
    }
    final completion = Completer<void>();
    _currentAtomsLoading = completion.future;
    _currentAtomsLoadingRef = reference;
    completion.complete(() async {
      try {
        final page = await scope.pageCollection(
          reference: reference,
          continuation: null,
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
        _loadedCurrentAtoms = List.unmodifiable(atoms);
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
          window.generation != reference.generation ||
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
}

extension TimelineSessionAccess on TimelineSessionOwner {
  bool _hasOpenTailWork(HistoryTimelinePage page) =>
      switch (page.items.firstOrNull) {
        WorkRangeTimelineItem(:final range) => range.beforeSeq == null,
        _ => false,
      };

  bool _isExecutionActive(
    ConversationSession session, {
    CurrentProjection? projection,
    List<CurrentAtom> loadedAtoms = const [],
  }) {
    if (projection != null) {
      if (!projection.executionPresent) return false;
      return projection.logicalStatus != ThreadStatusView.idle ||
          projection.activeTurn != null ||
          projection.sources.any(
            (source) => source.lifecycle is ActiveChatSource,
          ) ||
          projection.atoms.any((atom) => atom.lifecycle is ActiveChatAtom) ||
          loadedAtoms.any((atom) => atom.lifecycle is ActiveChatAtom);
    }
    return session.state.activeTurn != null || session.state.activity != null;
  }

  bool _isTextStreaming(
    ConversationSession session, {
    CurrentProjection? projection,
    List<CurrentAtom> loadedAtoms = const [],
  }) {
    if (projection != null) {
      if (projection.activeTurn?.phase == CurrentTurnPhase.responding) {
        return true;
      }
      final atoms = projection.atoms.isNotEmpty
          ? projection.atoms
          : loadedAtoms;
      if (atoms.any(
        (atom) =>
            atom.lifecycle is ActiveChatAtom &&
            atom.kind == ChatAtomKind.text &&
            atom.contents.isNotEmpty,
      )) {
        return true;
      }
    }
    return session.state.activity?.kind == ThreadActivityKind.responding;
  }

  ({
    List<DisplayBlock> timelineBlocks,
    ({HistoryWorkRange range, HistoryCut cut})? heldTail,
    DisplayBlock? liveWorkBlock,
  })
  _partitionTimelinePage(
    ConversationSession session,
    HistoryTimelinePage page, {
    CurrentProjection? projection,
    String? ownerId,
    TimelineDisplayLease? existingLease,
  }) {
    final loadedAtoms =
        existingLease?._loadedCurrentAtoms ?? const <CurrentAtom>[];
    final active = _isExecutionActive(
      session,
      projection: projection,
      loadedAtoms: loadedAtoms,
    );
    final streamingText = _isTextStreaming(
      session,
      projection: projection,
      loadedAtoms: loadedAtoms,
    );
    final first = page.items.firstOrNull;
    final heldRange =
        first is WorkRangeTimelineItem &&
            first.range.beforeSeq == null &&
            active &&
            !streamingText &&
            (first.range.runId == null ||
                ownerId == null ||
                first.range.runId == ownerId) &&
            !(existingLease?._isCommittedInController(first.range.rangeId) ??
                false)
        ? first.range
        : null;
    if (heldRange == null) {
      return (
        timelineBlocks: TimelineHistoryProjection.blocks(
          page.items.reversed,
          cut: page.cut,
        ),
        heldTail: null,
        liveWorkBlock: null,
      );
    }
    final timelineItems = page.items.skip(1).toList(growable: false);
    final sourceAtoms = (projection?.atoms.isNotEmpty ?? false)
        ? projection!.atoms
        : loadedAtoms;
    final unfinished = sourceAtoms
        .where((atom) => atom.lifecycle is ActiveChatAtom)
        .length;
    return (
      timelineBlocks: TimelineHistoryProjection.blocks(
        timelineItems.reversed,
        cut: page.cut,
      ),
      heldTail: (range: heldRange, cut: page.cut),
      liveWorkBlock: TimelineHistoryProjection.liveOpenWorkBlock(
        heldRange,
        cut: page.cut,
        unfinishedCount: unfinished,
      ),
    );
  }

  Future<void> _applyLatestHistory(
    _TimelineRead read,
    HistoryTimelinePage page,
    CurrentView? view,
    int modeIntent,
  ) async {
    final current = _current;
    if (!_ownsRead(read) ||
        current == null ||
        current.isRetired ||
        !identical(current.history, read.history)) {
      return;
    }
    if (current._mode == TimelineDisplayMode.history) {
      if (current._liveReturnPending && current._modeIntent == modeIntent) {
        await _applyAcceptedLiveWindow(
          read,
          current,
          page,
          view,
          modeIntent: modeIntent,
          transitionFromHistory: true,
          clearPaging: false,
        );
        return;
      }
      final activeView = view;
      final partition = _partitionTimelinePage(
        read.session,
        page,
        projection: activeView?.projection ?? current._latestCurrentProjection,
        ownerId:
            activeView?.revision.ownerId ??
            current._latestCurrentRevision?.ownerId,
        existingLease: current,
      );
      current._heldTailWork = partition.heldTail;
      current._setLiveOpenWork(partition.liveWorkBlock);
      if (view != null) await current._admitCurrentProject(view);
      if (!_ownsRead(read)) return;
      _publishState(
        connection: TimelineConnectionPhase.ready,
        connectionError: null,
        hasNewOutput: page.cut != current._historyCut,
      );
      return;
    }
    // A latest-page read started before entering History uses the same current
    // reader, but its History page is not the fixed browsing window. It still
    // carries the live-output notification needed by Return to live.
    if (current._modeIntent != modeIntent) return;
    await _applyAcceptedLiveWindow(
      read,
      current,
      page,
      view,
      modeIntent: modeIntent,
      transitionFromHistory: false,
      clearPaging: false,
    );
  }

  Future<void> _applyAcceptedLiveWindow(
    _TimelineRead read,
    TimelineDisplayLease current,
    HistoryTimelinePage page,
    CurrentView? view, {
    required int modeIntent,
    required bool transitionFromHistory,
    required bool clearPaging,
  }) async {
    if (!_ownsRead(read) ||
        !identical(_current, current) ||
        current.isRetired ||
        current._modeIntent != modeIntent ||
        transitionFromHistory && !current._liveReturnPending) {
      return;
    }
    final activeProjection =
        view?.projection ?? current._latestCurrentProjection;
    final activeOwnerId =
        view?.revision.ownerId ?? current._latestCurrentRevision?.ownerId;
    final partition = _partitionTimelinePage(
      read.session,
      page,
      projection: activeProjection,
      ownerId: activeOwnerId,
      existingLease: current,
    );
    final executionActive = _isExecutionActive(
      read.session,
      projection: activeProjection,
      loadedAtoms: current._loadedCurrentAtoms,
    );
    final pagingBoundaryChanged =
        current._mode == TimelineDisplayMode.live &&
        (current._historyCut != page.cut || current._before != page.next);
    await current._mutate(() async {
      try {
        await current._presentation!.reconcileBlocks(partition.timelineBlocks);
      } catch (error) {
        throw _TimelineApplyFailure(error);
      }
      current._heldTailWork = partition.heldTail;
      current._setLiveOpenWork(partition.liveWorkBlock);
      if (view != null) {
        current.live.value = current._snapshotCurrent(
          view.revision,
          view.projection,
          executionActive: executionActive,
        );
      }
      current._historyCut = page.cut;
      current._before = page.next;
      current._hasOlder = page.next != null;
      current._firstOrder = current._firstLoadedOrder;
      current._mode = TimelineDisplayMode.live;
      current._liveWindowGeneration++;
      current._liveReturnHistoryIntent = null;
      current._recordBatch(TimelineApplyPlacement.append);
    });
    if (!_ownsRead(read) ||
        !identical(_current, current) ||
        current.isRetired ||
        current._modeIntent != modeIntent) {
      return;
    }
    if (view != null) await current._admitCurrentProject(view);
    if (!_ownsRead(read) ||
        !identical(_current, current) ||
        current.isRetired ||
        current._modeIntent != modeIntent ||
        current._mode != TimelineDisplayMode.live) {
      return;
    }
    _markPresentedInputs(
      read.session.threadId,
      partition.timelineBlocks,
      const [],
    );
    _publishState(
      connection: TimelineConnectionPhase.ready,
      connectionError: null,
      hasNewOutput: false,
      isLoadingOlder: clearPaging ? false : null,
      olderError: clearPaging || pagingBoundaryChanged ? null : _unset,
    );
  }

  Future<void> _set(
    _TimelineRead read,
    ({
      List<DisplayBlock> timelineBlocks,
      ({HistoryWorkRange range, HistoryCut cut})? heldTail,
      DisplayBlock? liveWorkBlock,
    })
    partition, {
    required HistoryCut cut,
    required String? olderCursor,
    TimelinePreparedHistoryItem? initialContent,
    CurrentView? initialCurrent,
  }) async {
    final session = read.session;
    final next = TimelineDisplayLease._(
      read: read,
      threadId: session.threadId,
      generation: ++_generation,
      demand: _readDemand!,
      history: read.history!,
      selectionId: _selectionTarget == session.threadId
          ? _visibleSelectionId
          : null,
      selectionStartedMicros: _selectionTarget == session.threadId
          ? _selectionStartedMicros
          : null,
      initialHistoryContent: initialContent,
    );
    next._heldTailWork = partition.heldTail;
    next._setLiveOpenWork(partition.liveWorkBlock);
    if (initialCurrent != null) {
      next._latestCurrentRevision = initialCurrent.revision;
      next._latestCurrentProjection = initialCurrent.projection;
      next.live.value = next._snapshotCurrent(
        initialCurrent.revision,
        initialCurrent.projection,
        executionActive: _isExecutionActive(
          session,
          projection: initialCurrent.projection,
        ),
      );
    }
    final blocks = partition.timelineBlocks;
    _preparingDisplays.add(next);
    try {
      final presentation = next._presentation!;
      await next._mutate(() async {
        try {
          await presentation.applyBlocks(blocks, TimelineApplyPlacement.set);
        } catch (error) {
          throw _TimelineApplyFailure(error);
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
    next._historyCut = cut;
    next._before = olderCursor;
    next._firstOrder = blocks.firstOrNull?.blockOrder;
    next._recordBatch(TimelineApplyPlacement.set);
    next._hasOlder = olderCursor != null;
    final previous = _current;
    next._mode = previous?.mode ?? TimelineDisplayMode.live;
    _current = next;
    next.currentCollectionError.value = read.currentError;
    _markPresentedInputs(session.threadId, blocks, const []);
    _olderInFlight = null;
    if (previous != null) _retire(previous);
    if (!_ownsRead(read) || !identical(_current, next) || next.isRetired) {
      return;
    }
    _publishState(
      connection: TimelineConnectionPhase.ready,
      connectionError: null,
      isLoadingOlder: false,
      olderError: null,
      hasNewOutput: false,
    );
  }

  void _markPresentedInputs(
    String threadId,
    List<DisplayBlock> history,
    List<CurrentAtom> currentAtoms,
  ) {
    final inputIds = <String>[
      for (final block in history)
        if (block.body case SingleDisplayBlock(:final record))
          if (record.atom.source case InputChatSource(:final inputId)) inputId,
      for (final atom in currentAtoms)
        if (atom.source case InputChatSource(:final inputId)) inputId,
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

  Future<void> enterHistory(String threadId) async {
    final current = lease(threadId);
    if (current == null) return;
    // Cancel even a return that is still waiting for the paging slot.
    current._historyScrollIntent++;
    final read = _consumerObservation;
    try {
      await _serialize(() async {
        if (!identical(_current, current) || current.isRetired) return;
        final freezeCurrent = current._mode == TimelineDisplayMode.live;
        final invalidateReturn = current._liveReturnHistoryIntent != null;
        if (!freezeCurrent && !invalidateReturn) return;
        current.enterHistoryMode();
        if (freezeCurrent) {
          _publishState(hasNewOutput: false);
        }
      });
    } catch (error) {
      if (identical(_current, current) &&
          !current.isRetired &&
          read != null &&
          _ownsRead(read)) {
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error is _TimelineApplyFailure ? error.cause : error,
        );
        _restart(read);
        rethrow;
      }
    }
  }

  /// Confirms the live window after admission by the original History reader.
  Future<bool> returnToLive(String threadId) async {
    final current = lease(threadId);
    final read = _consumerObservation;
    if (current == null ||
        read == null ||
        !_ownsRead(read) ||
        !identical(current.history, read.history)) {
      return false;
    }
    final historyIntent = current._historyScrollIntent;
    await _readSlot((
      current,
      current._liveWindowGeneration,
      historyIntent,
      'return-live',
    ), () => _reloadLatestWindow(current, read, historyIntent));
    return _ownsRead(read) &&
        identical(lease(threadId), current) &&
        current._historyScrollIntent == historyIntent &&
        current._mode == TimelineDisplayMode.live &&
        !current._liveReturnPending;
  }

  Future<void> _reloadLatestWindow(
    TimelineDisplayLease current,
    _TimelineRead read,
    int historyIntent,
  ) async {
    int? modeIntent;
    int? liveGeneration;
    TimelineDisplayMode? sourceMode;
    try {
      await _serialize(() async {
        if (!identical(_current, current) ||
            current.isRetired ||
            !_ownsRead(read) ||
            current._historyScrollIntent != historyIntent) {
          return;
        }
        if (current._mode == TimelineDisplayMode.live &&
            !current._liveReturnPending &&
            !(source.value?.hasNewOutput ?? false)) {
          return;
        }
        sourceMode = current._mode;
        liveGeneration = current._liveWindowGeneration;
        modeIntent = current.requestLiveWindow();
      });
      final requestedMode = sourceMode;
      final requestedGeneration = liveGeneration;
      final requestedIntent = modeIntent;
      if (requestedMode == null ||
          requestedGeneration == null ||
          requestedIntent == null) {
        return;
      }
      final scope = current._historyQueries;
      if (scope == null || !scope.isActive) return;
      final demand = _readDemand ?? current.demand;
      final page = await scope.timelinePage(
        demand: HistoryDemand(
          maxRows: demand.maxItems,
          maxBytes: demand.maxBytes,
        ),
      );
      final view = await current.current?.snapshot(demand);
      if (!_ownsRead(read) ||
          current._modeIntent != requestedIntent ||
          current._mode != requestedMode ||
          !current._liveReturnPending) {
        return;
      }
      await _serialize(() async {
        if (!identical(_current, current) ||
            current.isRetired ||
            !_ownsRead(read) ||
            current._modeIntent != requestedIntent ||
            current._mode != requestedMode ||
            !current._liveReturnPending) {
          return;
        }
        // A newer accepted live page wins over this older return query.
        if (current._liveWindowGeneration != requestedGeneration) return;
        await _applyAcceptedLiveWindow(
          read,
          current,
          page,
          view,
          modeIntent: requestedIntent,
          transitionFromHistory: requestedMode == TimelineDisplayMode.history,
          clearPaging: true,
        );
      });
    } catch (error) {
      final requestedMode = sourceMode;
      final requestedIntent = modeIntent;
      if (requestedMode != null &&
          requestedIntent != null &&
          _ownsRead(read) &&
          current._modeIntent == requestedIntent &&
          current._mode == requestedMode &&
          current._liveReturnPending) {
        current._liveReturnHistoryIntent = null;
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error is _TimelineApplyFailure ? error.cause : error,
        );
        // A failed query never changed the loaded history. Keep the reading
        // window so the same action can retry. A partial apply needs a new Set.
        if (error is _TimelineApplyFailure) _restart(read);
        rethrow;
      }
    }
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
      current._historyScrollIntent,
      current._liveWindowGeneration,
      'older',
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
    final read = _consumerObservation;
    if (read == null || !identical(current.history, read.history)) return;
    bool active() =>
        identical(_current, current) && !current.isRetired && _ownsRead(read);

    ({
      HistoryCut? cut,
      String before,
      TimelineDisplayMode mode,
      int modeIntent,
      int liveGeneration,
      int maxRows,
      int maxBytes,
    })?
    request;
    // Capture after earlier commits, including the pause from the user scroll
    // that requested this page. Automatic filling borrows the live cut.
    await _serialize(() async {
      final before = current._before;
      final state = source.value;
      if (!active() ||
          !current.hasOlder ||
          before == null ||
          state?.connection != TimelineConnectionPhase.ready ||
          (!retry && state?.olderError != null)) {
        return;
      }
      final demand = _readDemand ?? current.demand;
      final maxRows = current._mode == TimelineDisplayMode.live
          ? min(demand.maxItems, current._historyRowLimit - current.loadedCount)
          : demand.maxItems;
      if (maxRows <= 0) return;
      request = (
        cut: current._historyCut,
        before: before,
        mode: current._mode,
        modeIntent: current._modeIntent,
        liveGeneration: current._liveWindowGeneration,
        maxRows: maxRows,
        maxBytes: demand.maxBytes,
      );
      _publishState(isLoadingOlder: true, olderError: null);
    });
    final window = request;
    if (window == null) return;
    bool ownsWindow() =>
        active() &&
        source.value?.connection == TimelineConnectionPhase.ready &&
        current._historyCut == window.cut &&
        current._before == window.before &&
        current._mode == window.mode &&
        current._modeIntent == window.modeIntent &&
        current._liveWindowGeneration == window.liveGeneration;

    try {
      final scope = current._historyQueries;
      if (scope == null) {
        throw const StaleConversationScope();
      }
      final cut = window.cut;
      if (cut == null) {
        throw const ConversationContinuityError(
          'History window has no fixed cut',
        );
      }
      final page = await scope.timelinePage(
        cut: cut,
        cursor: window.before,
        demand: HistoryDemand(
          maxRows: window.maxRows,
          maxBytes: window.maxBytes,
        ),
      );
      if (!ownsWindow() || !scope.isActive) return;
      await _serialize(() async {
        if (!ownsWindow() || !scope.isActive) return;
        if (page.next == window.before ||
            page.items.any(
              (item) => switch (item) {
                DividerTimelineItem(:final event) => event.eventId.isEmpty,
                WorkRangeTimelineItem(:final range) => range.rangeId.isEmpty,
              },
            )) {
          throw const ConversationContinuityError('Invalid history page');
        }
        if (page.cut != cut) {
          throw const ConversationContinuityError(
            'History older page changed its fixed cut',
          );
        }
        final blocks = TimelineHistoryProjection.blocks(
          page.items.reversed,
          cut: cut,
        );
        if (window.mode == TimelineDisplayMode.live &&
            blocks.length > window.maxRows) {
          throw const ConversationContinuityError(
            'History older page exceeded the live window demand',
          );
        }
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
            if (window.mode == TimelineDisplayMode.history) {
              await current._presentation!.trimNewest(
                current.loadedCount - current._historyRowLimit,
              );
            }
          } catch (error) {
            throw _TimelineApplyFailure(error);
          }
        });
        if (!ownsWindow() || !scope.isActive) return;
        if (blocks.isNotEmpty) {
          current._firstOrder = blocks.first.blockOrder;
        }
        current._before = page.next;
        current._hasOlder = page.next != null;
        current._recordBatch(TimelineApplyPlacement.prepend);
      });
    } catch (error) {
      if (ownsWindow()) {
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

final class _TimelineRead {
  _TimelineRead(this.owner, this.selection, this.session, this.restarts);
  final ClientResourceId resourceId = _newTimelineResourceId();
  final TimelineSessionOwner owner;
  final int selection;
  final ConversationSession session;
  final int restarts;
  HistoryReader? history;
  CurrentReader? current;
  Future<void>? currentOpening;
  Future<void>? currentConnecting;
  Object? currentError;
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
  bool isCancelled = false;
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
          // Openers retain late handles; cancellation cannot abandon their close duty.
          await currentOpening;
          await currentConnecting;
          final historyReader = history;
          final currentReader = current;
          final watch = currentWatch;
          currentReader?.requestClose();
          watch?.requestClose();
          await Future.wait<void>([
            if (historyReader != null) historyReader.close(),
            if (currentReader != null) currentReader.close(),
            if (watch != null) watch.close(),
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

final class HistoryWorkRangeMembers implements DisplayMembers {
  HistoryWorkRangeMembers._(this.scope, this.reference, this.demand);

  static Future<HistoryWorkRangeMembers> open(
    HistoryReadScope scope, {
    required DisplayBlockRef reference,
    required ReadDemand demand,
  }) async {
    if (reference.blockId.isEmpty || !scope.isActive) {
      throw const StaleConversationScope();
    }
    return HistoryWorkRangeMembers._(scope, reference, demand);
  }

  final HistoryReadScope scope;
  final DisplayBlockRef reference;
  final ReadDemand demand;
  List<DisplayMemberHead>? _folded;
  int _offset = 0;
  bool _done = false;
  bool _closed = false;

  @override
  Future<DisplayMemberBatch?> next() async {
    if (_closed || !scope.isActive || _done) {
      return null;
    }
    var folded = _folded;
    if (folded == null) {
      final rangeEvents = await _loadAllRangeEvents();
      if (_closed || !scope.isActive) return null;
      final backfilledByCall = <String, List<HistoryEventRecord>>{};
      final attemptedBackfills = <String>{};
      var result = WorkGroupEventFolder.fold(
        rangeEvents: rangeEvents,
        backfilledCallEvents: backfilledByCall,
        attemptedCallBackfills: attemptedBackfills,
      );
      if (result.missingCallIds.isNotEmpty) {
        var added = false;
        for (final callId in result.missingCallIds) {
          attemptedBackfills.add(callId);
          final fetched = await _loadCallEvents(callId);
          if (_closed || !scope.isActive) return null;
          if (fetched.isNotEmpty) {
            backfilledByCall[callId] = fetched;
            added = true;
          }
        }
        if (added) {
          result = WorkGroupEventFolder.fold(
            rangeEvents: rangeEvents,
            backfilledCallEvents: backfilledByCall,
            attemptedCallBackfills: attemptedBackfills,
          );
        }
      }
      folded = _folded = result.entries;
    }

    if (folded.isEmpty) {
      _done = true;
      return DisplayMemberBatch(
        block: reference,
        offset: _offset,
        complete: true,
        entries: const [],
      );
    }
    final limit = demand.maxItems > 0 ? demand.maxItems : 1;
    final start = _offset;
    final end = min(start + limit, folded.length);
    final entries = folded.sublist(start, end);
    _offset = end;
    _done = end >= folded.length;
    return DisplayMemberBatch(
      block: reference,
      offset: start,
      complete: _done,
      entries: entries,
    );
  }

  Future<List<HistoryEventRecord>> _loadAllRangeEvents() async {
    final collected = <HistoryEventRecord>[];
    final seenEventIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    while (true) {
      if (_closed) return collected;
      if (!scope.isActive) throw const StaleConversationScope();
      final previousCursor = cursor;
      final page = await scope.workRangePage(
        afterSeq: reference.afterSeq,
        beforeSeq: reference.beforeSeq,
        cut: reference.cut,
        cursor: cursor,
        demand: HistoryDemand(
          maxRows: demand.maxItems,
          maxBytes: demand.maxBytes,
        ),
      );
      if (page.cut != reference.cut ||
          page.afterSeq != reference.afterSeq ||
          page.beforeSeq != reference.beforeSeq) {
        throw const ConversationContinuityError(
          'History work range page changed its fixed cut or bounds',
        );
      }
      if (page.next?.isEmpty ?? false) {
        throw const ConversationContinuityError(
          'History work range page returned an empty cursor',
        );
      }
      if (page.next != null &&
          (page.next == previousCursor ||
              !seenCursors.add(page.next!) ||
              page.events.isEmpty)) {
        throw const ConversationContinuityError(
          'History work range page made no bounded cursor progress',
        );
      }
      // workRangePage returns raw work events in ascending seq order.
      for (final event in page.events) {
        if (event.eventId.isEmpty) {
          throw const ConversationContinuityError(
            'History work range returned an empty event identity',
          );
        }
        if (seenEventIds.add(event.eventId)) {
          collected.add(event);
        }
      }
      cursor = page.next;
      if (cursor == null) return collected;
    }
  }

  Future<List<HistoryEventRecord>> _loadCallEvents(String callId) async {
    final collected = <HistoryEventRecord>[];
    final seenEventIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    try {
      while (true) {
        if (_closed) return collected;
        if (!scope.isActive) throw const StaleConversationScope();
        final page = await scope.eventsPage(
          query: CallHistoryEvents(callId),
          cut: reference.cut,
          cursor: cursor,
          demand: HistoryDemand(
            maxRows: demand.maxItems,
            maxBytes: demand.maxBytes,
          ),
        );
        if (page.cut != reference.cut) return collected;
        for (final event in page.entries) {
          if (event.eventId.isNotEmpty && seenEventIds.add(event.eventId)) {
            collected.add(event);
          }
        }
        final next = page.next;
        if (next == null || next.isEmpty || !seenCursors.add(next)) {
          return collected;
        }
        if (page.entries.isEmpty) return collected;
        cursor = next;
      }
    } on StaleConversationScope {
      rethrow;
    } on ClientResourceClosed {
      rethrow;
    } catch (_) {
      // Single missing/failed call backfill falls back gracefully to in-range events.
      return collected;
    }
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
