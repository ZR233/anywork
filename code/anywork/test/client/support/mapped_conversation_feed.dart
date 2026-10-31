import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';

/// A test-only typed frame projection around a real feed. Identity, ACK and close stay native-owned.
final class MappedConversationFeed implements ConversationFeed {
  MappedConversationFeed(this.inner, this.mapState);
  final ConversationFeed inner;
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

/// 脚本化权威发送端。只发布显式事实，SDK 才是归约者；没有 pull 循环。
class ScriptedConversationFeed implements ConversationFeed {
  ScriptedConversationFeed({
    required this.threadId,
    required this.subscriptionId,
    required this.baseline,
    ThreadStreamFrame Function()? state,
  }) {
    _events = StreamController<ConversationFrame>(
      onListen: () {
        listenCalls++;
        scheduleMicrotask(() {
          if (closed) return;
          if (state != null) emitState(state());
          publish(ConversationBaselineEvent(baseline: baseline()));
        });
      },
      onCancel: requestClose,
    );
  }
  @override
  final String threadId;
  @override
  final String subscriptionId;
  final ConversationBaseline Function() baseline;
  late final StreamController<ConversationFrame> _events;
  final Set<int> _unacknowledged = {};
  final List<int> acknowledgements = [];
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
      if (_unacknowledged.length == 2) {
        throw StateError('Both data credits are owned');
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
  }

  void emit(ConversationUpdate update) =>
      publish(ConversationUpdateEvent(update: update));
  void emitState(ThreadStreamFrame frame) =>
      publish(ConversationStateEvent(frame: frame));

  @override
  void requestClose() {
    if (closed) return;
    // 终帧不获取 credit，也不等待 ACK。
    publish(const ConversationClosedEvent());
    closed = true;
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    closeCalls++;
    requestClose();
    // 发送端已真实停止；不能把 public consumer 的 done 当作 native join，
    // 否则 SDK 在 close 之后才取消 iterator 时会与暂停的 consumer 自等待。
    unawaited(_events.close());
  }
}
