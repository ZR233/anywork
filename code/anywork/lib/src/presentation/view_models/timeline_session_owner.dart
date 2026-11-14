import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show Key, ValueKey, ValueNotifier;
import 'package:flutter/widgets.dart' show ScrollController, WidgetsBinding;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/live_status/live_status_state.dart'
    show LiveStatusView;
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_display_diagnostics.dart';
import '../../features/conversation/timeline/state/timeline_display_unit.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/view_models/timeline_message_controller.dart';

export '../../features/conversation/timeline/state/timeline_view_state.dart';

const Object _unset = Object();

/// Component futures may fail after a partial mutation. Their response cannot be replayed.
final class _TimelineApplyFailure implements Exception {
  const _TimelineApplyFailure(this.cause);
  final Object cause;
}

/// One presentation generation. Only its component controller owns loaded messages.
final class TimelineDisplayLease
    implements TimelineUiControllers, ConversationQueries {
  TimelineDisplayLease({
    required this.threadId,
    required this.generation,
    required this.demand,
    required this.reader,
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

  @override
  final String threadId;
  final int generation;
  final ReadDemand demand;
  final TimelineReader reader;
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

  /// Published only by this display's serial admission, never directly by the transport.
  final ValueNotifier<TailSnapshot?> live = ValueNotifier(null);
  final Map<String, TimelineExpansionIntent> _expansions = {};
  final Set<ConversationQueryScope> _ownedQueries = {};
  final Map<ConversationQueryScope, Future<void>> _closingQueries = {};
  ConversationQueryScope? _queries;
  String? _before;
  int? _firstOrder;
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

  Future<TailSnapshot> loadLiveOlder({
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

  @override
  ConversationQueryScope openScope({required int generation}) {
    if (_retired) throw const StaleConversationScope();
    _ownedQueries.removeWhere(
      (scope) => scope is ConversationReadScope && scope.isSettled,
    );
    final scope = ConversationReadScope(
      threadId: threadId,
      generation: generation,
      reader: reader.reader,
      timeline: reader,
      isEligible: () => !_retired,
    );
    _ownedQueries.add(scope);
    return scope;
  }

  ConversationQueryScope? get queries {
    if (_retired) return null;
    final existing = _queries;
    if (existing != null && existing.isActive) return existing;
    if (existing != null) unawaited(_settleQueries(existing));
    final scope = openScope(generation: generation);
    _ownedQueries.add(scope);
    return _queries = scope;
  }

  ConversationQueryScope? openDetailQueries() {
    if (_retired) return null;
    final scope = openScope(generation: generation);
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
      final reader = await client.conversations.openTimelineReader(
        read.session.threadId,
        demand: demand,
      );
      read.reader = reader;
      if (!_ownsRead(read)) return;
      final metadata = reader.metadata;
      if (metadata.presentationVersion != presentationVersion ||
          metadata.readerProtocolVersion != timelineReaderProtocolVersion ||
          metadata.readerId.isEmpty) {
        throw const ConversationContinuityError(
          'Unsupported timeline reader handshake',
        );
      }
      read.cursor = metadata.initialCursor;
      var failures = 0;
      while (_ownsRead(read)) {
        ViewUpdate update;
        try {
          update = await reader.next(after: read.cursor!);
          failures = 0;
        } catch (error) {
          if (!_ownsRead(read)) break;
          if (error is StudioFailure && error.retryable && failures++ < 3) {
            continue; // Same capability and applied cursor replay the original response.
          }
          rethrow;
        }
        if (!_ownsRead(read)) break;
        await _serialize(() => _applyUpdate(read, update));
      }
    } catch (error) {
      if (_ownsRead(read)) {
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error is _TimelineApplyFailure ? error.cause : error,
        );
        if (read.restarts < 1 &&
            (error is _TimelineApplyFailure ||
                studioFailureReason(error) ==
                    StudioFailureReason.conversationResyncRequired)) {
          read.cancel();
          _attachConsumer(
            read.selection,
            read.session,
            restarts: read.restarts + 1,
          );
        }
      }
    } finally {
      read.reader?.requestClose();
      try {
        await read.reader?.close();
        _reads.remove(read);
      } catch (error) {
        read.closeError = error;
      }
    }
  }

  void _detach() {
    final consumer = _consumerObservation;
    _consumerObservation = null;
    _observedSession = null;
    consumer?.cancel();
  }

  Future<void> _applyUpdate(_TimelineRead read, ViewUpdate update) async {
    if (!_ownsRead(read)) return;
    if (read.cursor == update.next) return;
    final history = update.history;
    final isSet = history.placement == HistoryPlacement.set;
    var valid =
        update.presentationVersion == presentationVersion &&
        update.readerProtocolVersion == timelineReaderProtocolVersion &&
        read.cursor == update.after &&
        update.next != update.after &&
        update.next.value.isNotEmpty &&
        history.throughOrder >= 0 &&
        history.throughOrder <= 0x7fffffffffffffff &&
        (isSet
            ? read.through == null &&
                  history.fromOrder == null &&
                  update.tail is ReplaceTail
            : read.through != null &&
                  history.fromOrder == read.through &&
                  history.throughOrder >= read.through! &&
                  history.before == null);
    final ids = <String>{};
    var order = history.fromOrder ?? 0;
    for (final block in history.blocks) {
      valid =
          valid &&
          block.id.isNotEmpty &&
          ids.add(block.id) &&
          block.blockOrder > order &&
          block.blockOrder <= history.throughOrder;
      order = block.blockOrder;
    }
    final previous = _current?.live.value;
    TailSnapshot? tail;
    switch (update.tail) {
      case ReplaceTail(:final snapshot):
        tail = snapshot;
        valid =
            valid &&
            snapshot.readyFrontier == history.throughOrder &&
            snapshot.revision >= 0 &&
            snapshot.layoutRevision >= 0 &&
            (isSet ||
                previous == null ||
                (snapshot.layoutRevision >= previous.layoutRevision &&
                    snapshot.revision >= previous.revision));
        var last = history.throughOrder;
        String? work;
        var works = 0;
        for (final block in snapshot.blocks) {
          valid =
              valid &&
              block.id.isNotEmpty &&
              ids.add(block.id) &&
              block.blockOrder > last &&
              block.blockOrder <= 0x7fffffffffffffff;
          last = block.blockOrder;
          if (block.state == DisplayBlockState.open &&
              block.body is WorkDisplayBlock) {
            work = block.id;
            works++;
          }
        }
        valid = valid && works <= 1 && snapshot.currentWorkId == work;
      case KeepTail():
        valid =
            valid &&
            previous != null &&
            !isSet &&
            history.throughOrder > read.through!;
        if (previous != null) {
          tail = TailSnapshot(
            revision: previous.revision,
            layoutRevision: previous.layoutRevision,
            readyFrontier: previous.readyFrontier,
            executionPresent: previous.executionPresent,
            currentWorkId: ids.contains(previous.currentWorkId)
                ? null
                : previous.currentWorkId,
            blocks: previous.blocks.where((b) => !ids.contains(b.id)).toList(),
            older: previous.older,
          );
        }
      case TailStatus(
        :final baseLayoutRevision,
        :final revision,
        :final currentWorkId,
        :final thinkingSummary,
      ):
        valid =
            valid &&
            previous != null &&
            !isSet &&
            history.blocks.isEmpty &&
            history.throughOrder == read.through &&
            previous.layoutRevision == baseLayoutRevision &&
            previous.currentWorkId == currentWorkId &&
            revision >= previous.revision;
        if (previous != null) {
          tail = TailSnapshot(
            revision: revision,
            layoutRevision: previous.layoutRevision,
            readyFrontier: previous.readyFrontier,
            executionPresent: previous.executionPresent,
            currentWorkId: currentWorkId,
            older: previous.older,
            blocks: [
              for (final b in previous.blocks)
                if (b.id != currentWorkId)
                  b
                else
                  LiveDisplayBlock(
                    id: b.id,
                    blockOrder: b.blockOrder,
                    source: b.source,
                    body: b.body,
                    state: b.state,
                    hasUnfinishedMembers: b.hasUnfinishedMembers,
                    thinkingSummary: thinkingSummary,
                  ),
            ],
          );
        }
    }
    if (!valid || tail == null) {
      throw const ConversationContinuityError(
        'Invalid timeline cursor, range or tail',
      );
    }
    if (isSet) {
      await _set(read, history, tail);
    } else {
      final current = _current;
      if (current == null || current.isRetired) {
        throw const StaleConversationScope();
      }
      await current._mutate(() async {
        if (history.blocks.isNotEmpty) {
          try {
            await current._presentation!.applyBlocks(
              history.blocks,
              ChatPlacement.append,
            );
          } catch (error) {
            throw _TimelineApplyFailure(error);
          }
        }
        if (!_ownsRead(read) ||
            !identical(_current, current) ||
            current.isRetired) {
          return;
        }
        current.live.value = tail;
      });
      if (!_ownsRead(read) ||
          !identical(_current, current) ||
          current.isRetired) {
        return;
      }
      if (history.blocks.isNotEmpty) {
        current._firstOrder ??= history.blocks.first.blockOrder;
        current._recordBatch(ChatPlacement.append);
      }
      _markPresentedInputs(
        read.session.threadId,
        history.blocks,
        update.tail is ReplaceTail ? tail.blocks : const [],
      );
      if (history.blocks.isNotEmpty) {
        _publishState(
          hasNewOutput: current.mode == TimelineDisplayMode.history,
        );
      }
    }
    if (!_ownsRead(read)) return;
    read.through = history.throughOrder;
    read.cursor = update.next;
    _publishState(
      connection: TimelineConnectionPhase.ready,
      connectionError: null,
    );
  }

  Future<void> _set(
    _TimelineRead read,
    HistoryDelta batch,
    TailSnapshot live,
  ) async {
    final session = read.session;
    final next = TimelineDisplayLease(
      threadId: session.threadId,
      generation: ++_generation,
      demand: _readDemand!,
      reader: read.reader!,
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
        try {
          await presentation.applyBlocks(batch.blocks, ChatPlacement.set);
        } catch (error) {
          throw _TimelineApplyFailure(error);
        }
        if (_ownsRead(read)) next.live.value = live;
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
    next._before = batch.before;
    next._firstOrder = batch.blocks.firstOrNull?.blockOrder;
    next._recordBatch(ChatPlacement.set);
    next._hasOlder = batch.before != null;
    final previous = _current;
    next._mode = previous?.mode ?? TimelineDisplayMode.live;
    _current = next;
    _markPresentedInputs(session.threadId, batch.blocks, live.blocks);
    _olderInFlight = null;
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
      final scope = current.queries;
      if (scope is! TimelineQueryScope) {
        throw const StaleConversationScope();
      }
      final page = await scope.loadTimelineOlder(
        before: before,
        demand: _readDemand ?? current.demand,
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
        if (page.presentationVersion != presentationVersion ||
            page.before == before) {
          throw const ConversationContinuityError('Invalid history page');
        }
        var order = 0;
        for (final block in page.blocks) {
          if (block.blockOrder <= order || block.blockOrder > page.ceiling) {
            throw const ConversationContinuityError('Invalid history range');
          }
          order = block.blockOrder;
        }
        if (page.blocks.isNotEmpty &&
            current._firstOrder != null &&
            page.blocks.last.blockOrder >= current._firstOrder!) {
          throw const ConversationContinuityError('History pages overlap');
        }
        await current._mutate(
          () => current._presentation!.applyBlocks(
            page.blocks,
            ChatPlacement.prepend,
          ),
        );
        if (!identical(_current, current) ||
            current.isRetired ||
            !scope.isActive) {
          return;
        }
        if (page.blocks.isNotEmpty) {
          current._firstOrder = page.blocks.first.blockOrder;
        }
        current._before = page.before;
        current._hasOlder = page.before != null;
        current._recordBatch(ChatPlacement.prepend);
      });
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
      for (final read in _reads.toList()) read.join(),
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
        for (final read in _reads)
          UnresolvedResource(
            owner: 'timeline-reader:${read.session.threadId}',
            attemptId: AttemptId(read.selection),
            reason: read.closeError ?? StateError('Reader is still closing'),
          ),
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

final class _TimelineRead implements Observation {
  _TimelineRead(this.owner, this.selection, this.session, this.restarts);
  final TimelineSessionOwner owner;
  final int selection;
  final ConversationSession session;
  final int restarts;
  TimelineReader? reader;
  ViewCursor? cursor;
  int? through;
  Future<void>? task;
  Object? closeError;
  @override
  bool isCancelled = false;
  @override
  bool get isPaused => false;
  @override
  void cancel() {
    isCancelled = true;
    reader?.requestClose();
  }

  @override
  void pause() => throw UnsupportedError('Timeline reader cannot be paused');
  @override
  void resume() {}
  Future<void> join() async {
    cancel();
    await task;
    if (closeError != null) {
      try {
        await reader?.close();
        closeError = null;
        owner._reads.remove(this);
      } catch (error) {
        closeError = error;
      }
    }
  }
}
