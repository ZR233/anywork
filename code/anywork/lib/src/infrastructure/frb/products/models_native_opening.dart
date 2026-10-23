import 'dart:async';

import '../shared/resource_owner.dart';

/// The opening uses the connection's existing owner, not another registry or
/// closer. A late native handle remains reachable by the original close RPC.
final class ModelsNativeOpening<N> {
  ModelsNativeOpening() { _opened.future.ignore(); }

  final _opened = Completer<N>();
  N? _handle;
  N? get handle => _handle;
  Future<N> get ready => _opened.future;

  void start(AdapterResourceOwner owner, Future<N> Function() open,
      void Function(N) requestClose) {
    final finish = owner.registerOpening();
    Future<N>.sync(open).then<void>((handle) {
      _handle = handle;
      if (owner.isClosing) {
        try { requestClose(handle); } on Object catch (error, stack) {
          owner.failure(error, stack, source: 'late-open-close');
        }
      }
      _opened.complete(handle);
    }, onError: (Object error, StackTrace stack) {
      _opened.completeError(owner.failure(error, stack, source: 'open'), stack);
    }).whenComplete(finish).ignore();
  }
}
