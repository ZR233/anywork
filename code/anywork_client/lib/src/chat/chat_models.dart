import '../contracts/stamps.dart';

abstract interface class ChatReducer<S, F> {
  /// Validates and adopts an authoritative first Reset for a new view.
  S reset(S snapshot);
  S apply(S current, F frame);
  int version(S snapshot);
}

final class ChatProtocolError implements Exception {
  const ChatProtocolError(this.message);
  final String message;

  @override
  String toString() => 'Chat protocol error: $message';
}

final class ChatItem<T> {
  const ChatItem({
    required this.id,
    required this.revision,
    required this.value,
    required this.saved,
    required this.terminal,
    this.omittedUnits = 0,
  });
  final String id;
  final int revision;
  final T value;
  final bool saved;
  final bool terminal;
  final int omittedUnits;
}

final class ChatSnapshot<T> {
  ChatSnapshot({
    required this.stamp,
    required Iterable<ChatItem<T>> items,
    this.focusedItemId,
    this.hasOlder = false,
    this.hasNewer = false,
  }) : items = List.unmodifiable(items);

  final ViewStamp stamp;
  final List<ChatItem<T>> items;
  final String? focusedItemId;
  final bool hasOlder;
  final bool hasNewer;
}

sealed class ChatFrame<T> {
  const ChatFrame();
}

final class ChatReset<T> extends ChatFrame<T> {
  const ChatReset(this.snapshot);
  final ChatSnapshot<T> snapshot;
}

final class ChatPatch<T> extends ChatFrame<T> {
  ChatPatch({
    required this.from,
    required this.to,
    required Iterable<ChatChange<T>> changes,
    required this.hasNewer,
    this.focusedItemId,
    this.hasOlder = false,
  }) : changes = List.unmodifiable(changes);

  final ViewStamp from;
  final ViewStamp to;
  final List<ChatChange<T>> changes;
  final String? focusedItemId;
  final bool hasOlder;
  final bool hasNewer;
}

sealed class ChatChange<T> {
  const ChatChange();
}

final class ChatSplice<T> extends ChatChange<T> {
  ChatSplice({
    required this.index,
    required this.remove,
    required Iterable<ChatItem<T>> items,
  }) : items = List.unmodifiable(items);

  final int index;
  final int remove;
  final List<ChatItem<T>> items;
}

final class ChatItemUpdate<T> extends ChatChange<T> {
  const ChatItemUpdate({required this.expectedRevision, required this.item});
  final int expectedRevision;
  final ChatItem<T> item;
}

/// The sole writer for the SDK-only standard Chat snapshot representation.
final class ChatSnapshotReducer<T>
    implements ChatReducer<ChatSnapshot<T>, ChatFrame<T>> {
  const ChatSnapshotReducer();

  @override
  ChatSnapshot<T> reset(ChatSnapshot<T> snapshot) {
    _validate(snapshot);
    return snapshot;
  }

  @override
  int version(ChatSnapshot<T> snapshot) => snapshot.stamp.version;

  @override
  ChatSnapshot<T> apply(ChatSnapshot<T> current, ChatFrame<T> frame) {
    switch (frame) {
      case ChatReset<T>(:final snapshot):
        if (!current.stamp.sameView(snapshot.stamp)) {
          throw const ChatProtocolError('Reset belongs to another view');
        }
        if (snapshot.stamp.version < current.stamp.version) {
          throw const ChatProtocolError(
            'Reset regressed the delivered version',
          );
        }
        return reset(snapshot);
      case ChatPatch<T>(
        :final from,
        :final to,
        :final changes,
        :final focusedItemId,
        :final hasOlder,
        :final hasNewer,
      ):
        if (from != current.stamp ||
            !from.sameView(to) ||
            to.version <= from.version) {
          throw const ChatProtocolError('Patch does not continue the baseline');
        }
        final items = List<ChatItem<T>>.of(current.items);
        for (final change in changes) {
          switch (change) {
            case ChatSplice<T>(
              :final index,
              :final remove,
              items: final inserted,
            ):
              if (index < 0 || remove < 0 || index + remove > items.length) {
                throw const ChatProtocolError('Invalid splice range');
              }
              items.replaceRange(index, index + remove, inserted);
            case ChatItemUpdate<T>(:final expectedRevision, :final item):
              final index = items.indexWhere((value) => value.id == item.id);
              if (index < 0 ||
                  items[index].revision != expectedRevision ||
                  item.revision <= expectedRevision) {
                throw const ChatProtocolError('Item update revision mismatch');
              }
              items[index] = item;
          }
        }
        return reset(
          ChatSnapshot(
            stamp: to,
            items: items,
            focusedItemId: focusedItemId,
            hasOlder: hasOlder,
            hasNewer: hasNewer,
          ),
        );
    }
  }

  void _validate(ChatSnapshot<T> snapshot) {
    final ids = <String>{};
    for (final item in snapshot.items) {
      if (item.id.isEmpty ||
          !ids.add(item.id) ||
          item.revision < 0 ||
          item.omittedUnits < 0) {
        throw const ChatProtocolError('Invalid or duplicate item identity');
      }
    }
  }
}

sealed class ChatUiState<S> {
  const ChatUiState(this.threadId);
  final String threadId;
  S? get snapshot;
}

final class ChatIdle<S> extends ChatUiState<S> {
  const ChatIdle(super.threadId);
  @override
  S? get snapshot => null;
}

final class ChatOpening<S> extends ChatUiState<S> {
  const ChatOpening(super.threadId, {this.lastGood});
  final S? lastGood;
  @override
  S? get snapshot => lastGood;
}

final class ChatReady<S> extends ChatUiState<S> {
  const ChatReady(super.threadId, this.snapshot);
  @override
  final S snapshot;
}

final class ChatReconnecting<S> extends ChatUiState<S> {
  const ChatReconnecting(super.threadId, {this.lastGood, required this.error});
  final S? lastGood;
  final Object error;
  @override
  S? get snapshot => lastGood;
}

final class ChatFailed<S> extends ChatUiState<S> {
  const ChatFailed(super.threadId, {this.lastGood, required this.error});
  final S? lastGood;
  final Object error;
  @override
  S? get snapshot => lastGood;
}

final class ChatClosed<S> extends ChatUiState<S> {
  const ChatClosed(super.threadId);
  @override
  S? get snapshot => null;
}
