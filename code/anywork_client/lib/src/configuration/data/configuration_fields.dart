import 'dart:async';

import '../../../resources.dart';
import '../../../resources_ports.dart' show resourceCancelled;
import '../domain/configuration_state.dart';
import '../domain/configuration_values.dart';
import 'configuration_access.dart';
import 'configuration_port.dart';
import 'configuration_read_fields.dart';
import 'configuration_reader.dart';
import 'configuration_reducer.dart';

/// Pending typed field reads only; the host remains the sole canonical writer.
final class ConfigurationFields {
  ConfigurationFields(this.host);
  final ConfigurationReadAccess host;
  final Map<ConfigurationDemand, Future<String?>> _defaults = {};
  final Map<ConfigurationDemand, Future<List<ModeModelRoute>>> _modes = {};
  final Map<ConfigurationDemand, Future<List<RoleModelRoute>>> _roles = {};
  final Map<ConfigurationDemand, Future<String>> _permission = {};
  final Map<ConfigurationDemand, Future<InstructionsSettings>> _instructions =
      {};
  final Map<ConfigurationDemand, Future<SkillsSettings>> _skills = {};
  final Map<ConfigurationDemand, Future<List<McpConfiguration>>> _mcp = {};
  final Map<ConfigurationDemand, Future<GeneralSettings>> _general = {};
  final Map<ConfigurationDemand, Future<DelegationSettings>> _delegation = {};
  final Map<ConfigurationDemand, Future<WebSearchConfiguration>> _web = {};
  final Map<ConfigurationDemand, Future<DeepSeekSearchConfiguration>> _deep =
      {};

  Future<String?> defaults() => _read(
    _defaults,
    (state) => state.defaultAccountId,
    (state, value) => state.copyWith(defaultAccountId: value),
    (scope) async =>
        ConfigurationReader(scope)
            .optional((await scope.header()).defaultAccountId),
  );
  Future<List<ModeModelRoute>> modeRoutes() => _read(
    _modes,
    (state) => state.modeRoutes,
    (state, value) => state.copyWith(modeRoutes: value),
    (scope) async =>
        ConfigurationReader(scope)
            .modeRoutes((await scope.header()).modeModelRoutes),
  );
  Future<List<RoleModelRoute>> roleRoutes() => _read(
    _roles,
    (state) => state.roles,
    (state, value) => state.copyWith(roles: value),
    (scope) async =>
        ConfigurationReader(scope).roleRoutes((await scope.header()).roles),
  );
  Future<String> permission() => _read(
    _permission,
    (state) => state.permissionMode,
    (state, value) => state.copyWith(permissionMode: value),
    (scope) async =>
        ConfigurationReader(scope).text((await scope.header()).permissionMode),
  );
  Future<InstructionsSettings> instructions() => _read(
    _instructions,
    (state) => state.instructions,
    (state, value) => state.copyWith(instructions: value),
    (scope) async =>
        ConfigurationReader(scope)
            .instructions((await scope.header()).instructions),
  );
  Future<SkillsSettings> skills() => _read(
    _skills,
    (state) => state.skillsSettings,
    (state, value) => state.copyWith(skillsSettings: value),
    (scope) async =>
        ConfigurationReader(scope).skills((await scope.header()).skills),
  );
  Future<List<McpConfiguration>> mcp() => _read(
    _mcp,
    (state) => state.mcpConfigurations,
    (state, value) => state.copyWith(mcpConfigurations: value),
    (scope) async =>
        ConfigurationReader(scope).mcp((await scope.header()).mcpServers),
  );
  Future<GeneralSettings> general() => _read(
    _general,
    (state) => state.general,
    (state, value) => state.copyWith(general: value),
    (scope) async =>
        ConfigurationReader(scope).general((await scope.header()).general),
  );
  Future<DelegationSettings> delegation() => _read(
    _delegation,
    (state) => state.delegation,
    (state, value) => state.copyWith(delegation: value),
    (scope) async => (await scope.header()).delegation,
  );
  Future<WebSearchConfiguration> webSearch() => _read(
    _web,
    (state) => state.webSearch,
    (state, value) => state.copyWith(webSearch: value),
    (scope) async =>
        ConfigurationReader(scope).webSearch((await scope.header()).webSearch),
  );
  Future<DeepSeekSearchConfiguration> deepSeekSearch() => _read(
    _deep,
    (state) => state.deepSeekSearch,
    (state, value) => state.copyWith(deepSeekSearch: value),
    (scope) async =>
        ConfigurationReader(scope)
            .deepSeekSearch((await scope.header()).deepseekWebSearch),
  );

  Future<T> _read<T>(
    Map<ConfigurationDemand, Future<T>> pending,
    ReadValue<T, ConfigurationReadRef>? Function(ConfigurationState) field,
    ConfigurationState Function(
      ConfigurationState,
      ReadValue<T, ConfigurationReadRef>,
    )
    update,
    Future<T> Function(ConfigurationReadConnection) read,
  ) {
    host.lifetime.admit();
    final demand = host.capture();
    final known = field(host.source.value);
    if (known is ReadyReadValue<T, ConfigurationReadRef> &&
        known.current.origin == demand.origin &&
        known.current.reference == demand.reference)
      return Future.value(known.current.value);
    final existing = pending[demand];
    if (existing != null) return existing;
    final done = Completer<T>();
    pending[demand] = done.future;
    unawaited(
      host.lifetime
          .run('configuration:field', () async {
            final binding = await host.bind(demand);
            final target = binding.target;
            host.source.publish(
              update(
                host.source.value,
                ReadValue.loading(
                  origin: target.origin,
                  reference: target.reference,
                  previous: configurationPrevious(field(host.source.value)),
                ),
              ),
            );
            try {
              final value = await host.pin(target).use(read);
              if (host.lifetime.sealed) throw resourceCancelled;
              if (!host.current(target)) throw configurationSuperseded;
              host.source.publish(
                update(
                  host.source.value,
                  ReadValue.ready(
                    current: Materialized(
                      origin: target.origin,
                      reference: target.reference,
                      value: value,
                    ),
                  ),
                ),
              );
              return value;
            } catch (error) {
              if (!host.lifetime.sealed && host.current(target))
                host.source.publish(
                  update(
                    host.source.value,
                    ReadValue.failed(
                      origin: target.origin,
                      reference: target.reference,
                      error: configurationFailure(error),
                      previous: configurationPrevious(field(host.source.value)),
                    ),
                  ),
                );
              rethrow;
            }
          })
          .then(
            (value) {
              unawaited(pending.remove(demand));
              done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              unawaited(pending.remove(demand));
              done.completeError(configurationFailure(error), stack);
            },
          ),
    );
    return done.future;
  }
}
