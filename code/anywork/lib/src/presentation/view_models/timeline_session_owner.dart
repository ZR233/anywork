import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show Key, ValueKey, ValueNotifier;
import 'package:flutter/widgets.dart' show ScrollController, WidgetsBinding;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_display_diagnostics.dart';
import '../../features/conversation/timeline/state/timeline_display_unit.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/view_models/timeline_message_controller.dart';

export '../../features/conversation/timeline/state/timeline_view_state.dart';

const Object _unset = Object();

/// One presentation generation. Only its component controller owns loaded messages.
final class TimelineDisplayLease implements TimelineUiControllers {
  TimelineDisplayLease({
    required this.threadId,
    required this.generation,
    required this.demand,
    required this.content,
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
  }

  final String threadId;
  final int generation;
  final ReadDemand demand;
  final ConversationContent content;
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

  /// Published only by this display's serial admission, never directly by the transport.
  final ValueNotifier<LiveDisplayWindow?> live = ValueNotifier(null);
  final Map<String, TimelineExpansionIntent> _expansions = {};
  final Set<ConversationQueryScope> _ownedQueries = {};
  final Map<ConversationQueryScope, Future<void>> _closingQueries = {};
  ConversationQueryScope? _queries;
  String? _before;
  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  bool _hasOlder = false;
  bool _mounted = false;
  bool _retired = false;
  bool _disposed = false;
  int _mutations = 0;
  Object? queryCleanupError;
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
    final scope = queries;
    if (scope is! TimelineQueryScope) {
      throw const StaleConversationScope();
    }
    final members = await scope.openDisplayMembers(
      reference: reference,
      window: window,
      demand: demand,
    );
    if (_retired || !scope.isActive) {
      members.requestClose();
      await members.close();
      throw const StaleConversationScope();
    }
    return members;
  }

  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    ReadDemand? demand,
  }) async {
    final scope = queries;
    if (scope is! TimelineQueryScope) {
      throw const StaleConversationScope();
    }
    final page = await scope.loadLiveOlder(
      before: before,
      demand: demand ?? this.demand,
    );
    if (_retired || !scope.isActive) {
      throw const StaleConversationScope();
    }
    return page;
  }

  Iterable<TimelineGroupDisplay> get groupDisplays => _retired
      ? const []
      : _groupDisplays.where((display) => display.isCurrent);

  void _bindUnit(TimelineDisplayUnit unit) {
    final intent = unit.expansion;
    // The same disclosure capability crosses live/history parents. Its queries
    // and callbacks are installed once, independent of header replacements.
    if (intent.isDisplayActive != null) return;
    ConversationQueryScope? bodyScope;
    Object? bodyGeneration;
    intent.retireBody = () {
      final original = bodyScope;
      bodyScope = null;
      bodyGeneration = null;
      if (original == null) return;
      original.retire();
      unawaited(_settleQueries(original));
    };
    intent.readBody = (generation, reference, range) async {
      if (_retired ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration)) {
        throw const StaleConversationScope();
      }
      if (!identical(bodyGeneration, generation)) {
        intent.retireBody!();
        bodyScope = openDetailQueries();
        bodyGeneration = generation;
      }
      final original = bodyScope;
      if (original == null || !original.isActive) {
        throw const StaleConversationScope();
      }
      final value = await original.readContent(
        reference: reference,
        range: range,
      );
      if (_retired ||
          intent.current == null ||
          !intent.bodyActive ||
          !identical(generation, intent.bodyGeneration) ||
          !identical(bodyScope, original) ||
          !original.isActive) {
        throw const StaleConversationScope();
      }
      return value;
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

  void _recordBatch(ChatPlacement placement) {
    switch (placement) {
      case ChatPlacement.set:
        _appliedSets++;
      case ChatPlacement.prepend:
        _appliedPrepends++;
      case ChatPlacement.append:
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

  ConversationQueryScope? get queries {
    if (_retired) return null;
    final existing = _queries;
    if (existing != null && existing.isActive) return existing;
    if (existing != null) unawaited(_settleQueries(existing));
    final scope = content.openScope(generation: generation);
    _ownedQueries.add(scope);
    return _queries = scope;
  }

  ConversationQueryScope? openDetailQueries() {
    if (_retired) return null;
    final scope = content.openScope(generation: generation);
    _ownedQueries.add(scope);
    return scope;
  }

  Future<void> closeDetailQueries(ConversationQueryScope scope) async {
    await _settleQueries(scope);
    if (_ownedQueries.contains(scope)) {
      throw StateError('History reader has not closed: $queryCleanupError');
    }
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
      _queries = null;
    }
    for (final scope in _ownedQueries.toList()) {
      scope.retire();
      unawaited(_settleQueries(scope));
    }
    _releaseIfReady();
    return _released.future;
  }

  Future<void> _settleQueries(ConversationQueryScope scope) {
    if (!_ownedQueries.contains(scope)) return Future.value();
    final existing = _closingQueries[scope];
    if (existing != null) return existing;
    final task = _closeQuery(scope);
    _closingQueries[scope] = task;
    return task;
  }

  Future<void> _closeQuery(ConversationQueryScope scope) async {
    scope.retire();
    try {
      final report = await scope.close();
      if (report.complete) {
        _ownedQueries.remove(scope);
        if (_ownedQueries.isEmpty) queryCleanupError = null;
      } else {
        queryCleanupError = report;
      }
    } catch (error) {
      queryCleanupError = error;
    } finally {
      _closingQueries.remove(scope);
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
  Observation? _connectionObservation;
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
    final result = _commits.then((_) => commit());
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
    final previousConnection = _connectionObservation;
    final previous = _current;
    final preparing = _preparingDisplays.toList();
    _consumerObservation = null;
    _connectionObservation = null;
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
    previousConnection?.cancel();
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
    final watched = session.content.state.watchLatest((state) {
      if (_selected(selection, session)) _onConnection(state);
    });
    if (!_selected(selection, session)) {
      watched.observation.cancel();
      return;
    }
    _connectionObservation = watched.observation;
    _onConnection(watched.value);
    if (_selected(selection, session)) _attachConsumer(selection, session);
  }

  void _attachConsumer(int selection, ConversationSession session) {
    // attachConsumer may synchronously open a feed and notify SDK observers
    // before returning its lease. A nested selection waits for this one local
    // acquisition to return, so A -> B -> A cannot bind over its provisional A.
    final demand = _readDemand;
    if (_bindingConsumer || !_selected(selection, session) || demand == null) {
      return;
    }
    _bindingConsumer = true;
    try {
      final content = session.content;
      if (content is! TimelineContent) {
        throw const ConversationContinuityError(
          'Native timeline requires the presentation feed',
        );
      }
      final observation = content.attachTimelineConsumer(
        _TimelineConsumer(this, selection, session),
        demand: demand,
      );
      if (_selected(selection, session)) {
        _consumerObservation = observation;
      } else {
        observation.cancel();
      }
    } catch (error) {
      if (_selected(selection, session)) {
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error,
        );
      }
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

  void _detach() {
    final consumer = _consumerObservation;
    final connection = _connectionObservation;
    _consumerObservation = null;
    _connectionObservation = null;
    _observedSession = null;
    connection?.cancel();
    consumer?.cancel();
  }

  void _onConnection(ChatUiState<bool> state) {
    final phase = switch (state) {
      ChatIdle<bool>() => TimelineConnectionPhase.idle,
      ChatOpening<bool>() => TimelineConnectionPhase.opening,
      ChatReady<bool>() => TimelineConnectionPhase.ready,
      ChatReconnecting<bool>() => TimelineConnectionPhase.reconnecting,
      ChatFailed<bool>() => TimelineConnectionPhase.failed,
      ChatClosed<bool>() => TimelineConnectionPhase.closed,
    };
    final error = switch (state) {
      ChatReconnecting<bool>(:final error) ||
      ChatFailed<bool>(:final error) => error,
      _ => null,
    };
    _publishState(connection: phase, connectionError: error);
  }

  Future<void> _accept(
    int selection,
    ConversationSession session,
    TimelineBatch batch,
    LiveDisplayWindow live,
  ) => _serialize(() async {
    if (!_selected(selection, session)) return;
    if (batch.placement == ChatPlacement.set) {
      await _set(selection, session, batch, live);
      return;
    }
    final current = _current;
    if (current == null || current.isRetired) {
      throw const ConversationContinuityError('Chat has no active display');
    }
    final presentation = current._presentation!;
    await current._mutate(() async {
      // The component API reports validation failures through its Future even
      // though its in-memory mutation contains no await. Commit live only after
      // successful admission; the completed microtasks precede the next frame.
      // No content query, layout or animation is part of this commit.
      if (batch.blocks.isNotEmpty) {
        await presentation.applyTimeline(batch);
      }
      if (!_selected(selection, session) ||
          !identical(_current, current) ||
          current.isRetired) {
        return;
      }
      current.live.value = live;
    });
    if (!_selected(selection, session) ||
        !identical(_current, current) ||
        current.isRetired) {
      return;
    }
    if (batch.blocks.isNotEmpty || batch.placement != ChatPlacement.append) {
      current._recordBatch(batch.placement);
    }
    _markPresentedInputs(session.threadId, batch);
    if (batch.placement == ChatPlacement.prepend) {
      current._before = batch.before;
      current._hasOlder = batch.before != null;
      _publishState(isLoadingOlder: false, olderError: null);
    } else if (batch.blocks.isNotEmpty) {
      _publishState(hasNewOutput: current.mode == TimelineDisplayMode.history);
    }
  });

  Future<void> _set(
    int selection,
    ConversationSession session,
    TimelineBatch batch,
    LiveDisplayWindow live,
  ) async {
    final next = TimelineDisplayLease(
      threadId: session.threadId,
      generation: ++_generation,
      demand: _readDemand!,
      content: session.content,
      selectionId: _selectionTarget == session.threadId
          ? _visibleSelectionId
          : null,
      selectionStartedMicros: _selectionTarget == session.threadId
          ? _selectionStartedMicros
          : null,
    );
    _preparingDisplays.add(next);
    try {
      final presentation = next._presentation!;
      await next._mutate(() async {
        await presentation.applyTimeline(batch);
        next.live.value = live;
      });
    } catch (_) {
      _preparingDisplays.remove(next);
      _retire(next);
      rethrow;
    }
    _preparingDisplays.remove(next);
    if (!_selected(selection, session)) {
      _retire(next);
      return;
    }
    next._before = batch.before;
    next._recordBatch(batch.placement);
    next._hasOlder = batch.before != null;
    final previous = _current;
    next._mode = previous?.mode ?? TimelineDisplayMode.live;
    _current = next;
    _markPresentedInputs(session.threadId, batch);
    _olderInFlight = null;
    if (previous != null) _retire(previous);
    _publishState(isLoadingOlder: false, olderError: null, hasNewOutput: false);
  }

  void _markPresentedInputs(String threadId, TimelineBatch batch) {
    final inputIds = <String>[
      for (final block in batch.blocks)
        if (block.body case SingleDisplayBlock(:final record))
          if (record.atom.source case InputChatSource(:final inputId)) inputId,
      for (final block in batch.live?.blocks ?? const <LiveDisplayBlock>[])
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
      final scope = current.queries;
      if (scope is! TimelineQueryScope) {
        throw const StaleConversationScope();
      }
      // The SDK performs IO outside admission, then resolves only after the same
      // captured consumer applied the Prepend. Do not insert the returned batch twice.
      await scope.loadTimelineOlder(
        before: before,
        demand: _readDemand ?? current.demand,
      );
      if (!identical(_current, current) ||
          current.isRetired ||
          !scope.isActive) {
        return;
      }
      if (current._before == before) {
        throw const ConversationContinuityError('History page did not advance');
      }
      _publishState(isLoadingOlder: false, olderError: null);
    } catch (error) {
      if (identical(_current, current) && !current.isRetired) {
        _publishState(isLoadingOlder: false, olderError: error);
      }
    } finally {
      if (identical(_current, current) &&
          source.value?.isLoadingOlder == true) {
        _publishState(isLoadingOlder: false);
      }
    }
  }

  Future<CloseReport> close({DateTime? deadline}) {
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
        return _join(leases, deadline);
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
    DateTime? deadline,
  ) async {
    final pending = Future.wait<void>([
      _commits,
      ?_olderInFlight,
      for (final lease in leases) lease.released,
    ]);
    if (deadline == null) {
      await pending;
    } else {
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        try {
          await pending.timeout(remaining);
        } on TimeoutException {
          // All owners and native close obligations remain retained for retry.
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (final lease in leases)
          if (!lease.isReleased)
            UnresolvedResource(
              owner: 'timeline-display:${lease.threadId}',
              attemptId: AttemptId(lease.generation),
              reason: StateError(
                'Display is not released: '
                '${lease.queryCleanupError ?? "waiting for operations/subtree detach"}',
              ),
            ),
      ],
    );
  }
}

final class _TimelineConsumer implements TimelineBatchConsumer {
  const _TimelineConsumer(this.owner, this.selection, this.session);
  final TimelineSessionOwner owner;
  final int selection;
  final ConversationSession session;
  @override
  Future<void> applyTimeline(TimelineBatch batch, LiveDisplayWindow live) =>
      owner._accept(selection, session, batch, live);
}
