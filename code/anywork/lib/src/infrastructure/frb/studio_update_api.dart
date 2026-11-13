import 'package:anywork_client/studio_client.dart';

import 'studio_bridge_api.dart' as frb;
import 'studio_api.dart' show FrbStudioTransport;

final class FrbStudioUpdateApi implements StudioUpdateApi {
  const FrbStudioUpdateApi();

  @override
  Future<void> check() async {
    await FrbStudioTransport.ensureReady();
    await frb.checkStudioUpdate();
  }

  @override
  Future<void> startAutomaticUpdate() async {
    await FrbStudioTransport.ensureReady();
    await frb.startStudioBackgroundUpdate();
  }

  @override
  Future<void> cancelCurrentPreparation() =>
      frb.cancelCurrentUpdatePreparation();

  @override
  Future<void> stopAutomaticUpdate() => frb.stopStudioBackgroundUpdate();

  @override
  Future<StudioUpdateOperation> startPreparation({
    required int expectedRevision,
    required String version,
  }) async {
    await FrbStudioTransport.ensureReady();
    try {
      return _FrbStudioUpdateOperation(
        await frb.prepareStudioUpdate(
          expectedRevision: BigInt.from(expectedRevision),
          version: version,
        ),
      );
    } on frb.BridgeError catch (error) {
      throw StudioUpdatePreparationRejected(error.message);
    }
  }
}

final class _FrbStudioUpdateOperation implements StudioUpdateOperation {
  _FrbStudioUpdateOperation(this._handle);
  final frb.BridgeStudioUpdateOperation _handle;
  bool _disposed = false;

  @override
  Future<void> cancel() => _handle.cancel();

  @override
  Future<StudioUpdatePreparationResult> finishPreparation() async =>
      switch (await _handle.finishPreparation()) {
        frb.BridgeUpdatePreparationResult_Ready(:final version) =>
          ReadyStudioUpdatePreparation(version),
        frb.BridgeUpdatePreparationResult_Cancelled() =>
          const CancelledStudioUpdatePreparation(),
        frb.BridgeUpdatePreparationResult_Failed(:final error) =>
          FailedStudioUpdatePreparation(
            UpdaterErrorView(
              code: error.code,
              message: error.message,
              retryable: error.retryable,
            ),
          ),
      };

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _handle.dispose();
  }
}
