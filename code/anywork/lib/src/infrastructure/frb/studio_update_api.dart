import 'package:anywork_client/studio_client.dart';

import 'studio_bridge_api.dart' as frb;
import 'studio_api.dart' show FrbStudioTransport, updaterStateFromFrb;

final class FrbStudioUpdateApi implements StudioUpdateApi {
  const FrbStudioUpdateApi();

  @override
  Future<UpdaterStateSnapshot> read() async {
    await FrbStudioTransport.ensureReady();
    return updaterStateFromFrb(await frb.readStudioUpdateState());
  }

  @override
  Future<UpdaterStateSnapshot> check() async {
    await FrbStudioTransport.ensureReady();
    return updaterStateFromFrb(await frb.checkStudioUpdate());
  }

  @override
  Future<void> startAutomaticUpdate() async {
    await FrbStudioTransport.ensureReady();
    await frb.startStudioBackgroundUpdate();
  }

  @override
  Future<void> cancelAutomaticUpdate() => frb.cancelStudioBackgroundUpdate();

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
      // This typed response is only returned before native operation admission.
      throw StudioUpdatePreparationRejected(error.message);
    }
  }
}

final class _FrbStudioUpdateOperation implements StudioUpdateOperation {
  _FrbStudioUpdateOperation(this._handle);
  final frb.BridgeStudioUpdateOperation _handle;
  bool _disposed = false;

  @override
  Stream<UpdaterStateSnapshot> get events =>
      _handle.progressStream().map(updaterStateFromFrb);
  @override
  Future<void> cancel() => _handle.cancel();
  @override
  Future<void> finishPreparation() => _handle.finishPreparation();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _handle.dispose();
  }
}
