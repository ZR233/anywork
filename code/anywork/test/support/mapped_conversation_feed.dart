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

final class _UnusedReader extends Fake implements ConversationReader {
  _UnusedReader(this.threadId);
  @override
  final String threadId;
  @override
  void requestClose() {}
  @override
  Future<void> close() async {}
}
