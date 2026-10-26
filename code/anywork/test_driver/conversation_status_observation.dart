/// Passive execution identity from the original Session's canonical facet.
/// It never interprets Turn state as execution, consumption or saved evidence.
final class DriverExecutionObservation {
  const DriverExecutionObservation({
    required this.threadId,
    required this.stamp,
    required this.syncPhase,
    required this.loaded,
    required this.execution,
    required this.continuation,
  });
  final String? threadId, syncPhase;
  final Map<String, Object?>? stamp, execution, continuation;
  final bool loaded;
  bool get ready => syncPhase == 'ready' && loaded;
  bool get hasExecution => ready && execution != null;

  /// No execution is not evidence of a terminal or durable Turn.
  bool get readyWithoutExecution => ready && execution == null;
  String? get executionId => execution?['id'] as String?;
  bool sameSource(DriverExecutionObservation other) =>
      threadId != null &&
      threadId == other.threadId &&
      stamp != null &&
      other.stamp != null &&
      stamp!['runtimeEpoch'] == other.stamp!['runtimeEpoch'] &&
      stamp!['incarnation'] == other.stamp!['incarnation'];
  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'stamp': stamp,
    'syncPhase': syncPhase,
    'loaded': loaded,
    'execution': execution,
    'continuation': continuation,
  };
}

DriverExecutionObservation driverExecutionObservation(
  Map<String, dynamic> snapshot,
) {
  final group = _group(_diagnostics(snapshot), 'execution');
  _required(group, {
    'threadId',
    'stamp',
    'sync',
    'loaded',
    'execution',
    'continuation',
  });
  final stamp = _stamp(group['stamp'], 'execution');
  final sync = _optionalMap(group['sync']);
  final execution = _optionalMap(group['execution']);
  final continuation = _optionalMap(group['continuation']);
  final loaded = _bool(group['loaded']);
  if (loaded == null) throw StateError('Missing execution loaded fact');
  if (!loaded && (execution != null || continuation != null)) {
    throw StateError('Execution facts require a canonical baseline');
  }
  if (sync != null) _required(sync, {'phase'});
  if (sync?['phase'] == 'ready' &&
      (stamp == null || !loaded || _text(group['threadId']) == null)) {
    throw StateError('Ready execution requires its original stamp and value');
  }
  if (execution != null) {
    _required(execution, {'id', 'phase', 'turnId'});
    if (_text(execution['id']) == null || _text(execution['phase']) == null) {
      throw StateError('Invalid canonical execution identity');
    }
    _text(execution['turnId']);
  }
  if (continuation != null) {
    _required(continuation, {
      'id',
      'sourceTurnId',
      'reason',
      'createdAt',
      'claimed',
    });
    if (_text(continuation['id']) == null ||
        continuation['createdAt'] is! int ||
        _bool(continuation['claimed']) == null) {
      throw StateError('Invalid canonical continuation');
    }
    _text(continuation['sourceTurnId']);
    _text(continuation['reason']);
  }
  return DriverExecutionObservation(
    threadId: _text(group['threadId']),
    stamp: stamp == null ? null : Map.unmodifiable(stamp),
    syncPhase: _text(sync?['phase']),
    loaded: loaded,
    execution: execution == null ? null : Map.unmodifiable(execution),
    continuation: continuation == null ? null : Map.unmodifiable(continuation),
  );
}

/// Passive request-time readiness only. Identity/ordering proof belongs to the
/// asynchronous Metrics recorder, never to a numeric reference in this group.
final class DriverMetricsObservation {
  const DriverMetricsObservation({
    required this.ready,
    required this.threadId,
    required this.runtimeEpoch,
    required this.incarnation,
    required this.revision,
    required this.live,
    required this.observationSequence,
    required this.completionTokens,
    required this.responseMillis,
  });
  final bool ready, live;
  final String? threadId, runtimeEpoch;
  final int? incarnation,
      revision,
      observationSequence,
      completionTokens,
      responseMillis;
  bool get isLive => ready && live;
  Map<String, Object?> toJson() => {
    'ready': ready,
    'threadId': threadId,
    'metricsStamp': runtimeEpoch == null
        ? null
        : {
            'runtimeEpoch': runtimeEpoch,
            'incarnation': incarnation,
            'facet': 'metrics',
            'revision': revision,
          },
    'live': live,
    'observationSequence': observationSequence,
    'completionTokens': completionTokens,
    'responseMillis': responseMillis,
  };
}

DriverMetricsObservation driverMetricsObservation(
  Map<String, dynamic> snapshot,
) {
  final diagnostics = _diagnostics(snapshot);
  final metrics = _group(diagnostics, 'metrics');
  _required(metrics, {'threadId', 'stamp', 'sync', 'live', 'authoritative'});
  final stamp = _stamp(metrics['stamp'], 'metrics');
  final sync = _optionalMap(metrics['sync']);
  final live = _optionalMap(metrics['live']);
  if (sync != null) _required(sync, {'phase'});
  if (live != null) {
    _required(live, {
      'state',
      'observationSequence',
      'completionTokens',
      'responseMillis',
    });
  }
  if (sync?['phase'] == 'ready' && stamp == null) {
    throw StateError('Ready Metrics diagnostics require an original stamp');
  }
  return DriverMetricsObservation(
    ready: sync?['phase'] == 'ready',
    threadId: _text(metrics['threadId']),
    runtimeEpoch: _text(stamp?['runtimeEpoch']),
    incarnation: _number(stamp?['incarnation']),
    revision: _number(stamp?['revision']),
    live: live?['state'] == 'live',
    observationSequence: _number(live?['observationSequence']),
    completionTokens: _number(live?['completionTokens']),
    responseMillis: _number(live?['responseMillis']),
  );
}

final class DriverContextObservation {
  const DriverContextObservation({
    required this.threadId,
    required this.stamp,
    required this.syncPhase,
    required this.liveLatestContextTokens,
    required this.latestContextTokens,
    required this.contextWindow,
    required this.totalTokens,
    required this.promptTokens,
    required this.completionTokens,
    required this.reasoningTokens,
    required this.hasIncompleteUsage,
  });
  final String? threadId, syncPhase;
  final Map<String, Object?>? stamp;
  final int? liveLatestContextTokens, latestContextTokens, contextWindow;
  final int? totalTokens, promptTokens, completionTokens, reasoningTokens;
  final bool? hasIncompleteUsage;
  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'stamp': stamp,
    'syncPhase': syncPhase,
    'liveLatestContextTokens': liveLatestContextTokens,
    'latestContextTokens': latestContextTokens,
    'contextWindow': contextWindow,
    'totalTokens': totalTokens,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'reasoningTokens': reasoningTokens,
    'hasIncompleteUsage': hasIncompleteUsage,
  };
}

DriverContextObservation driverContextObservation(
  Map<String, dynamic> snapshot,
) {
  final context = _group(_diagnostics(snapshot), 'context');
  _required(context, {'threadId', 'stamp', 'sync', 'liveContext', 'usage'});
  final stamp = _stamp(context['stamp'], 'context');
  final sync = _optionalMap(context['sync']);
  final live = _optionalMap(context['liveContext']);
  final usage = _optionalMap(context['usage']);
  if (sync != null) _required(sync, {'phase'});
  if (live != null) _required(live, {'state', 'latestContextTokens'});
  if (usage != null) {
    _required(usage, {
      'latestContextTokens',
      'contextWindow',
      'totalTokens',
      'promptTokens',
      'completionTokens',
      'reasoningTokens',
      'hasIncompleteUsage',
    });
  }
  if (sync?['phase'] == 'ready' && stamp == null) {
    throw StateError('Ready Context diagnostics require an original stamp');
  }
  return DriverContextObservation(
    threadId: _text(context['threadId']),
    stamp: stamp == null
        ? null
        : Map<String, Object?>.unmodifiable(stamp.cast<String, Object?>()),
    syncPhase: _text(sync?['phase']),
    liveLatestContextTokens: _number(live?['latestContextTokens']),
    latestContextTokens: _number(usage?['latestContextTokens']),
    contextWindow: _number(usage?['contextWindow']),
    totalTokens: _number(usage?['totalTokens']),
    promptTokens: _number(usage?['promptTokens']),
    completionTokens: _number(usage?['completionTokens']),
    reasoningTokens: _number(usage?['reasoningTokens']),
    hasIncompleteUsage: _bool(usage?['hasIncompleteUsage']),
  );
}

/// Poll counts deliberately carry no Turn/attempt identity or publish verdict.
final class DriverRuntimeReadiness {
  factory DriverRuntimeReadiness(Iterable<DriverMetricsObservation> samples) {
    var sampleCount = 0, liveSampleCount = 0, unknownSampleCount = 0;
    for (final sample in samples) {
      sampleCount++;
      if (!sample.ready) unknownSampleCount++;
      if (sample.isLive) liveSampleCount++;
    }
    return DriverRuntimeReadiness._(
      sampleCount,
      liveSampleCount,
      unknownSampleCount,
    );
  }
  const DriverRuntimeReadiness._(
    this.sampleCount,
    this.liveSampleCount,
    this.unknownSampleCount,
  );
  final int sampleCount, liveSampleCount, unknownSampleCount;
  Map<String, Object?> toJson() => {
    'source': 'snapshotPoll',
    'readinessOnly': true,
    'sampleCount': sampleCount,
    'liveSampleCount': liveSampleCount,
    'unknownSampleCount': unknownSampleCount,
  };
}

Map<String, dynamic> _diagnostics(Map<String, dynamic> snapshot) {
  final value = snapshot['driverDiagnostics'];
  if (value is! Map ||
      value['schemaVersion'] is! int ||
      value['schemaVersion'] != 2) {
    throw StateError('Missing schema-v2 Driver diagnostics');
  }
  return value.cast<String, dynamic>();
}

Map<String, dynamic> _group(Map<String, dynamic> diagnostics, String name) {
  final value = diagnostics[name];
  if (value is! Map) throw StateError('Missing Driver $name diagnostics');
  return value.cast<String, dynamic>();
}

String? _text(Object? value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw StateError('Invalid Driver diagnostic string');
  }
  return value;
}

int? _number(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw StateError('Invalid Driver diagnostic integer');
  }
  return value;
}

Map<String, dynamic>? _optionalMap(Object? value) {
  if (value == null) return null;
  if (value is! Map) throw StateError('Invalid Driver diagnostic object');
  return value.cast<String, dynamic>();
}

void _required(Map<String, dynamic> map, Set<String> fields) {
  if (!fields.every(map.containsKey)) {
    throw StateError('Missing Driver diagnostic fields');
  }
}

Map<String, dynamic>? _stamp(Object? value, String facet) {
  final stamp = _optionalMap(value);
  if (stamp == null) return null;
  _required(stamp, {'runtimeEpoch', 'incarnation', 'facet', 'revision'});
  if (_text(stamp['runtimeEpoch']) == null ||
      stamp['facet'] != facet ||
      _number(stamp['incarnation']) == null ||
      _number(stamp['revision']) == null) {
    throw StateError('Invalid Driver facet stamp');
  }
  return stamp;
}

bool? _bool(Object? value) {
  if (value == null) return null;
  if (value is! bool) throw StateError('Invalid Driver diagnostic boolean');
  return value;
}
