import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import 'runtime_evidence_values.dart';
import 'runtime_identity_read.dart';

/// Driver-only, one run. Construction borrows no Session or graph. Composition
/// registers seal/close/retryCleanup with its existing exit coordinator first.
final class RuntimeEventEvidenceRecorder {
  RuntimeEventEvidenceRecorder({this.factLimit = defaultFactLimit}) {
    if (factLimit < 1 || factLimit > defaultFactLimit) throw ArgumentError.value(factLimit, 'factLimit');
    _baseline.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}).ignore();
  }
  static const int defaultFactLimit = 4096;
  static const String source = 'repositoryMetricsPublish';
  final int factLimit;
  final _facts = <RuntimePublishFact>[];
  final _pending = <_MetricsPublication>[];
  final _reads = <RuntimeIdentityRead>[];
  final _uncancelled = <Observation>[];
  // Pure ID associations only, within this concrete Session + Metrics origin.
  final _identities = <int, RuntimeObservedIdentity>{};
  final _baseline = Completer<RuntimePublishFact>();
  RuntimeEvidencePhase _phase = RuntimeEvidencePhase.idle;
  ConversationSession? _session;
  Observation? _metricsObservation;
  Observation? _activeObservation;
  ThreadFacetStamp? _origin;
  String? _threadId, _targetTurnId, _errorCode;
  Map<String, Object?>? _failure;
  RuntimeObservedIdentity? _identity;
  int? _lastSequence, _lastLiveRevision, _lastPublicationRevision;
  int _readSequence = 0;
  bool _baselineQueued = false, _processing = false, _draining = false;
  bool _admissionClosed = false, _shutdown = false, _overflowed = false;
  bool _hasActualLive = false, _cleared = false, _observerCancelled = false;
  Future<void>? _pump;
  Future<Map<String, Object?>>? _stopping;
  RuntimeEvidencePhase get phase => _phase;
  int get _used => _facts.length + _pending.length + (_processing ? 1 : 0) +
      _reads.where((read) => !read.done).length;

  Future<Map<String, Object?>> start({required ConversationRepository conversations,
    required String threadId, required String turnId}) {
    if (threadId.isEmpty || turnId.isEmpty) return Future.value(_rejection('runtime-evidence-start', 'invalidTarget'));
    if (_phase == RuntimeEvidencePhase.starting || _phase == RuntimeEvidencePhase.recording) {
      return Future.value(_rejection('runtime-evidence-start', 'alreadyRecording'));
    }
    if (_phase != RuntimeEvidencePhase.idle || _shutdown) {
      return Future.value(_rejection('runtime-evidence-start', 'runCompleted'));
    }
    final session = conversations.existingSession(threadId);
    if (session == null) return Future.value(_rejection('runtime-evidence-start', 'sessionNotOpen'));
    if (!identical(conversations.active.value, session) || session.threadId != threadId) {
      return Future.value(_rejection('runtime-evidence-start', 'sessionNotActive'));
    }
    // Claim before registration/first await; no replacement Session lookup later.
    _phase = RuntimeEvidencePhase.starting;
    _session = session; _threadId = threadId; _targetTurnId = turnId;
    try {
      final active = conversations.active.watchLatest((value) {
        if (!_admissionClosed && !identical(value, session)) _fail('sessionReplaced');
      });
      _activeObservation = active.observation;
      if (_admissionClosed || !identical(active.value, session)) {
        _fail('sessionReplaced');
      } else {
        final watched = session.metrics.watchLatest((value) => _accept(value, baseline: false));
        _metricsObservation = watched.observation;
        if (!_admissionClosed) _accept(watched.value, baseline: true);
      }
    } catch (error) { _fail('observerRegistrationFailed', error); }
    if (_admissionClosed) _cancelOwnObservations();
    return _startResult();
  }

  Future<Map<String, Object?>> _startResult() async {
    RuntimePublishFact? baseline;
    try { baseline = await _baseline.future; } catch (_) { /* already retained */ }
    return Map.unmodifiable({ ..._envelope('runtime-evidence-start'),
      'ok': _errorCode == null && _phase == RuntimeEvidencePhase.recording,
      'baseline': baseline?.toJson(),
    });
  }

  void _accept(ThreadMetricsState state, {required bool baseline}) {
    if (_admissionClosed) return;
    try {
      final stamp = state.stamp;
      if (state.sync.phase != FacetSyncPhase.ready || stamp == null || state.value == null) {
        _fail('metricsUnavailable', state.sync.error); return;
      }
      if (stamp.facet != ThreadFacet.metrics || stamp.runtimeEpoch.isEmpty ||
          stamp.incarnation < 0 || stamp.revision < 0) {
        _fail('metricsSourceInvalid'); return;
      }
      if (_used >= factLimit) { _overflowed = true; _fail('factOverflow'); return; }
      final publication = _MetricsPublication(stamp, state.value!.live,
        DateTime.now().millisecondsSinceEpoch, baseline);
      if (baseline) {
        _origin = stamp; _baselineQueued = true; _pending.insert(0, publication);
      } else { _pending.add(publication); }
      _kick();
    } catch (error) { _fail('observerFailed', error); }
  }

  void _kick() {
    if (_draining || !_baselineQueued) return;
    _draining = true;
    _pump = _drain();
    _pump!.then<void>((_) {}, onError: (Object error, StackTrace _) {
      _fail('processingFailed', error);
    }).ignore();
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        if (_errorCode != null || _shutdown) { _pending.clear(); break; }
        final publication = _pending.removeAt(0);
        _processing = true;
        RuntimePublishFact? fact;
        try { fact = await _process(publication); }
        catch (error) { _fail(error is RuntimeIdentityCleanupUnresolved ? 'closeUnresolved' : 'identityReadFailed', error); }
        finally { _processing = false; }
        if (fact != null && _errorCode == null) {
          _facts.add(fact);
          if (publication.baseline) {
            if (_phase == RuntimeEvidencePhase.starting) _phase = RuntimeEvidencePhase.recording;
            if (!_baseline.isCompleted) _baseline.complete(fact);
          }
        }
      }
    } catch (error) {
      _fail('processingFailed', error);
    } finally { _draining = false; }
  }

  Future<RuntimePublishFact?> _process(_MetricsPublication publication) async {
    final stamp = publication.stamp;
    final origin = _origin!;
    if (stamp.runtimeEpoch != origin.runtimeEpoch || stamp.incarnation != origin.incarnation ||
        stamp.facet != origin.facet || (_lastPublicationRevision != null &&
          stamp.revision < _lastPublicationRevision!)) throw runtimeEvidenceProtocol;
    _lastPublicationRevision = stamp.revision;
    final live = publication.live;
    RuntimeObservedIdentity? identity;
    if (live != null) {
      if (_cleared || live.state != TurnObservationState.live || live.observationSequence < 0) {
        throw runtimeEvidenceProtocol;
      }
      identity = await _readIdentity(live.identity, stamp);
      if (identity.turnId != _targetTurnId || (_identity != null &&
          (_identity!.turnId != identity.turnId || _identity!.attemptId != identity.attemptId))) {
        throw runtimeEvidenceProtocol;
      }
      _identity = identity;
      if (!publication.baseline && _lastSequence == live.observationSequence) return null;
      if (_lastSequence != null && live.observationSequence <= _lastSequence! ||
          _lastLiveRevision != null && stamp.revision <= _lastLiveRevision!) throw runtimeEvidenceProtocol;
      _lastSequence = live.observationSequence; _lastLiveRevision = stamp.revision;
      if (!publication.baseline) _hasActualLive = true;
    } else if (!publication.baseline) {
      if (!_hasActualLive || _cleared) return null;
      if (stamp.revision <= _lastLiveRevision!) throw runtimeEvidenceProtocol;
      _cleared = true;
      return RuntimePublishFact(kind: RuntimePublishFactKind.cleared, threadId: _threadId!,
        metricsStamp: stamp, atUnixMillis: publication.atUnixMillis,
        clearedPreviousLive: RuntimeClearedLiveReference(identity: _identity!,
          lastObservationSequence: _lastSequence!, lastMetricsRevision: _lastLiveRevision!));
    }
    return RuntimePublishFact(kind: publication.baseline ? RuntimePublishFactKind.baseline : RuntimePublishFactKind.live,
      threadId: _threadId!, metricsStamp: stamp, atUnixMillis: publication.atUnixMillis,
      observedIdentity: identity, observationSequence: live?.observationSequence,
      completionTokens: live?.completionTokens, responseMillis: live?.responseMillis);
  }

  Future<RuntimeObservedIdentity> _readIdentity(MetricsIdentityRef reference, ThreadFacetStamp origin) async {
    if (reference.entry < 0) throw runtimeEvidenceProtocol;
    final known = _identities[reference.entry];
    if (known != null) return known;
    if (_shutdown) throw runtimeEvidenceCancelled;
    if (_used >= factLimit) { _overflowed = true; _fail('factOverflow'); throw runtimeEvidenceCancelled; }
    final read = RuntimeIdentityRead(attempt: AttemptId(++_readSequence), origin: origin);
    _reads.add(read);
    // Native scope open is actually called here, not a lazy closure relabelled
    // as admitted. _reads already owns its opening receipt before reentrancy.
    read.start(() => _session!.openMetricsIdentity(reference, origin: origin));
    final identity = await read.result;
    _identities[reference.entry] = identity;
    return identity;
  }

  void _remember(String code, [Object? error]) {
    _errorCode ??= code;
    if (error != null) _failure ??= runtimeEvidenceFailure(error);
  }

  void _fail(String code, [Object? error]) {
    _remember(code, error); _phase = RuntimeEvidencePhase.failed; _admissionClosed = true;
    _cancelOwnObservations();
    if (!_baseline.isCompleted) _baseline.completeError(error ?? runtimeEvidenceProtocol);
  }

  void _cancelOwnObservations() {
    final observations = [_metricsObservation, _activeObservation, ..._uncancelled];
    _uncancelled.clear();
    _metricsObservation = null; _activeObservation = null;
    for (final observation in observations) {
      if (observation == null) continue;
      try { observation.cancel(); }
      catch (error) {
        _remember('observerCancelFailed', error);
        if (!observation.isCancelled) _uncancelled.add(observation);
      }
    }
    // Physical cancellation and the retained recording error are independent.
    _observerCancelled = _uncancelled.isEmpty;
  }

  /// Synchronous exit seal. Queued metadata that has not opened a native scope
  /// is cancelled; already admitted read work retains its original receipt.
  void seal() {
    if (_shutdown) return;
    _shutdown = true; _admissionClosed = true;
    if (_phase == RuntimeEvidencePhase.starting || _phase == RuntimeEvidencePhase.recording ||
        _phase == RuntimeEvidencePhase.stopping) _fail('cancelledByShutdown', runtimeEvidenceCancelled);
    _cancelOwnObservations(); _pending.clear();
    for (final read in _reads) {
      if (read.done) continue;
      try { read.seal(); } catch (error) { _remember('readSealFailed', error); }
    }
  }

  Future<Map<String, Object?>> stop({DateTime? deadline}) {
    final existing = _stopping;
    if (existing != null) return existing.then((result) => Map<String, Object?>.unmodifiable({
      ...result, 'ok': false, 'errorCode': 'alreadyStopped', 'recordedErrorCode': result['errorCode'],
    }));
    if (_phase == RuntimeEvidencePhase.idle) return Future.value(_rejection('runtime-evidence-stop', 'notStarted'));
    final completion = Completer<Map<String, Object?>>();
    _stopping = completion.future;
    _admissionClosed = true;
    if (_phase != RuntimeEvidencePhase.failed) _phase = RuntimeEvidencePhase.stopping;
    _cancelOwnObservations();
    _finishStop(deadline).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<Map<String, Object?>> _finishStop(DateTime? deadline) async {
    final report = await _join(deadline: deadline);
    if (!report.complete) {
      _remember('closeUnresolved');
      if (!_baseline.isCompleted) _baseline.completeError(runtimeEvidenceCancelled);
    }
    final liveCount = _facts.where((fact) => fact.kind == RuntimePublishFactKind.live).length;
    if (liveCount < 2 || !_cleared) _remember('liveEvidenceIncomplete');
    _phase = _errorCode == null ? RuntimeEvidencePhase.stopped : RuntimeEvidencePhase.failed;
    final result = Map<String, Object?>.unmodifiable({
      ..._envelope('runtime-evidence-stop'), 'ok': _errorCode == null && report.complete,
      'observerCancelled': _observerCancelled, 'readsJoined': !_draining && _reads.every((read) => read.done),
      'scopesClosed': report.complete, 'overflowed': _overflowed,
      'factLimit': factLimit, 'factCount': _facts.length,
      'closeUnresolved': runtimeCloseJson(report),
      'facts': List<Object?>.unmodifiable([for (final fact in _facts) fact.toJson()]),
    });
    return result;
  }

  Future<CloseReport> _join({DateTime? deadline, bool retry = false}) async {
    final pump = _pump;
    final joined = pump == null || await observeEvidenceCompletion(pump, () => !_draining, deadline);
    final reports = await Future.wait([for (final read in _reads) read.observe(deadline: deadline, retry: retry)]);
    final report = CloseReport(unresolved: [for (final value in reports) ...value.unresolved,
      if (_uncancelled.any((observation) => !observation.isCancelled))
        UnresolvedResource(owner: 'driver-runtime-evidence:observation', attemptId: const AttemptId(0),
          issues: [const FeedCloseIssue(diagnostic: StudioShutdownIssue(stage: 'driver-runtime-evidence',
            code: 'observerCancelPending', message: 'The original evidence observation is still registered',
            retryable: true, correlationId: 'driver-runtime-evidence'), recovery: CleanupRecovery.retryClose)]),
      if (!joined) UnresolvedResource(owner: 'driver-runtime-evidence:metadata',
        attemptId: const AttemptId(0), issues: [const FeedCloseIssue(
          diagnostic: StudioShutdownIssue(stage: 'driver-runtime-evidence', code: 'metadataJoinPending',
            message: 'Original admitted evidence metadata has not joined', retryable: true,
            correlationId: 'driver-runtime-evidence'), recovery: CleanupRecovery.awaitCompletion)])]);
    return report;
  }

  Future<CloseReport> close({DateTime? deadline}) { seal(); return _join(deadline: deadline); }
  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    seal();
    if (_uncancelled.isNotEmpty) _cancelOwnObservations();
    return _join(deadline: deadline, retry: true);
  }

  Map<String, Object?> _envelope(String command) => {
    'schemaVersion': 2, 'source': source, 'cmd': command, 'phase': _phase.name,
    'target': Map<String, Object?>.unmodifiable({'threadId': _threadId, 'turnId': _targetTurnId}),
    'metricsOrigin': _origin == null ? null : Map<String, Object?>.unmodifiable({
      'runtimeEpoch': _origin!.runtimeEpoch, 'incarnation': _origin!.incarnation, 'facet': _origin!.facet.name}),
    'errorCode': _errorCode, 'failure': _failure,
  };
  Map<String, Object?> _rejection(String command, String code) => Map.unmodifiable({
    ..._envelope(command), 'ok': false, 'errorCode': code,
  });
}

final class _MetricsPublication {
  const _MetricsPublication(this.stamp, this.live, this.atUnixMillis, this.baseline);
  final ThreadFacetStamp stamp;
  final LiveTurnMetrics? live;
  final int atUnixMillis;
  final bool baseline;
}
