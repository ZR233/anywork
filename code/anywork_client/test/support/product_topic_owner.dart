import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';

/// Registers the scripted source as the actual owner, separate from SDK demand.
Future<TestProductTopicObservation> openTestProductTopic(
  ClientScope scope,
  ClientResourceId resourceId,
  StreamController<ProductTopicFrame> controller,
) async {
  final owner = scope.open<TestProductTopicOwner>(
    'scripted-topic-owner',
    (operation) async =>
        TestProductTopicOwner(operation.resourceId, controller),
    identity: resourceId,
  );
  return TestProductTopicObservation(owner, await owner.ready);
}

final class TestProductTopicOwner implements ClientResource {
  TestProductTopicOwner(this.resourceId, this.controller);

  @override
  final ClientResourceId resourceId;
  final StreamController<ProductTopicFrame> controller;
  final closeRequested = Completer<void>();
  final closeAcknowledged = Completer<void>();
  int closeCalls = 0;
  int retryCloseCalls = 0;
  Completer<void>? closeGate;
  Object? closeFailure;
  Future<void>? _closing;
  bool _hadListener = false;

  @override
  void requestClose() {
    if (closeRequested.isCompleted) return;
    closeRequested.complete();
    _hadListener = controller.hasListener;
    _closing = controller.close();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
    // A late, never-delivered source has no SDK consumer to acknowledge done.
    if (_hadListener) await _closing;
    if (!closeAcknowledged.isCompleted) closeAcknowledged.complete();
  }

  @override
  Future<void> retryClose() {
    retryCloseCalls++;
    return close();
  }
}

final class TestProductTopicObservation implements ProductTopicObservation {
  TestProductTopicObservation(this.owner, this.source);
  final ClientAcquisition<TestProductTopicOwner> owner;
  final TestProductTopicOwner source;

  @override
  ClientResourceId get resourceId => owner.resourceId;
  @override
  Stream<ProductTopicFrame> get frames => source.controller.stream;
  @override
  void requestClose() => owner.requestClose();
  @override
  Future<void> close() => owner.close();
  @override
  Future<void> retryClose() => owner.retryClose();
}
