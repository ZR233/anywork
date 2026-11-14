import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:flutter_test/flutter_test.dart';

/// A test-only reader override. Identity, events, ACK and close stay native-owned.
class MappedConversationFeed implements ConversationFeed {
  MappedConversationFeed(this.inner, {ConversationReader? reader})
    : reader = reader ?? inner.reader;
  final ConversationFeed inner;
  @override
  String get threadId => inner.threadId;
  @override
  String get subscriptionId => inner.subscriptionId;
  @override
  final ConversationReader reader;
  @override
  Stream<ConversationFrame> get events => inner.events;
  @override
  Future<void> acknowledge(int deliverySequence) =>
      inner.acknowledge(deliverySequence);
  @override
  void requestClose() => inner.requestClose();
  @override
  Future<void> close() => inner.close();
}

/// Overrides only query delivery; the original cursor and close remain owned by the reader.
class MappedTimelineReader implements TimelineReader {
  MappedTimelineReader(this.inner, {ConversationReader? reader})
    : reader = reader ?? inner.reader;
  final TimelineReader inner;
  String get threadId => reader.threadId;
  String get subscriptionId => metadata.readerId;
  @override
  final ConversationReader reader;
  @override
  OpenTimeline get metadata => inner.metadata;
  @override
  Future<ViewUpdate> next({required ViewCursor after}) =>
      inner.next(after: after);
  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => inner.loadTimelineOlder(before: before, demand: demand);
  @override
  Future<TailSnapshot> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => inner.loadLiveOlder(before: before, demand: demand);
  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) => inner.openDisplayMembers(
    reference: reference,
    window: window,
    demand: demand,
  );
  @override
  void requestClose() => inner.requestClose();
  @override
  Future<void> close() => inner.close();
}

/// 脚本化权威发送端。只发布显式事实，SDK 才是归约者；没有 pull 循环。
class ScriptedConversationFeed implements ConversationFeed {
  ScriptedConversationFeed({
    required String threadId,
    required String subscriptionId,
    required ChatBatch Function() initial,
    ConversationReader? reader,
  }) : this._(
         threadId: threadId,
         subscriptionId: subscriptionId,
         initial: () => ConversationChatEvent(batch: initial()),
         reader: reader,
       );

  ScriptedConversationFeed._({
    required this.threadId,
    required this.subscriptionId,
    required ConversationEvent Function() initial,
    ConversationReader? reader,
  }) : reader = reader ?? _UnusedReader(threadId) {
    _events = StreamController<ConversationFrame>(
      onListen: () {
        listenCalls++;
        scheduleMicrotask(() {
          if (closed) return;
          publish(initial());
        });
      },
      onCancel: requestClose,
    );
  }
  @override
  final String threadId;
  @override
  final String subscriptionId;
  @override
  final ConversationReader reader;
  late final StreamController<ConversationFrame> _events;
  final Set<int> _unacknowledged = {};
  final List<int> acknowledgements = [];
  final Map<int, Completer<void>> _accepted = {};
  Future<void> accepted(int sequence) => acknowledgements.contains(sequence)
      ? Future.value()
      : (_accepted[sequence] ??= Completer<void>()).future;
  int listenCalls = 0;
  int deliveredFrames = 0;
  int closeCalls = 0;
  bool closed = false;
  bool _terminalSent = false;
  bool _claimed = false;
  Future<void>? _closing;

  @override
  Stream<ConversationFrame> get events {
    if (_claimed) throw StateError('A feed has one consumer');
    _claimed = true;
    return _events.stream;
  }

  void publish(ConversationEvent event) {
    if (closed) throw StateError('The feed has closed');
    final terminal =
        event is ConversationClosedEvent || event is ConversationFailureEvent;
    if (_terminalSent) {
      if (terminal) return;
      throw StateError('Data after the terminal frame');
    }
    if (terminal) _terminalSent = true;
    if (!terminal) {
      if (_unacknowledged.isNotEmpty) {
        throw StateError('The single data credit is owned');
      }
      _unacknowledged.add(++deliveredFrames);
    }
    _events.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: deliveredFrames,
        event: event,
      ),
    );
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (!_unacknowledged.remove(deliverySequence)) {
      throw StateError('ACK does not own a credit');
    }
    acknowledgements.add(deliverySequence);
    _accepted.remove(deliverySequence)?.complete();
  }

  void emit(ChatBatch batch) => publish(ConversationChatEvent(batch: batch));

  @override
  void requestClose() {
    if (closed) return;
    // 终帧不获取 credit，也不等待 ACK。
    publish(const ConversationClosedEvent());
    closed = true;
    reader.requestClose();
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    closeCalls++;
    requestClose();
    // 发送端已真实停止；不能把 public consumer 的 done 当作 native join，
    // 否则 SDK 在 close 之后才取消 iterator 时会与暂停的 consumer 自等待。
    unawaited(_events.close());
    try {
      await reader.close();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

/// A controlled peer: fixtures declare responses; the real UI owns application and cursors.
class ScriptedTimelineReader extends MappedTimelineReader {
  ScriptedTimelineReader({required this.queries, required this._initial})
    : super(queries);
  final TimelineReader queries;
  final ViewUpdate Function() _initial;
  final _updates = StreamController<ViewUpdate>();
  late final _iterator = StreamIterator(_updates.stream);
  final List<ViewCursor> acceptedCursors = [];
  final _acceptance = <int, Completer<void>>{};
  int get deliveredFrames => _sequence;
  ViewUpdate? _pending;
  int _sequence = 0;
  bool closed = false;
  Future<void> accepted(int response) => acceptedCursors.length >= response
      ? Future.value()
      : (_acceptance[response] ??= Completer<void>()).future;
  void emitTimeline(ViewUpdate update) => _updates.add(update);
  void emitError(Object error) => _updates.addError(error);
  @override
  Future<ViewUpdate> next({required ViewCursor after}) async {
    if (closed) throw const StaleConversationScope();
    final pending = _pending;
    if (pending != null && after == pending.after) return pending;
    if (pending != null) {
      if (after != pending.next) throw StateError('stale fixture cursor');
      acceptedCursors.add(after);
      _pending = null;
      _acceptance.remove(acceptedCursors.length)?.complete();
    }
    final ViewUpdate declared;
    if (_sequence == 0) {
      declared = _initial();
    } else {
      if (!await _iterator.moveNext()) throw const StaleConversationScope();
      declared = _iterator.current;
    }
    return _pending = ViewUpdate(
      presentationVersion: declared.presentationVersion,
      readerProtocolVersion: declared.readerProtocolVersion,
      after: after,
      next: ViewCursor('${metadata.readerId}-${++_sequence}'),
      history: declared.history,
      tail: declared.tail,
    );
  }

  @override
  void requestClose() {
    if (closed) return;
    closed = true;
    unawaited(_updates.close());
    super.requestClose();
  }

  @override
  Future<void> close() async {
    requestClose();
    await super.close();
    await _iterator.cancel();
  }
}

/// 状态侧脚本化发送端：只承载 State/Failure/Closed，身份与 credit 独立于内容连接。
class ScriptedConversationStateFeed implements ConversationStateFeed {
  ScriptedConversationStateFeed({
    required this.threadId,
    this.subscriptionId = 'state-sub',
    ThreadStreamFrame Function()? initialState,
  }) {
    _events = StreamController<ConversationFrame>(
      onListen: () {
        listenCalls++;
        scheduleMicrotask(() {
          if (closed) return;
          unawaited(() async {
            if (initialState != null) {
              emitState(initialState());
              await Future.any([accepted(deliveredFrames), _stopped.future]);
            }
          }());
        });
      },
      onCancel: requestClose,
    );
  }
  @override
  final String threadId;
  @override
  final String subscriptionId;
  late final StreamController<ConversationFrame> _events;
  final Set<int> _unacknowledged = {};
  final List<int> acknowledgements = [];
  final Map<int, Completer<void>> _accepted = {};
  final _stopped = Completer<void>();
  Future<void> accepted(int sequence) => acknowledgements.contains(sequence)
      ? Future.value()
      : (_accepted[sequence] ??= Completer<void>()).future;
  int listenCalls = 0;
  int deliveredFrames = 0;
  int closeCalls = 0;
  bool closed = false;
  bool _terminalSent = false;
  bool _claimed = false;
  Future<void>? _closing;

  @override
  Stream<ConversationFrame> get events {
    if (_claimed) throw StateError('A feed has one consumer');
    _claimed = true;
    return _events.stream;
  }

  void publish(ConversationEvent event) {
    if (closed) throw StateError('The feed has closed');
    final terminal =
        event is ConversationClosedEvent || event is ConversationFailureEvent;
    if (_terminalSent) {
      if (terminal) return;
      throw StateError('Data after the terminal frame');
    }
    if (event is ConversationChatEvent || event is ConversationActivityEvent) {
      throw StateError('Content never flows on the state feed');
    }
    if (terminal) _terminalSent = true;
    if (!terminal) {
      if (_unacknowledged.isNotEmpty) {
        throw StateError('The single data credit is owned');
      }
      _unacknowledged.add(++deliveredFrames);
    }
    _events.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: deliveredFrames,
        event: event,
      ),
    );
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (!_unacknowledged.remove(deliverySequence)) {
      throw StateError('ACK does not own a credit');
    }
    acknowledgements.add(deliverySequence);
    _accepted.remove(deliverySequence)?.complete();
  }

  void emitState(ThreadStreamFrame frame) =>
      publish(ConversationStateEvent(frame: frame));

  @override
  void requestClose() {
    if (closed) return;
    // 终帧不获取 credit，也不等待 ACK。
    publish(const ConversationClosedEvent());
    closed = true;
    _stopped.complete();
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    closeCalls++;
    requestClose();
    unawaited(_events.close());
  }
}

/// A test-only typed frame projection around a real state feed.
final class MappedConversationStateFeed implements ConversationStateFeed {
  MappedConversationStateFeed(this.inner, this.mapState);
  final ConversationStateFeed inner;
  final ThreadStreamFrame Function(ThreadStreamFrame frame) mapState;
  @override
  String get threadId => inner.threadId;
  @override
  String get subscriptionId => inner.subscriptionId;
  @override
  Stream<ConversationFrame> get events => inner.events.map(
    (frame) => ConversationFrame(
      threadId: frame.threadId,
      subscriptionId: frame.subscriptionId,
      deliverySequence: frame.deliverySequence,
      event: switch (frame.event) {
        ConversationStateEvent(:final frame) => ConversationStateEvent(
          frame: mapState(frame),
        ),
        final event => event,
      },
    ),
  );
  @override
  Future<void> acknowledge(int deliverySequence) =>
      inner.acknowledge(deliverySequence);
  @override
  void requestClose() => inner.requestClose();
  @override
  Future<void> close() => inner.close();
}

final class _UnusedReader extends Fake implements ConversationReader {
  _UnusedReader(this.threadId);
  @override
  final String threadId;
  @override
  void requestClose() {}
  @override
  Future<void> close() async {}
}
