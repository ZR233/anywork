import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

import '../state/skills_view_state.dart';

typedef ActiveSkillsTarget = ({ConversationSession session, int selectionGeneration,
  ThreadFacetStamp origin, ThreadConfigurationReadRef reference, int count});

/// A Settings presentation borrower of an existing Session's configuration.
/// It never creates/closes a Session, publishes a domain mirror, or owns jobs.
final class ActiveSkillNamesRead {
  ActiveSkillNamesRead({required this.projectId, required this.conversations,
    required this.workspace, required this.changed, required this.cleanupErrorsChanged});
  final String projectId;
  final ConversationRepository conversations;
  final WorkspaceRepository workspace;
  final void Function(ActiveSkillNames? names, StudioFailure? error, bool reading, CloseReport? cleanup) changed;
  final void Function(List<StudioFailure>) cleanupErrorsChanged;
  Observation? _activeObservation;
  Observation? _workspaceObservation;
  Observation? _configurationObservation;
  ConversationSession? _session;
  ActiveSkillsTarget? _target;
  ActiveSkillsTarget? _attempted;
  ThreadConfigurationReadScope? _scope;
  final _retired = <ThreadConfigurationReadScope, CloseReport?>{};
  final _cleanupErrors = <ThreadConfigurationReadScope, StudioFailure>{};
  bool _visible = false;
  bool _disposed = false;
  bool _reading = false;
  int _generation = 0;

  void visible(bool visible) {
    if (_disposed || _visible == visible) return;
    _visible = visible; _generation++;
    if (!visible) {
      _activeObservation?.cancel(); _activeObservation = null;
      _workspaceObservation?.cancel(); _workspaceObservation = null;
      _configurationObservation?.cancel(); _configurationObservation = null; _session = null;
      _target = null; _scope?.requestClose();
      return;
    }
    _attempted = null;
    final generation = _generation;
    try {
      final active = conversations.active.watchLatest((_) => _refresh());
      if (_disposed || !_visible || generation != _generation) { active.observation.cancel(); return; }
      _activeObservation = active.observation;
      final selected = workspace.state.watchLatest((_) => _refresh());
      if (_disposed || !_visible || generation != _generation) { selected.observation.cancel(); return; }
      _workspaceObservation = selected.observation;
      _refresh();
    } on StudioFailure catch (error) { changed(null, error, false, null); }
  }
  void dispose() {
    _disposed = true; _visible = false; _generation++;
    _activeObservation?.cancel(); _workspaceObservation?.cancel(); _configurationObservation?.cancel();
    // Accepted reads finish their own finally; D1 supervises all scope owners.
  }
  void _refresh() {
    if (_disposed || !_visible) return;
    final selection = workspace.state.value;
    final candidate = conversations.active.value;
    final session = selection.selection.projectId == projectId && selection.selection.threadId == candidate?.threadId ? candidate : null;
    if (!identical(session, _session)) {
      _configurationObservation?.cancel(); _configurationObservation = null; _session = session;
      _target = null; _scope?.requestClose(); changed(null, null, false, null);
      if (_disposed || !_visible || !identical(_session, session)) return;
      if (session != null) {
        try {
          final configuration = session.configuration.watchLatest((_) => _refresh());
          if (_disposed || !_visible || !identical(_session, session)) { configuration.observation.cancel(); return; }
          _configurationObservation = configuration.observation;
        }
        on StudioFailure catch (error) { changed(null, error, false, null); return; }
      }
    }
    final configuration = session?.configuration.value;
    final origin = configuration?.stamp;
    final reference = configuration?.value?.details;
    final target = session == null || origin == null || reference == null || configuration?.sync.phase != FacetSyncPhase.ready ? null :
      (session: session, selectionGeneration: selection.selectionGeneration, origin: origin,
        reference: reference, count: configuration!.value!.activeSkillCount);
    if (_target != target) { _target = target; _scope?.requestClose(); changed(null, configuration?.sync.error, false, null); }
    _pump();
  }
  void _pump() {
    final target = _target;
    if (_disposed || !_visible || _reading || target == null || target == _attempted) return;
    _attempted = target; _reading = true;
    final generation = _generation;
    changed(null, null, true, null);
    if (!_owns(target, generation)) { _reading = false; _attempted = null; return; }
    unawaited(_load(target, generation));
  }
  bool _owns(ActiveSkillsTarget target, int generation) {
    if (_disposed || !_visible || _target != target || generation != _generation) return false;
    final selected = workspace.state.value;
    final configuration = target.session.configuration.value;
    return identical(conversations.active.value, target.session) && selected.selectionGeneration == target.selectionGeneration &&
      selected.selection.projectId == projectId && selected.selection.threadId == target.session.threadId &&
      configuration.sync.phase == FacetSyncPhase.ready && configuration.stamp == target.origin && configuration.value?.details == target.reference;
  }

  Future<void> _load(ActiveSkillsTarget target, int generation) async {
    ThreadConfigurationReadScope? scope;
    try {
      scope = await target.session.openConfiguration(target.reference, origin: target.origin);
      _scope = scope;
      if (!_owns(target, generation)) { scope.requestClose(); return; }
      final header = await scope.header();
      // D1 already validates the scope's origin/revision and page/text prefix.
      // Presentation additionally matches the frozen field count and indices.
      if (header.activeSkillCount != target.count || target.count < 0)
        throw _protocol('Active skill metadata returned a different frozen source.');
      final names = <String>[];
      var offset = 0;
      while (offset < target.count) {
        if (!_owns(target, generation)) return;
        final page = await scope.activeSkills(offset: offset, limit: 32);
        final end = offset + page.items.length;
        if (page.total != target.count || end > target.count)
          throw _protocol('Active skill page does not match its original read scope.');
        for (var index = 0; index < page.items.length; index++) {
          final item = page.items[index];
          if (item.index != offset + index) throw _protocol('Active skill indices are not a contiguous prefix.');
          names.add(await _text(scope, item.name, target, generation));
}
        offset = end;
      }
      if (_owns(target, generation)) changed(ActiveSkillNames(threadId: target.session.threadId,
        origin: target.origin, reference: target.reference, names: names), null, false, null);
    } on StudioFailure catch (error) {
      if (_owns(target, generation)) changed(null, error, false, null);
    } finally {
      try {
        if (scope != null) {
          scope.requestClose();
          _retired.putIfAbsent(scope, () => null);
          try {
          final report = await scope.close();
            _cleanupErrors.remove(scope);
          if (report.complete) { _retired.remove(scope); } else { _retired[scope] = report; }
            final cleanup = _cleanupReport;
            if (!_disposed && cleanup != null) changed(null, null, false, cleanup);
          } on StudioFailure catch (error) {
            _cleanupErrors[scope] = error;
          }
          if (!_disposed) cleanupErrorsChanged(_cleanupErrors.values.toList());
        }
      } finally {
        if (identical(_scope, scope)) _scope = null;
        _reading = false;
        _pump();
      }
    }
  }
  Future<String> _text(ThreadConfigurationReadScope scope, ReadText value, ActiveSkillsTarget target, int generation) async {
    if (value case InlineReadText(:final text)) return text;
    final deferred = value as DeferredReadText;
    if (deferred.utf8Bytes < 0) throw _protocol('Active skill name length is negative.');
    final text = StringBuffer();
    var offset = 0;
    while (offset < deferred.utf8Bytes) {
      if (!_owns(target, generation)) throw const StudioFailure(code: StudioFailureCode.superseded,
        message: 'The visible active-skill demand changed.', retryable: true, correlationId: 'settings-active-skills');
      final chunk = await scope.text(deferred.fieldId, offset: offset, maxBytes: 65536);
      final length = utf8.encode(chunk.text).length;
      final end = offset + length;
      if (end > deferred.utf8Bytes || chunk.nextOffset != (end == deferred.utf8Bytes ? null : end))
        throw _protocol('Active skill name text has a different UTF-8 prefix.');
      text.write(chunk.text); offset = end;
    }
    return text.toString();
  }
  CloseReport? get _cleanupReport => _retired.values.any((report) => report == null) ? null
    : CloseReport(unresolved: [for (final report in _retired.values) ...report!.unresolved]);
  Future<void> retry() async {
    if (_disposed || !_visible) return;
    for (final scope in List<ThreadConfigurationReadScope>.of(_retired.keys)) {
      try {
      final report = await (_retired[scope] == null ? scope.close() : scope.retryCleanup());
        _cleanupErrors.remove(scope);
      if (report.complete) { _retired.remove(scope); } else { _retired[scope] = report; }
      } on StudioFailure catch (error) { _cleanupErrors[scope] = error; }
    }
    if (_disposed || !_visible) return;
    cleanupErrorsChanged(_cleanupErrors.values.toList());
    final report = _cleanupReport;
    if (report != null) changed(null, null, false, report);
    visible(false); visible(true);
  }
  static StudioFailure _protocol(String message) => StudioFailure(code: StudioFailureCode.protocol,
    message: message, retryable: false, correlationId: 'settings-active-skills');
}
