import 'dart:async';

import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/feed/startup_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/feed_connection.dart';
import '../product_native_opening.dart';
import 'startup_values.dart';

/// Native open registers the original attempt before start can run; a real
/// events listener subsequently claims its stream. No latest-stage poll or ACK.
final class FrbStartupProgressConnection
    implements FeedConnection<StartupProgressFrame> {
  FrbStartupProgressConnection(int attemptId) {
    _connection =
        AdapterFeedConnection<
          native.BridgeStartupProgressFrame,
          StartupProgressFrame
        >(
          resource: 'startup-progress',
          openNativeStream: _stream,
          convert: startupProgressFromBridge,
          failureFrame: (error) => StartupProgressFrame.failure(error: error),
          isTerminal: (frame) => frame is! DataStartupProgressFrame,
          identity: (_) => _feedId,
          acknowledgeNative: (sequence) async {
            final handle = await _opening.ready;
            _connection.owner.ensureOpen();
            await handle.ackThrough(deliverySequence: sequence);
          },
          requestNativeClose: () {
            _wakeAcknowledgements();
            _opening.handle?.requestClose();
          },
          closeNative: () => _closeNative(retry: false),
          retryNativeClose: () => _closeNative(retry: true),
          disposeNative: () => _opening.handle!.dispose(),
          mapFailure: bridgeFailure,
        );
    _opening.start(
      _connection.owner,
      () => native.openStartupProgress(
        attemptId: nativeU64(attemptId, 'startup attempt'),
      ),
      (handle) => handle.requestClose(),
      attached: _rememberIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeStartupFeed>();
  late final AdapterFeedConnection<
    native.BridgeStartupProgressFrame,
    StartupProgressFrame
  >
  _connection;
  String? _feedId;
  BigInt _deliveredThrough = BigInt.zero;
  BigInt _acknowledgedThrough = BigInt.zero;
  Completer<void>? _acknowledgements;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  Stream<native.BridgeStartupProgressFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _rememberIdentity(handle);
    await for (final frame in handle.stream()) {
      if (_connection.owner.isClosing) return;
      if (frame case native.BridgeStartupProgressFrame_Data(
        :final deliverySequence,
      )) {
        _deliveredThrough = deliverySequence;
      }
      if (frame case native.BridgeStartupProgressFrame_Closed(
        reason: native.BridgeStartupCloseReason.completed,
      )) {
        // Native terminal control needs no Data credit. Do not let the shared
        // terminal fence cancel a still-unacknowledged final Ready stage.
        // Only the real caller's completed ackThrough can advance this prefix.
        while (!_connection.owner.isClosing &&
            _acknowledgedThrough < _deliveredThrough) {
          await (_acknowledgements ??= Completer<void>()).future;
        }
        if (_connection.owner.isClosing) return;
      }
      yield frame;
    }
  }

  void _wakeAcknowledgements() {
    final pending = _acknowledgements;
    _acknowledgements = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _rememberIdentity(native.BridgeStartupFeed handle) {
    final id = handle.identity();
    if (id.isEmpty || _feedId != null && _feedId != id) {
      throw adapterProtocol('startup-feed-identity');
    }
    _feedId ??= id;
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    if (_feedId == null) {
      try {
        _rememberIdentity(handle);
      } on Object catch (error, stack) {
        _connection.owner.failure(error, stack, source: 'close-identity');
      }
    }
    final report = feedCloseReportFromBridge(
      await (retry ? handle.retryClose() : handle.close()),
    );
    if (_feedId == null || report.feedId != _feedId) {
      throw adapterProtocol('startup-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<StartupProgressFrame> get events => _connection.events;
  @override
  Future<void> ackThrough(int deliverySequence) async {
    // Wake completion only after the shared query owner has accepted the actual
    // native ACK result; waking inside its callback could race its close fence.
    await _connection.ackThrough(deliverySequence);
    final sequence = nativeU64(
      deliverySequence,
      'startup acknowledged delivery',
    );
    if (sequence > _acknowledgedThrough) _acknowledgedThrough = sequence;
    _wakeAcknowledgements();
  }

  @override
  void requestClose() => _connection.requestClose();
  @override
  Future<FeedCloseReport> close() => _connection.close();
  @override
  Future<FeedCloseReport> retryClose() => _connection.retryClose();
}
