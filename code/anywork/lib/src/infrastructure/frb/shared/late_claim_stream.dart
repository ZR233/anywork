import 'dart:async';

/// A view, not a subscription. Every listen, including a second listen on the
/// very same view, reaches the owning connection's typed admission check.
final class LateClaimStream<T> extends Stream<T> {
  LateClaimStream(this._listen);

  final StreamSubscription<T> Function(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) _listen;

  @override
  bool get isBroadcast => false;

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
