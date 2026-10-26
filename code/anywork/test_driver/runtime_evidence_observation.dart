/// Strict schema-v2 consumer. No legacy stream/workspace watermarks or aliases.
final class DriverMetricsStamp {
  const DriverMetricsStamp(this.runtimeEpoch, this.incarnation, this.revision);
  final String runtimeEpoch;
  final int incarnation, revision;
  factory DriverMetricsStamp.parse(Object? value) {
    final map = _map(value, 'metricsStamp');
    _keys(map, {'runtimeEpoch', 'incarnation', 'facet', 'revision'});
    if (_string(map, 'facet') != 'metrics') {
      throw StateError('metricsStamp.facet must be metrics');
    }
    return DriverMetricsStamp(
      _string(map, 'runtimeEpoch'),
      _integer(map, 'incarnation'),
      _integer(map, 'revision'),
    );
  }
  Map<String, Object?> toJson() => {
    'runtimeEpoch': runtimeEpoch,
    'incarnation': incarnation,
    'facet': 'metrics',
    'revision': revision,
  };
}

final class DriverMetricsIdentity {
  const DriverMetricsIdentity(this.turnId, this.attemptId);
  final String turnId, attemptId;
  factory DriverMetricsIdentity.parse(Object? value) {
    final map = _map(value, 'observedIdentity');
    return DriverMetricsIdentity(
      _string(map, 'turnId'),
      _string(map, 'attemptId'),
    );
  }
  bool same(DriverMetricsIdentity other) =>
      turnId == other.turnId && attemptId == other.attemptId;
  Map<String, Object?> toJson() => {'turnId': turnId, 'attemptId': attemptId};
}

enum DriverRuntimePublishKind { baseline, live, cleared }

final class DriverRuntimeClearedReference {
  const DriverRuntimeClearedReference(
    this.identity,
    this.lastObservationSequence,
    this.lastMetricsRevision,
  );
  final DriverMetricsIdentity identity;
  final int lastObservationSequence, lastMetricsRevision;
  Map<String, Object?> toJson() => {
    ...identity.toJson(),
    'lastObservationSequence': lastObservationSequence,
    'lastMetricsRevision': lastMetricsRevision,
  };
}

final class DriverRuntimePublishFact {
  DriverRuntimePublishFact._({
    required this.kind,
    required this.threadId,
    required this.metricsStamp,
    required this.atUnixMillis,
    this.observedIdentity,
    this.observationSequence,
    this.completionTokens,
    this.responseMillis,
    this.clearedPreviousLive,
  });
  factory DriverRuntimePublishFact.parse(Object? value, int index) {
    final map = _map(value, 'facts[$index]');
    _keys(map, {
      'kind',
      'threadId',
      'metricsStamp',
      'atUnixMillis',
      'observedIdentity',
      'live',
      'clearedPreviousLive',
    });
    final kind = switch (_string(map, 'kind')) {
      'baseline' => DriverRuntimePublishKind.baseline,
      'live' => DriverRuntimePublishKind.live,
      'cleared' => DriverRuntimePublishKind.cleared,
      _ => throw StateError('Unknown Metrics publish fact kind'),
    };
    final identity = map['observedIdentity'] == null
        ? null
        : DriverMetricsIdentity.parse(map['observedIdentity']);
    if (identity != null) {
      _keys(_map(map['observedIdentity'], 'identity'), {'turnId', 'attemptId'});
    }
    final live = map['live'] == null ? null : _map(map['live'], 'live');
    final rawClear = map['clearedPreviousLive'];
    DriverRuntimeClearedReference? clear;
    if (rawClear != null) {
      final reference = _map(rawClear, 'clearedPreviousLive');
      _keys(reference, {
        'turnId',
        'attemptId',
        'lastObservationSequence',
        'lastMetricsRevision',
      });
      clear = DriverRuntimeClearedReference(
        DriverMetricsIdentity.parse(reference),
        _integer(reference, 'lastObservationSequence'),
        _integer(reference, 'lastMetricsRevision'),
      );
    }
    if (live != null) {
      _keys(live, {
        'observationSequence',
        'completionTokens',
        'responseMillis',
      });
    }
    if ((identity == null) != (live == null) ||
        kind == DriverRuntimePublishKind.live && live == null ||
        kind == DriverRuntimePublishKind.cleared &&
            (live != null || clear == null) ||
        kind != DriverRuntimePublishKind.cleared && clear != null) {
      throw StateError('Metrics publish fact identity shape is inconsistent');
    }
    return DriverRuntimePublishFact._(
      kind: kind,
      threadId: _string(map, 'threadId'),
      metricsStamp: DriverMetricsStamp.parse(map['metricsStamp']),
      atUnixMillis: _integer(map, 'atUnixMillis'),
      observedIdentity: identity,
      observationSequence: live == null
          ? null
          : _integer(live, 'observationSequence'),
      completionTokens: live == null
          ? null
          : _nullableInteger(live, 'completionTokens'),
      responseMillis: live == null
          ? null
          : _nullableInteger(live, 'responseMillis'),
      clearedPreviousLive: clear,
    );
  }
  final DriverRuntimePublishKind kind;
  final String threadId;
  final DriverMetricsStamp metricsStamp;
  final int atUnixMillis;
  final DriverMetricsIdentity? observedIdentity;
  final int? observationSequence, completionTokens, responseMillis;
  final DriverRuntimeClearedReference? clearedPreviousLive;
  bool get isLive => kind == DriverRuntimePublishKind.live;
  bool get isBaseline => kind == DriverRuntimePublishKind.baseline;
  bool get isCleared => kind == DriverRuntimePublishKind.cleared;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'threadId': threadId,
    'metricsStamp': metricsStamp.toJson(),
    'atUnixMillis': atUnixMillis,
    'observedIdentity': observedIdentity?.toJson(),
    'live': observationSequence == null
        ? null
        : {
            'observationSequence': observationSequence,
            'completionTokens': completionTokens,
            'responseMillis': responseMillis,
          },
    'clearedPreviousLive': clearedPreviousLive?.toJson(),
  };
}

final class DriverRuntimePublishEvidence {
  DriverRuntimePublishEvidence._({
    required this.targetThreadId,
    required this.targetTurnId,
    required this.runtimeEpoch,
    required this.incarnation,
    required this.phase,
    required this.observerCancelled,
    required this.readsJoined,
    required this.scopesClosed,
    required this.overflowed,
    required this.errorCode,
    required this.failure,
    required this.factLimit,
    required this.payloadOk,
    required this.closeUnresolved,
    required this.facts,
  });
  factory DriverRuntimePublishEvidence.parse(
    Object? decoded, {
    required String expectedThreadId,
    required String expectedTurnId,
  }) {
    final map = _map(decoded, 'runtime-evidence-stop');
    const fields = {
      'schemaVersion',
      'source',
      'cmd',
      'phase',
      'target',
      'metricsOrigin',
      'errorCode',
      'failure',
      'ok',
      'observerCancelled',
      'readsJoined',
      'scopesClosed',
      'overflowed',
      'factLimit',
      'factCount',
      'closeUnresolved',
      'facts',
    };
    if (!fields.every(map.containsKey) ||
        map.keys.any(
          (key) => !fields.contains(key) && key != 'recordedErrorCode',
        )) {
      throw StateError('Unexpected Metrics evidence envelope fields');
    }
    if (map.containsKey('recordedErrorCode')) {
      _nullableString(map, 'recordedErrorCode');
    }
    if (!{
      'idle',
      'starting',
      'recording',
      'stopping',
      'stopped',
      'failed',
    }.contains(_string(map, 'phase'))) {
      throw StateError('Unknown Metrics evidence phase');
    }
    if (_integer(map, 'schemaVersion') != 2 ||
        _string(map, 'source') != 'repositoryMetricsPublish' ||
        _string(map, 'cmd') != 'runtime-evidence-stop') {
      throw StateError('Unsupported Metrics evidence schema');
    }
    final target = _map(map['target'], 'target');
    _keys(target, {'threadId', 'turnId'});
    final thread = _string(target, 'threadId'),
        turn = _string(target, 'turnId');
    if (thread != expectedThreadId || turn != expectedTurnId) {
      throw StateError('Metrics evidence target mismatch');
    }
    final origin = _map(map['metricsOrigin'], 'metricsOrigin');
    _keys(origin, {'runtimeEpoch', 'incarnation', 'facet'});
    if (_string(origin, 'facet') != 'metrics') {
      throw StateError('Metrics evidence origin facet mismatch');
    }
    final rawFacts = map['facts'];
    if (rawFacts is! List) {
      throw StateError('Metrics evidence facts must be a list');
    }
    final limit = _integer(map, 'factLimit');
    if (limit < 1 ||
        limit > 4096 ||
        _integer(map, 'factCount') != rawFacts.length ||
        rawFacts.length > limit) {
      throw StateError('Metrics evidence bound/count mismatch');
    }
    final facts = [
      for (var index = 0; index < rawFacts.length; index++)
        DriverRuntimePublishFact.parse(rawFacts[index], index),
    ];
    if (facts.isEmpty ||
        !facts.first.isBaseline ||
        facts.skip(1).any((fact) => fact.isBaseline)) {
      throw StateError('Metrics evidence requires exactly one first baseline');
    }
    final failure = map['failure'];
    if (!map.containsKey('failure')) throw StateError('Missing failure');
    if (failure != null) {
      final error = _map(failure, 'failure');
      _keys(error, {'type', 'code', 'retryable', 'correlationId'});
      _string(error, 'type');
      _nullableString(error, 'code');
      _nullableString(error, 'correlationId');
      if (error['retryable'] != null && error['retryable'] is! bool) {
        throw StateError('Invalid failure.retryable');
      }
    }
    final rawClose = map['closeUnresolved'];
    if (rawClose is! List) throw StateError('Missing closeUnresolved');
    final close = <Object?>[];
    for (final value in rawClose) {
      final resource = _map(value, 'closeUnresolved resource');
      _keys(resource, {'owner', 'attemptId', 'issues'});
      _string(resource, 'owner');
      _integer(resource, 'attemptId');
      final issues = resource['issues'];
      if (issues is! List || issues.isEmpty) {
        throw StateError('Unresolved resource requires typed issues');
      }
      final copied = <Object?>[];
      for (final value in issues) {
        final issue = _map(value, 'close issue');
        _keys(issue, {'code', 'retryable', 'correlationId', 'recovery'});
        _string(issue, 'code');
        _boolean(issue, 'retryable');
        _nullableString(issue, 'correlationId');
        if (!{
          'awaitCompletion',
          'retryClose',
          'terminal',
        }.contains(_string(issue, 'recovery'))) {
          throw StateError('Unknown close recovery');
        }
        copied.add(Map<String, Object?>.unmodifiable(issue));
      }
      close.add(
        Map<String, Object?>.unmodifiable({
          'owner': resource['owner'],
          'attemptId': resource['attemptId'],
          'issues': List<Object?>.unmodifiable(copied),
        }),
      );
    }
    return DriverRuntimePublishEvidence._(
      targetThreadId: thread,
      targetTurnId: turn,
      runtimeEpoch: _string(origin, 'runtimeEpoch'),
      incarnation: _integer(origin, 'incarnation'),
      phase: _string(map, 'phase'),
      observerCancelled: _boolean(map, 'observerCancelled'),
      readsJoined: _boolean(map, 'readsJoined'),
      scopesClosed: _boolean(map, 'scopesClosed'),
      overflowed: _boolean(map, 'overflowed'),
      errorCode: _nullableString(map, 'errorCode'),
      failure: failure == null
          ? null
          : Map<String, Object?>.unmodifiable(_map(failure, 'failure')),
      factLimit: limit,
      payloadOk: _boolean(map, 'ok'),
      closeUnresolved: List.unmodifiable(close),
      facts: List.unmodifiable(facts),
    );
  }
  final String targetThreadId, targetTurnId, runtimeEpoch, phase;
  final int incarnation, factLimit;
  final bool observerCancelled,
      readsJoined,
      scopesClosed,
      overflowed,
      payloadOk;
  final String? errorCode;
  final Map<String, Object?>? failure;
  final List<Object?> closeUnresolved;
  final List<DriverRuntimePublishFact> facts;
  List<DriverRuntimePublishFact> get baselineFacts => [
    for (final fact in facts)
      if (fact.isBaseline) fact,
  ];
  List<DriverRuntimePublishFact> get liveFacts => [
    for (final fact in facts)
      if (fact.isLive) fact,
  ];
  DriverRuntimePublishFact? get clearedFact {
    for (final fact in facts) {
      if (fact.isCleared) return fact;
    }
    return null;
  }

  bool get boundedAndClosed =>
      payloadOk &&
      phase == 'stopped' &&
      observerCancelled &&
      readsJoined &&
      scopesClosed &&
      !overflowed &&
      errorCode == null &&
      failure == null &&
      closeUnresolved.isEmpty &&
      facts.length <= factLimit;
  bool get identityStable {
    final live = liveFacts;
    if (live.isEmpty) return false;
    final identity = live.first.observedIdentity!;
    return identity.turnId == targetTurnId &&
        facts.every(
          (fact) =>
              fact.threadId == targetThreadId &&
              fact.metricsStamp.runtimeEpoch == runtimeEpoch &&
              fact.metricsStamp.incarnation == incarnation &&
              (fact.observedIdentity == null ||
                  fact.observedIdentity!.same(identity)),
        );
  }

  bool get liveSequenceIncreasing {
    final live = liveFacts;
    if (live.length < 2) return false;
    int? previous = facts.first.observationSequence;
    for (final fact in live) {
      if (previous != null && fact.observationSequence! <= previous) {
        return false;
      }
      previous = fact.observationSequence;
    }
    return true;
  }

  bool get liveMetricsRevisionsIncreasing {
    final live = liveFacts;
    if (live.length < 2) return false;
    var previous = facts.first.metricsStamp.revision;
    for (final fact in live) {
      if (fact.metricsStamp.revision <= previous) return false;
      previous = fact.metricsStamp.revision;
    }
    return true;
  }

  bool get clearedAfterLive {
    final clears = facts.where((fact) => fact.isCleared).toList();
    final live = liveFacts;
    if (clears.length != 1 || live.isEmpty) return false;
    final clear = clears.single, last = live.last;
    final reference = clear.clearedPreviousLive!;
    return identityStable &&
        reference.identity.same(last.observedIdentity!) &&
        reference.lastObservationSequence == last.observationSequence &&
        reference.lastMetricsRevision == last.metricsStamp.revision &&
        clear.metricsStamp.revision > last.metricsStamp.revision &&
        facts.indexOf(clear) > facts.lastIndexOf(last);
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'source': 'repositoryMetricsPublish',
    'target': {'threadId': targetThreadId, 'turnId': targetTurnId},
    'metricsOrigin': {
      'runtimeEpoch': runtimeEpoch,
      'incarnation': incarnation,
      'facet': 'metrics',
    },
    'phase': phase,
    'observerCancelled': observerCancelled,
    'readsJoined': readsJoined,
    'scopesClosed': scopesClosed,
    'overflowed': overflowed,
    'errorCode': errorCode,
    'failure': failure,
    'factLimit': factLimit,
    'factCount': facts.length,
    'baselineFactCount': baselineFacts.length,
    'liveFactCount': liveFacts.length,
    'clearedFactCount': clearedFact == null ? 0 : 1,
    'boundedAndClosed': boundedAndClosed,
    'identityStable': identityStable,
    'liveSequenceIncreasing': liveSequenceIncreasing,
    'liveMetricsRevisionsIncreasing': liveMetricsRevisionsIncreasing,
    'clearedAfterLive': clearedAfterLive,
    'closeUnresolved': closeUnresolved,
    'facts': [for (final fact in facts) fact.toJson()],
  };
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw StateError('$label must be a string-keyed object');
  }
  return value.cast<String, dynamic>();
}

void _keys(Map<String, dynamic> map, Set<String> fields) {
  if (map.length != fields.length || !fields.every(map.containsKey)) {
    throw StateError('Unexpected Metrics evidence fields');
  }
}

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw StateError('Missing/invalid $key');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> map, String key) {
  if (!map.containsKey(key) || map[key] != null && map[key] is! String) {
    throw StateError('Missing/invalid nullable $key');
  }
  return map[key] as String?;
}

int _integer(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int || value < 0) {
    throw StateError('Missing/invalid integer $key');
  }
  return value;
}

int? _nullableInteger(Map<String, dynamic> map, String key) {
  if (!map.containsKey(key)) throw StateError('Missing nullable $key');
  return map[key] == null ? null : _integer(map, key);
}

bool _boolean(Map<String, dynamic> map, String key) {
  if (map[key] is! bool) throw StateError('Missing/invalid boolean $key');
  return map[key] as bool;
}
