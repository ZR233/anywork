import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/configuration.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/close_converters.dart';
import '../product_read_owner.dart';
import 'route_values.dart';

final class FrbConfigurationRoleReadConnection
    implements ConfigurationRoleReadConnection {
  FrbConfigurationRoleReadConnection(this._target) {
    _owner = ProductReadOwner<native.BridgeConfigurationRoleReadConnection>(
      resource: 'configuration-role-read',
      origin: _target.configuration.origin,
      version: ProductReadVersion.value(
        entry: _target.reference.entry,
        revision: _target.reference.revision,
      ),
      open: () => native.openConfigurationRoleRead(
        target: configurationRoleTargetToBridge(_target),
      ),
      identity: (handle) => handle.identity(),
      requestClose: (handle) => handle.requestClose(),
      close: (handle) async => feedCloseReportFromBridge(await handle.close()),
      retryClose: (handle) async =>
          feedCloseReportFromBridge(await handle.retryClose()),
      dispose: (handle) => handle.dispose(),
    );
  }
  final ConfigurationRoleReadTarget _target;
  late final ProductReadOwner<native.BridgeConfigurationRoleReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<ConfigurationRoleReadTarget> header() => _owner.query((handle) async {
    final value = configurationRoleTargetFromBridge(await handle.header());
    if (value != _target) throw adapterProtocol('configuration-role-pair');
    return value;
  });
  @override
  Future<RoleRouteRead> roleRoute(String roleId) => _owner.query(
    (handle) async => configurationRoleRouteFromBridge(
      await handle.roleRoute(roleId: roleId),
    ),
  );
  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}

/// Preserves native intent/query/results; no Start route policy lives in Dart.
final class FrbConfigurationStartReadConnection
    implements ConfigurationStartReadConnection {
  FrbConfigurationStartReadConnection(this._sources) {
    _owner = ProductReadOwner<native.BridgeConfigurationStartReadConnection>(
      resource: 'configuration-start-read',
      origin: _sources.configuration.origin,
      version: ProductReadVersion.value(
        entry: _sources.reference.entry,
        revision: _sources.reference.revision,
      ),
      open: () => native.openConfigurationStartRead(
        target: configurationRoleTargetToBridge(_sources),
      ),
      identity: (handle) => handle.identity(),
      requestClose: (handle) => handle.requestClose(),
      close: (handle) async => feedCloseReportFromBridge(await handle.close()),
      retryClose: (handle) async =>
          feedCloseReportFromBridge(await handle.retryClose()),
      dispose: (handle) => handle.dispose(),
    );
  }
  final ConfigurationRoleReadTarget _sources;
  late final ProductReadOwner<native.BridgeConfigurationStartReadConnection>
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<ConfigurationRoleReadTarget> header() => _owner.query((handle) async {
    final value = configurationRoleTargetFromBridge(await handle.header());
    if (value != _sources) throw adapterProtocol('configuration-start-pair');
    return value;
  });
  @override
  Future<StartRouteRead> resolve(StartRouteQuery query) =>
      _owner.query((handle) async {
        final value = startReadFromBridge(
          await handle.resolve(query: startQueryToBridge(query)),
        );
        if (value.sources != _sources || value.query != query) {
          throw adapterProtocol('configuration-start-binding');
        }
        return value;
      });
  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
