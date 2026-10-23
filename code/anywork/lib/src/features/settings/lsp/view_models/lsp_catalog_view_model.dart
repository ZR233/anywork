import 'dart:async';

import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../../view_models/visible_read_demand.dart';
import '../state/lsp_view_state.dart';

part 'lsp_catalog_view_model.g.dart';

/// The source is global even with no selected project. Project actions have
/// their own non-null keyed VM, not a fabricated per-project LSP feed.
@riverpod
class LspCatalogViewModel extends _$LspCatalogViewModel {
  late LspRepository _repository;
  late VisibleReadDemand<(ProductReadOrigin, LspReadRef)> _servers;
  late VisibleReadDemand<(ProductReadOrigin, ProductSourceStatusRef)> _status;
  bool _alive = true;
  bool _visible = false;
  int _lifetime = 0;

  @override
  Future<LspCatalogViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _repository = ref.watch(lspRepositoryProvider);
    _servers = VisibleReadDemand(read: (key) async {
      final source = _repository.state.value.projection;
      if (source.stamp?.origin == key.$1 && source.header?.reference == key.$2) await _repository.loadServersPage();
    }, changed: (key, error, current) => _changed(LspReadField.servers, error, current, _servers.reading, lifetime));
    _status = VisibleReadDemand(read: (key) async {
      final source = _repository.state.value.projection;
      if (source.stamp?.origin == key.$1 && source.header?.source.status == key.$2) await _repository.loadSourceStatus();
    }, changed: (key, error, current) => _changed(LspReadField.status, error, current, _status.reading, lifetime));
    final tab = ref.read(settingsNavigationViewModelProvider.notifier).register(SettingsTab.lsp, SettingsTabLifecycle(visibility: setVisible));
    _visible = tab.visible;
    Observation? observation;
    ref.onDispose(() {
      _alive = false; _lifetime++; tab.unregister(); observation?.cancel(); _servers.dispose(); _status.dispose();
    });
    observation = _repository.state.watchLatest((source) {
      if (!_owns(lifetime)) return;
      state = AsyncData(state.requireValue.copyWith(source: source)); _refresh();
    }).observation;
    StudioFailure? issue;
    try { await _repository.loadSourceStatus(); } on StudioFailure catch (error) { issue = error; }
    if (failedReadIdentity(_repository.state.value.sourceStatus) case final key?) _status.remember(key);
    Future<void>(() { if (_owns(lifetime)) _refresh(); });
    return LspCatalogViewState(source: _repository.state.value, readIssues: {if (issue != null) LspReadField.status: issue});
  }
  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;
  void _changed(LspReadField field, StudioFailure? error, bool current, bool reading, int lifetime) {
    if (!_owns(lifetime)) return;
    final issues = {...state.requireValue.readIssues};
    if (current && !reading) { if (error == null) { issues.remove(field); } else { issues[field] = error; } }
    final pending = {...state.requireValue.reading};
    if (reading) { pending.add(field); } else { pending.remove(field); }
    state = AsyncData(state.requireValue.copyWith(readIssues: issues, reading: pending));
  }
  void setVisible(bool value) { if (!_alive) return; _visible = value; _refresh(); }
  void _refresh() {
    if (!_alive || state.asData == null) return;
    final source = _repository.state.value;
    final origin = source.projection.stamp?.origin;
    final reference = source.projection.header?.reference;
    final status = source.projection.header?.source.status;
    _servers.visible(false); _status.visible(false);
    _servers.target(origin == null || reference == null ? null : (origin, reference));
    _status.target(origin == null || status == null ? null : (origin, status),
      needed: !isCurrentRead(source.sourceStatus, status, origin));
    _servers.visible(_visible); _status.visible(_visible);
  }
  Future<void> refresh() async {
    if (!_alive || !_visible) return;
    if (_repository.state.value.projection.header == null) {
      final lifetime = _lifetime;
      StudioFailure? issue;
      try { await _repository.loadSourceStatus(); } on StudioFailure catch (error) { issue = error; }
      _changed(LspReadField.status, issue, true, false, lifetime);
    }
    _refresh(); _servers.retry(); _status.retry();
  }
  Future<void> loadMore() async {
    if (!_alive || !_visible || state.requireValue.reading.contains(LspReadField.servers)) return;
    final lifetime = _lifetime;
    _changed(LspReadField.servers, null, true, true, lifetime);
    StudioFailure? issue;
    try { await _repository.loadServersPage(); } on StudioFailure catch (error) { issue = error; }
    _changed(LspReadField.servers, issue, true, false, lifetime);
  }
}
