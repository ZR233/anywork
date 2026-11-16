import 'dart:async';

import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';

Future<ThreadObservationHandle> ownTestThreadObservation(
  ClientScope scope,
  ClientResourceId resourceId,
  Future<ThreadObservationHandle> Function(ClientOperation) create,
) async {
  final owner = scope.open<ThreadObservationHandle>(
    'scripted-metadata-owner',
    create,
    identity: resourceId,
  );
  return _ThreadProxy(owner, await owner.ready);
}

final class _ThreadProxy implements ThreadObservationHandle {
  _ThreadProxy(this.owner, this.source);
  final ClientAcquisition<ThreadObservationHandle> owner;
  final ThreadObservationHandle source;
  @override
  ClientResourceId get resourceId => owner.resourceId;
  @override
  Future<ThreadMetadataFrame?> next() => source.next();
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
  @override
  Future<void> retryClose() => owner.retryClose();
}

Future<ThreadsObservationHandle> ownTestThreadsObservation(
  ClientScope scope,
  ClientResourceId resourceId,
  Future<ThreadsObservationHandle> Function(ClientOperation) create,
) async {
  final owner = scope.open<ThreadsObservationHandle>(
    'scripted-directory-owner',
    create,
    identity: resourceId,
  );
  return _ThreadsProxy(owner, await owner.ready);
}

final class _ThreadsProxy implements ThreadsObservationHandle {
  _ThreadsProxy(this.owner, this.source);
  final ClientAcquisition<ThreadsObservationHandle> owner;
  final ThreadsObservationHandle source;
  @override
  ClientResourceId get resourceId => owner.resourceId;
  @override
  Future<ThreadDirectoryFrame?> next() => source.next();
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
  @override
  Future<void> retryClose() => owner.retryClose();
}

Future<AccountDomainObservation> ownTestAccountObservation(
  ClientScope scope,
  ClientResourceId resourceId,
  Future<AccountDomainObservation> Function(ClientOperation) create,
) async {
  final owner = scope.open<AccountDomainObservation>(
    'scripted-account-owner',
    create,
    identity: resourceId,
  );
  return _AccountProxy(owner, await owner.ready);
}

final class _AccountProxy implements AccountDomainObservation {
  _AccountProxy(this.owner, this.source);
  final ClientAcquisition<AccountDomainObservation> owner;
  final AccountDomainObservation source;
  @override
  ClientResourceId get resourceId => owner.resourceId;
  @override
  Future<AccountDomainFrame?> next() => source.next();
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
  @override
  Future<void> retryClose() => owner.retryClose();
}

Future<ProductTopicObservation> ownTestProductTopic(
  ClientScope scope,
  ClientResourceId resourceId,
  Stream<ProductTopicFrame> frames, {
  void Function()? requestSource,
  Future<void> Function()? closeSource,
  Future<void> Function()? retrySource,
}) async {
  final owner = scope.open<_StreamTopicOwner>(
    'scripted-topic-owner',
    (operation) async => _StreamTopicOwner(
      operation.resourceId,
      frames,
      requestSource,
      closeSource,
      retrySource,
    ),
    identity: resourceId,
  );
  return _TopicProxy(owner, await owner.ready);
}

final class _TopicProxy implements ProductTopicObservation {
  _TopicProxy(this.owner, this.source);
  final ClientAcquisition<_StreamTopicOwner> owner;
  final _StreamTopicOwner source;
  @override
  ClientResourceId get resourceId => owner.resourceId;
  @override
  Stream<ProductTopicFrame> get frames => source.frames;
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
  @override
  Future<void> retryClose() => owner.retryClose();
}

final class _StreamTopicOwner implements ClientResource {
  _StreamTopicOwner(
    this.resourceId,
    this.source,
    this.requestSource,
    this.closeSource,
    this.retrySource,
  );
  @override
  final ClientResourceId resourceId;
  final Stream<ProductTopicFrame> source;
  final void Function()? requestSource;
  final Future<void> Function()? closeSource;
  final Future<void> Function()? retrySource;
  StreamSubscription<ProductTopicFrame>? _subscription;
  Future<void>? _cancellation;
  Future<void>? _streamClosed;
  bool _closed = false;
  bool _listened = false;
  late final StreamController<ProductTopicFrame> _controller =
      StreamController<ProductTopicFrame>(
        onListen: () {
          _listened = true;
          if (_closed) {
            _streamClosed = _controller.close();
            return;
          }
          _subscription = source.listen(
            _controller.add,
            onError: _controller.addError,
            onDone: _controller.close,
          );
        },
        onCancel: () => _cancellation ??= _subscription?.cancel(),
      );
  Stream<ProductTopicFrame> get frames => _controller.stream;
  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    _cancellation ??= _subscription?.cancel();
    if (_listened) _streamClosed = _controller.close();
    requestSource?.call();
  }

  @override
  Future<void> close() async {
    requestClose();
    await Future.wait<void>([
      ?_cancellation,
      ?_streamClosed,
      Future<void>.sync(() async {
        await closeSource?.call();
      }),
    ]);
  }

  @override
  Future<void> retryClose() async {
    requestClose();
    await Future.wait<void>([
      ?_cancellation,
      ?_streamClosed,
      Future<void>.sync(() async {
        await (retrySource ?? closeSource)?.call();
      }),
    ]);
  }
}
