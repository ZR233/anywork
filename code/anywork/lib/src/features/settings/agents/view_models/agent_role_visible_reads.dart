import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/resources.dart';

import '../../view_models/collection_values.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/agent_profiles_state.dart';

typedef _RoleReadKey = ({
  ConfigurationRoleReadTarget target,
  String roleId,
  int intent,
});

ConfigurationRoleReadTarget? currentRoleReadTarget(ConfigurationState source) =>
    source.projection.sync.phase == ResourceSyncPhase.ready
    ? source.projection.header?.roleRead
    : null;

/// UI demand only. Rust owns presence/default policy and the Repository owns
/// each admitted paired read, its pinned scope, budget and eventual join.
final class AgentRoleVisibleReads {
  AgentRoleVisibleReads(this.configuration, this.changed);
  final ConfigurationRepository configuration;
  final void Function(SettingsRoleRead read) changed;
  final _demands = <String, VisibleReadDemand<_RoleReadKey>>{};
  final _requests = <String, SettingsRoleRead>{};
  Set<String> _roles = {};
  ConfigurationRoleReadTarget? _target;
  bool _visible = false;
  bool _disposed = false;
  int _intent = 0;
  int _refresh = 0;

  bool _owns(_RoleReadKey key) =>
      !_disposed &&
      _roles.contains(key.roleId) &&
      _target == key.target &&
      currentRoleReadTarget(configuration.state.value) == key.target &&
      _requests[key.roleId]?.intent == key.intent;

  void _publish(SettingsRoleRead read) {
    if (_disposed || _requests[read.roleId] == read) return;
    _requests[read.roleId] = read;
    changed(read);
  }

  VisibleReadDemand<_RoleReadKey> _demand(String role) {
    late final VisibleReadDemand<_RoleReadKey> demand;
    demand = VisibleReadDemand(
      read: (key) async {
        if (!_owns(key)) return;
        // The complete Rust-issued target and exact role/intent are frozen in
        // key before await; never construct a pair from two latest headers.
        final result = await configuration.roleRoute(
          target: key.target,
          roleId: key.roleId,
        );
        if (_owns(key)) {
          _publish(_requests[role]!.copyWith(value: result, error: null));
        }
      },
      changed: (key, error, current) {
        if (!current || !_owns(key)) return;
        final request = _requests[role]!;
        _publish(
          request.copyWith(
            pending: demand.reading,
            error: error,
            value: error == null ? request.value : null,
          ),
        );
      },
    );
    return demand;
  }

  void visible(bool value) {
    _visible = value;
    refresh();
  }

  void refresh() {
    if (_disposed) return;
    final refresh = ++_refresh;
    final source = configuration.state.value;
    final target = currentRoleReadTarget(source);
    final roles = {
      for (final profile in displayCollectionRows(
        configuration.profiles.value.profiles,
      ))
        if (profile.system && profile.profileId != 'planner') profile.profileId,
    };
    _target = target;
    _roles = roles;
    for (final role
        in _demands.keys.where((role) => !roles.contains(role)).toList()) {
      _demands.remove(role)!.dispose();
      _requests.remove(role);
    }
    for (final role in roles) {
      final demand = _demands.putIfAbsent(role, () => _demand(role));
      demand.visible(false);
      final previous = _requests[role];
      // Missing pair material is unknown, not a query failure. Only preserve
      // the source's real typed error; there is no role retry without a target.
      final error = target == null ? source.projection.sync.error : null;
      if (previous == null || previous.target != target) {
        _publish(
          SettingsRoleRead(
            roleId: role,
            target: target,
            intent: ++_intent,
            error: error,
          ),
        );
      } else if (target == null && previous.error != error) {
        _publish(previous.copyWith(error: error));
      }
      if (_disposed || refresh != _refresh) return;
      final request = _requests[role]!;
      // Intent is part of UI demand identity so A -> unavailable -> A cannot
      // admit a late result on behalf of the replacement request.
      demand.target(
        target == null
            ? null
            : (target: target, roleId: role, intent: request.intent),
        needed: request.value == null,
      );
      if (_disposed || refresh != _refresh) return;
      demand.visible(_visible);
      if (_disposed || refresh != _refresh) return;
    }
  }

  void retry() {
    if (_disposed || !_visible) return;
    for (final request in _requests.values.toList()) {
      if (_disposed || !_visible) return;
      if (request.target != null &&
          request.value == null &&
          !(_demands[request.roleId]?.reading ?? false)) {
        _publish(
          request.copyWith(intent: ++_intent, pending: false, error: null),
        );
      }
    }
    refresh();
  }

  void dispose() {
    _disposed = true;
    _visible = false;
    _refresh++;
    for (final demand in _demands.values) {
      demand.dispose();
    }
    _demands.clear();
    _requests.clear();
    // Never close/cancel an admitted Repository read from a VM lifetime.
  }
}
