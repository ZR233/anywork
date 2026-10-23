import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/resources.dart';

import '../../view_models/read_values.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/mcp_view_state.dart';

final class McpVisibleReads {
  McpVisibleReads(this.configuration, this.mcp, this.changed) {
    _configuration = VisibleReadDemand(read: (key) async {
      final source = configuration.state.value.projection;
      if (source.stamp?.origin == key.$1 && source.header?.reference == key.$2) await configuration.loadMcpConfigurations();
    }, changed: (key, error, current) => changed(McpReadField.configuration, error, current, _configuration.reading));
    _runtime = VisibleReadDemand(read: (key) async {
      final source = mcp.state.value.projection;
      if (source.stamp?.origin != key.$1 || source.header?.reference != key.$2) return;
      await mcp.loadServersPage();
    }, changed: (key, error, current) => changed(McpReadField.runtime, error, current, _runtime.reading));
    _configurationStatus = VisibleReadDemand(read: (key) async {
      final source = configuration.state.value.projection;
      if (source.stamp?.origin == key.$1 && source.header?.source.status == key.$2) await configuration.loadSourceStatus();
    }, changed: (key, error, current) => changed(McpReadField.configurationStatus, error, current, _configurationStatus.reading));
    _runtimeStatus = VisibleReadDemand(read: (key) async {
      final source = mcp.state.value.projection;
      if (source.stamp?.origin == key.$1 && source.header?.source.status == key.$2) await mcp.loadSourceStatus();
    }, changed: (key, error, current) => changed(McpReadField.runtimeStatus, error, current, _runtimeStatus.reading));
  }
  final ConfigurationRepository configuration;
  final McpRepository mcp;
  final void Function(McpReadField, StudioFailure?, bool, bool) changed;
  late final VisibleReadDemand<(ProductReadOrigin, ConfigurationReadRef)> _configuration;
  late final VisibleReadDemand<(ProductReadOrigin, McpReadRef)> _runtime;
  late final VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)> _configurationStatus;
  late final VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)> _runtimeStatus;
  bool _visible = false;

  void visible(bool value) { _visible = value; refresh(); }
  void refresh() {
    final config = configuration.state.value;
    final runtime = mcp.state.value;
    final configOrigin = config.projection.stamp?.origin;
    final configRef = config.projection.header?.reference;
    final origin = runtime.projection.stamp?.origin;
    final reference = runtime.projection.header?.reference;
    final configStatus = config.projection.header?.source.status;
    final status = runtime.projection.header?.source.status;
    _target(_configuration, configOrigin == null || configRef == null ? null : (configOrigin, configRef),
      !isCurrentRead(config.mcpConfigurations, configRef, configOrigin));
    _target(_runtime, origin == null || reference == null ? null : (origin, reference), true);
    _target(_configurationStatus, configOrigin == null || configStatus == null ? null : (configOrigin, configStatus),
      !isCurrentRead(config.sourceStatus, configStatus, configOrigin));
    _target(_runtimeStatus, origin == null || status == null ? null : (origin, status),
      !isCurrentRead(runtime.sourceStatus, status, origin));
  }
  void _target<K extends Object>(VisibleReadDemand<K> demand, K? key, bool needed) {
    demand.visible(false); demand.target(key, needed: needed); demand.visible(_visible);
  }
  void rememberStatusFailures() {
    if (failedReadIdentity(configuration.state.value.sourceStatus) case final key?) _configurationStatus.remember(key);
    if (failedReadIdentity(mcp.state.value.sourceStatus) case final key?) _runtimeStatus.remember(key);
  }
  void retry() { refresh(); _configuration.retry(); _runtime.retry(); _configurationStatus.retry(); _runtimeStatus.retry(); }
  void dispose() { _configuration.dispose(); _runtime.dispose(); _configurationStatus.dispose(); _runtimeStatus.dispose(); }
}
