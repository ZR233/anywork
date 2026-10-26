import 'package:anywork_client/skills_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/skills.dart' as wire;
import '../../../../rust/api/studio/products/feed/skills_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../skills_converters.dart';
import '../product_native_opening.dart';

/// Retains the original project's native source and its unmodified ACK window.
final class FrbSkillsConnection implements FeedConnection<SkillsFrame> {
  FrbSkillsConnection(String projectId) {
    _connection = AdapterFeedConnection<wire.BridgeSkillsFrame, SkillsFrame>(
      resource: 'skills',
      openNativeStream: _stream,
      convert: _convert,
      failureFrame: (error) {
        final identity = _identity;
        if (identity == null) throw error;
        return SkillsFrame.failure(identity: identity, error: error);
      },
      isTerminal: (frame) => frame is! SkillsData,
      identity: (_) => _feedId,
      acknowledgeNative: (sequence) async {
        final handle = await _opening.ready;
        _connection.owner.ensureOpen();
        await handle.ackThrough(deliverySequence: sequence);
      },
      requestNativeClose: () => _opening.handle?.requestClose(),
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _opening.handle!.dispose(),
      mapFailure: bridgeFailure,
    );
    _opening.start(
      _connection.owner,
      () => native.openSkills(projectId: projectId),
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeSkillsFeed>();
  late final AdapterFeedConnection<wire.BridgeSkillsFrame, SkillsFrame>
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeSkillsFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('skills-feed-identity');
    }
    _feedId ??= raw;
  }

  ProductFeedIdentity _originalIdentity() {
    final handle = _opening.handle!;
    _rememberRawIdentity(handle);
    final value = productFeedIdentityFromBridge(handle.identity());
    if (value.feedId != _feedId ||
        value.ownerEpoch.isEmpty ||
        value.incarnation < 1 ||
        value.resource != ProductResource.skills ||
        _identity != null && value != _identity) {
      throw adapterProtocol('skills-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeSkillsFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  SkillsFrame _convert(wire.BridgeSkillsFrame value) {
    final identity = _originalIdentity();
    final frame = skillsFrameFromBridge(value);
    final incoming = switch (frame) {
      SkillsData(event: SkillsBaselineEvent(:final identity)) => identity,
      SkillsResyncRequired(:final identity) => identity,
      SkillsFeedFailure(:final identity) => identity,
      SkillsClosed(:final identity) => identity,
      SkillsData(event: SkillsChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('skills-frame-identity');
    }
    final stamp = switch (frame) {
      SkillsData(event: SkillsBaselineEvent(:final stamp)) => stamp,
      SkillsData(event: SkillsChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('skills-frame-stamp');
    }
    return frame;
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    if (_feedId == null) {
      try {
        _rememberRawIdentity(handle);
      } on Object catch (error, stack) {
        _connection.owner.failure(error, stack, source: 'close-identity');
      }
    }
    final report = feedCloseReportFromBridge(
      await (retry ? handle.retryClose() : handle.close()),
    );
    if (_feedId == null || report.feedId != _feedId) {
      throw adapterProtocol('skills-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<SkillsFrame> get events => _connection.events;
  @override
  Future<void> ackThrough(int deliverySequence) {
    try {
      return _connection.ackThrough(deliverySequence);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _connection.owner.failure(error, stack, source: 'ack-input'),
        stack,
      );
    }
  }

  @override
  void requestClose() => _connection.requestClose();
  @override
  Future<FeedCloseReport> close() => _connection.close();
  @override
  Future<FeedCloseReport> retryClose() => _connection.retryClose();
}
