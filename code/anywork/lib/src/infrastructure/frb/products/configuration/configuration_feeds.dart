import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/agent_profiles.dart'
    as profile;
import '../../../../rust/api/studio/products/feed/configuration.dart'
    as configuration;
import '../../../../rust/api/studio/products/feed/configuration_transport.dart'
    as native;
import '../../../../rust/api/studio/products/feed/profiles_transport.dart'
    as profiles;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../configuration_converters.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';
import '../profiles_converters.dart';

/// Opening does not claim the native producer. Only an actual events listener
/// reaches handle.stream; ACK and the original window remain native-owned.
final class FrbConfigurationConnection
    implements FeedConnection<ConfigurationFrame> {
  FrbConfigurationConnection() {
    _connection =
        AdapterFeedConnection<
          configuration.BridgeConfigurationFrame,
          ConfigurationFrame
        >(
          resource: 'configuration',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return ConfigurationFrame.failure(identity: identity, error: error);
          },
          isTerminal: (frame) => frame is! ConfigurationData,
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
      native.openConfiguration,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeConfigurationFeed>();
  late final AdapterFeedConnection<
    configuration.BridgeConfigurationFrame,
    ConfigurationFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeConfigurationFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('configuration-feed-identity');
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
        value.resource != ProductResource.configuration ||
        _identity != null && value != _identity) {
      throw adapterProtocol('configuration-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<configuration.BridgeConfigurationFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  ConfigurationFrame _convert(configuration.BridgeConfigurationFrame value) {
    final identity = _originalIdentity();
    final frame = productConfigurationFrameFromBridge(value);
    final incoming = switch (frame) {
      ConfigurationData(event: ConfigurationBaselineEvent(:final identity)) =>
        identity,
      ConfigurationResyncRequired(:final identity) => identity,
      ConfigurationFeedFailure(:final identity) => identity,
      ConfigurationClosed(:final identity) => identity,
      ConfigurationData(event: ConfigurationChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('configuration-frame-identity');
    }
    final stamp = switch (frame) {
      ConfigurationData(event: ConfigurationBaselineEvent(:final stamp)) =>
        stamp,
      ConfigurationData(event: ConfigurationChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('configuration-frame-stamp');
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
      throw adapterProtocol('configuration-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<ConfigurationFrame> get events => _connection.events;
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

final class FrbAgentProfilesConnection
    implements FeedConnection<AgentProfilesFrame> {
  FrbAgentProfilesConnection() {
    _connection =
        AdapterFeedConnection<
          profile.BridgeAgentProfilesFrame,
          AgentProfilesFrame
        >(
          resource: 'agent-profiles',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return AgentProfilesFrame.failure(identity: identity, error: error);
          },
          isTerminal: (frame) => frame is! AgentProfilesData,
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
      profiles.openAgentProfiles,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<profiles.BridgeAgentProfilesFeed>();
  late final AdapterFeedConnection<
    profile.BridgeAgentProfilesFrame,
    AgentProfilesFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(profiles.BridgeAgentProfilesFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('profiles-feed-identity');
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
        value.resource != ProductResource.agentProfiles ||
        _identity != null && value != _identity) {
      throw adapterProtocol('profiles-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<profile.BridgeAgentProfilesFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  AgentProfilesFrame _convert(profile.BridgeAgentProfilesFrame value) {
    final identity = _originalIdentity();
    final frame = profilesFrameFromBridge(value);
    final incoming = switch (frame) {
      AgentProfilesData(event: AgentProfilesBaselineEvent(:final identity)) =>
        identity,
      AgentProfilesResyncRequired(:final identity) => identity,
      AgentProfilesFeedFailure(:final identity) => identity,
      AgentProfilesClosed(:final identity) => identity,
      AgentProfilesData(event: AgentProfilesChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('profiles-frame-identity');
    }
    final stamp = switch (frame) {
      AgentProfilesData(event: AgentProfilesBaselineEvent(:final stamp)) =>
        stamp,
      AgentProfilesData(event: AgentProfilesChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('profiles-frame-stamp');
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
      throw adapterProtocol('profiles-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<AgentProfilesFrame> get events => _connection.events;
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
