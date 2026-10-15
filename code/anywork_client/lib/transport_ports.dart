enum ChatDirection { older, newer }

abstract interface class ChatTransport<S, F, R> {
  Future<ChatHandle<S, F, R>> open(String threadId);
}

/// A transport handle owns its native close signal, sink and pending reads.
/// [requestClose] must synchronously request cancellation; [close] joins it.
abstract interface class ChatHandle<S, F, R> {
  Future<S> initial();
  Future<F?> next();
  Future<R> load(ChatDirection direction);
  Future<R> extendLatest();
  Future<R> focus(String? itemId);
  Future<R> expand(String itemId);
  void requestClose();
  Future<void> close();
}
