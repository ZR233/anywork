import 'dart:convert';

/// The provenance of runtime usage fields in a Driver observation.
///
/// `unknown` is intentional: a missing live/authoritative usage observation is
/// not represented by zero-valued counters.
enum DriverRuntimeUsageState { live, authoritative, unknown }

class DriverRuntimeObservation {
  const DriverRuntimeObservation({
    required this.usageState,
    this.turnId,
    this.attemptId,
    this.observationSequence,
    this.revision,
    this.contextTokens,
    this.contextWindow,
    this.totalTokens,
    this.inputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.liveOutputTokens,
    this.turnOutputTokens,
    this.responseMillis,
    this.tokensPerSecond,
  });

  const DriverRuntimeObservation.unknown()
    : this(usageState: DriverRuntimeUsageState.unknown);

  final DriverRuntimeUsageState usageState;
  final String? turnId;
  final String? attemptId;
  final int? observationSequence;
  final int? revision;
  final int? contextTokens;
  final int? contextWindow;
  final int? totalTokens;
  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? liveOutputTokens;
  final int? turnOutputTokens;
  final int? responseMillis;
  final double? tokensPerSecond;

  bool get isLive => usageState == DriverRuntimeUsageState.live;

  bool get isAuthoritative =>
      usageState == DriverRuntimeUsageState.authoritative;

  Map<String, Object?> toJson() => {
    'usageState': usageState.name,
    'turnId': turnId,
    'attemptId': attemptId,
    'observationSequence': observationSequence,
    'revision': revision,
    'contextTokens': contextTokens,
    'contextWindow': contextWindow,
    'totalTokens': totalTokens,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'liveOutputTokens': liveOutputTokens,
    'turnOutputTokens': turnOutputTokens,
    'responseMillis': responseMillis,
    'tokensPerSecond': tokensPerSecond,
  };
}

DriverRuntimeObservation driverRuntimeObservation(
  Map<String, dynamic> snapshot,
) {
  final diagnostics = snapshot['driverDiagnostics'];
  final runtime = diagnostics is Map ? diagnostics['runtime'] : null;
  if (runtime is! Map) return const DriverRuntimeObservation.unknown();
  final parsedUsageState = _runtimeUsageState(runtime['usageState']);
  final turnId = _string(runtime['turnId']);
  final attemptId = _string(runtime['attemptId']);
  final observationSequence = _int(runtime['observationSequence']);
  final hasIdentity =
      turnId != null && attemptId != null && observationSequence != null;
  final metricsAvailable =
      (parsedUsageState == DriverRuntimeUsageState.live ||
          parsedUsageState == DriverRuntimeUsageState.authoritative) &&
      hasIdentity;
  final usageState = metricsAvailable
      ? parsedUsageState
      : DriverRuntimeUsageState.unknown;
  return DriverRuntimeObservation(
    usageState: usageState,
    turnId: metricsAvailable ? turnId : null,
    attemptId: metricsAvailable ? attemptId : null,
    observationSequence: metricsAvailable ? observationSequence : null,
    revision: _int(runtime['revision']),
    contextTokens: metricsAvailable ? _int(runtime['contextTokens']) : null,
    contextWindow: metricsAvailable ? _int(runtime['contextWindow']) : null,
    totalTokens: metricsAvailable ? _int(runtime['totalTokens']) : null,
    inputTokens: metricsAvailable ? _int(runtime['inputTokens']) : null,
    outputTokens: metricsAvailable ? _int(runtime['outputTokens']) : null,
    reasoningTokens: metricsAvailable ? _int(runtime['reasoningTokens']) : null,
    liveOutputTokens: metricsAvailable
        ? _int(runtime['liveOutputTokens'])
        : null,
    turnOutputTokens: metricsAvailable
        ? _int(runtime['turnOutputTokens'])
        : null,
    responseMillis: metricsAvailable ? _int(runtime['responseMillis']) : null,
    tokensPerSecond: metricsAvailable
        ? _double(runtime['tokensPerSecond'])
        : null,
  );
}

DriverRuntimeUsageState _runtimeUsageState(Object? value) => switch (value) {
  'live' => DriverRuntimeUsageState.live,
  'authoritative' => DriverRuntimeUsageState.authoritative,
  _ => DriverRuntimeUsageState.unknown,
};

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;

class DriverAttachmentObservation {
  const DriverAttachmentObservation({
    required this.id,
    required this.name,
    required this.modality,
    required this.previewReady,
    this.byteSize,
  });

  final String id;
  final String name;
  final String? modality;
  final bool? previewReady;
  final int? byteSize;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'modality': modality,
    'previewReady': previewReady,
    'byteSize': byteSize,
  };
}

class DriverComposerAttachmentObservation {
  const DriverComposerAttachmentObservation({
    required this.present,
    required this.previewReady,
    required this.attachments,
    this.attachmentGeneration,
    this.submissionPending,
    this.failed,
  });

  final bool? present;
  final bool? previewReady;
  final List<DriverAttachmentObservation> attachments;
  final int? attachmentGeneration;
  final bool? submissionPending;
  final bool? failed;

  Map<String, Object?> toJson() => {
    'present': present,
    'previewReady': previewReady,
    'attachmentGeneration': attachmentGeneration,
    'submissionPending': submissionPending,
    'failed': failed,
    'attachments': [for (final attachment in attachments) attachment.toJson()],
  };
}

DriverComposerAttachmentObservation driverComposerAttachments(
  Map<String, dynamic> snapshot, {
  String target = 'thread',
}) {
  final diagnostics = snapshot['driverDiagnostics'];
  final composer = diagnostics is Map ? diagnostics['composer'] : null;
  final targetValue = composer is Map ? composer[target] : null;
  if (targetValue is! Map) {
    return const DriverComposerAttachmentObservation(
      present: null,
      previewReady: null,
      attachments: [],
    );
  }
  final attachments = <DriverAttachmentObservation>[];
  final rawAttachments = targetValue['attachments'];
  if (rawAttachments is List) {
    for (final raw in rawAttachments) {
      if (raw is! Map || raw['id'] is! String) continue;
      attachments.add(
        DriverAttachmentObservation(
          id: raw['id'] as String,
          name: raw['name'] is String ? raw['name'] as String : '',
          modality: raw['modality'] as String?,
          previewReady: raw['previewReady'] as bool?,
          byteSize: _int(raw['byteSize']),
        ),
      );
    }
  }
  final previewReady = targetValue['previewReady'];
  return DriverComposerAttachmentObservation(
    present: targetValue['present'] as bool? ?? attachments.isNotEmpty,
    previewReady: previewReady is bool
        ? previewReady
        : attachments.isNotEmpty &&
              attachments.every(
                (attachment) => attachment.previewReady == true,
              ),
    attachments: attachments,
    attachmentGeneration: _int(targetValue['attachmentGeneration']),
    submissionPending: targetValue['submissionPending'] as bool?,
    failed: targetValue['failed'] as bool?,
  );
}

List<Map<String, dynamic>> driverAccountListObservation(
  Map<String, dynamic> snapshot,
) {
  final accounts = _accountObservation(snapshot)?['list'];
  if (accounts is! List) return const [];
  return [
    for (final account in accounts)
      if (account is Map) account.cast<String, dynamic>(),
  ];
}

List<Map<String, dynamic>> driverAccountDetailsObservation(
  Map<String, dynamic> snapshot,
) {
  final accounts = _accountObservation(snapshot)?['details'];
  if (accounts is! List) return const [];
  return [
    for (final account in accounts)
      if (account is Map) account.cast<String, dynamic>(),
  ];
}

Map<String, dynamic>? _accountObservation(Map<String, dynamic> snapshot) {
  final diagnostics = snapshot['driverDiagnostics'];
  final accounts = diagnostics is Map ? diagnostics['accounts'] : null;
  return accounts is Map ? accounts.cast<String, dynamic>() : null;
}

/// Verifies the list/detail split without treating a detail model modelId as a
/// list label. The list projection is deliberately metadata-only; model model_ids
/// remain observable only in the detail projection.
void verifyAccountListRedacted(
  Map<String, dynamic> snapshot, {
  required String fixtureModelId,
  String? accountId,
}) {
  final list = driverAccountListObservation(snapshot);
  if (list.isEmpty) {
    throw StateError('account list observation is unavailable');
  }
  final encodedList = jsonEncode(list);
  if (encodedList.contains(fixtureModelId)) {
    throw StateError(
      'account list observation leaked fixture model modelId $fixtureModelId',
    );
  }
  if (RegExp(r'\+\d+').hasMatch(encodedList)) {
    throw StateError('account list observation leaked a +N model label');
  }

  final details = driverAccountDetailsObservation(snapshot);
  final matchingAccount = accountId == null
      ? details
      : details.where((account) => account['id'] == accountId).toList();
  final hasModelDetail = matchingAccount.any((account) {
    final models = account['models'];
    return models is List &&
        models.any(
          (model) => model is Map && model['modelId'] == fixtureModelId,
        );
  });
  if (!hasModelDetail) {
    throw StateError(
      'account detail observation omitted fixture model $fixtureModelId',
    );
  }
}

/// 快照轮询的就绪事实。
///
/// 快照端点不是 runtime 事件流：它只说明当前展示投影「当时」看到什么，因此这里保留的
/// 计数**仅用于就绪**，永不作发布顺序判定输入。真实发布证据只来自
/// [DriverRuntimePublishEvidence]（Driver-only 记录器的实际 Client 发布回调）。
final class DriverRuntimeReadiness {
  factory DriverRuntimeReadiness(Iterable<DriverRuntimeObservation> samples) {
    final all = List<DriverRuntimeObservation>.unmodifiable(samples);
    final identities = <String, List<DriverRuntimeObservation>>{};
    for (final sample in all) {
      final turnId = sample.turnId;
      final attemptId = sample.attemptId;
      if (turnId == null || attemptId == null) continue;
      identities.putIfAbsent('$turnId\u0000$attemptId', () => []).add(sample);
    }
    return DriverRuntimeReadiness._(
      sampleCount: all.length,
      liveSampleCount: all.where((sample) => sample.isLive).length,
      foreignSampleCount: all
          .where(
            (sample) => sample.usageState == DriverRuntimeUsageState.unknown,
          )
          .length,
      identitySampleCounts: <Map<String, Object?>>[
        for (final entry in identities.entries.take(_readinessIdentityLimit))
          <String, Object?>{
            'turnId': entry.key.substring(0, entry.key.indexOf('\u0000')),
            'attemptId': entry.key.substring(entry.key.indexOf('\u0000') + 1),
            'samples': entry.value.length,
            'liveSamples': entry.value.where((sample) => sample.isLive).length,
          },
      ],
    );
  }

  const DriverRuntimeReadiness._({
    required this.sampleCount,
    required this.liveSampleCount,
    required this.foreignSampleCount,
    required this.identitySampleCounts,
  });

  final int sampleCount;
  final int liveSampleCount;
  final int foreignSampleCount;
  final List<Map<String, Object?>> identitySampleCounts;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': 'snapshotPoll',
    // 轮询样本只是就绪观察：它不能证明发布顺序、新鲜度或终态清除。
    'readinessOnly': true,
    'sampleCount': sampleCount,
    'liveSampleCount': liveSampleCount,
    'foreignSampleCount': foreignSampleCount,
    'identitySampleCounts': identitySampleCounts,
  };
}

/// 就绪事实里最多列出的身份组数：只读诊断，不值得为它保留无界分组。
const int _readinessIdentityLimit = 8;

/// 一条真实 Client runtime 发布事实的种类。
enum DriverRuntimePublishKind { baseline, live, cleared }

/// `cleared` 事实里被清除对象的引用。
///
/// 清除本身没有身份与 sequence：这里只是对被清除的那次 live 发布的引用。
final class DriverRuntimeClearedReference {
  const DriverRuntimeClearedReference({
    required this.turnId,
    required this.attemptId,
    required this.lastObservationSequence,
  });

  final String turnId;
  final String attemptId;
  final int lastObservationSequence;

  Map<String, Object?> toJson() => <String, Object?>{
    'turnId': turnId,
    'attemptId': attemptId,
    'lastObservationSequence': lastObservationSequence,
  };
}

/// 一条真实发布事实（严格 typed 读取，缺字段即报错，不填默认假值）。
final class DriverRuntimePublishFact {
  const DriverRuntimePublishFact._({
    required this.kind,
    required this.threadId,
    required this.turnId,
    required this.streamEpoch,
    required this.publicationRevision,
    required this.atUnixMillis,
    required this.attemptId,
    required this.observationSequence,
    required this.completionTokens,
    required this.responseMillis,
    required this.latestContextTokens,
    required this.clearedPreviousLive,
  });

  factory DriverRuntimePublishFact.parse(Object? value, int index) {
    final map = _requireMap(value, 'facts[$index]');
    final kind = switch (_requireString(map, 'kind', 'facts[$index]')) {
      'baseline' => DriverRuntimePublishKind.baseline,
      'live' => DriverRuntimePublishKind.live,
      'cleared' => DriverRuntimePublishKind.cleared,
      final other => throw StateError('facts[$index].kind is unknown: $other'),
    };
    final cleared = map['clearedPreviousLive'];
    final liveUsage = map['liveUsage'];
    final usageMap = liveUsage == null
        ? null
        : _requireMap(liveUsage, 'facts[$index].liveUsage');
    return DriverRuntimePublishFact._(
      kind: kind,
      threadId: _requireString(map, 'threadId', 'facts[$index]'),
      turnId: _requireString(map, 'turnId', 'facts[$index]'),
      streamEpoch: _requireInt(map, 'streamEpoch', 'facts[$index]'),
      publicationRevision: _requireInt(
        map,
        'publicationRevision',
        'facts[$index]',
      ),
      atUnixMillis: _requireInt(map, 'atUnixMillis', 'facts[$index]'),
      attemptId: _optionalString(map, 'attemptId', 'facts[$index]'),
      observationSequence: _optionalInt(
        map,
        'observationSequence',
        'facts[$index]',
      ),
      completionTokens: usageMap == null
          ? null
          : _optionalInt(
              usageMap,
              'completionTokens',
              'facts[$index].liveUsage',
            ),
      responseMillis: usageMap == null
          ? null
          : _optionalInt(usageMap, 'responseMillis', 'facts[$index].liveUsage'),
      latestContextTokens: usageMap == null
          ? null
          : _optionalInt(
              usageMap,
              'latestContextTokens',
              'facts[$index].liveUsage',
            ),
      clearedPreviousLive: cleared == null
          ? null
          : DriverRuntimeClearedReference(
              turnId: _requireString(
                _requireMap(cleared, 'facts[$index].clearedPreviousLive'),
                'turnId',
                'facts[$index].clearedPreviousLive',
              ),
              attemptId: _requireString(
                _requireMap(cleared, 'facts[$index].clearedPreviousLive'),
                'attemptId',
                'facts[$index].clearedPreviousLive',
              ),
              lastObservationSequence: _requireInt(
                _requireMap(cleared, 'facts[$index].clearedPreviousLive'),
                'lastObservationSequence',
                'facts[$index].clearedPreviousLive',
              ),
            ),
    );
  }

  final DriverRuntimePublishKind kind;
  final String threadId;
  final String turnId;
  final int streamEpoch;
  final int publicationRevision;
  final int atUnixMillis;
  final String? attemptId;
  final int? observationSequence;
  final int? completionTokens;
  final int? responseMillis;
  final int? latestContextTokens;
  final DriverRuntimeClearedReference? clearedPreviousLive;

  bool get isLive => kind == DriverRuntimePublishKind.live;
  bool get isBaseline => kind == DriverRuntimePublishKind.baseline;
  bool get isCleared => kind == DriverRuntimePublishKind.cleared;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'threadId': threadId,
    'turnId': turnId,
    'attemptId': attemptId,
    'streamEpoch': streamEpoch,
    'publicationRevision': publicationRevision,
    'atUnixMillis': atUnixMillis,
    'observationSequence': observationSequence,
    'liveUsage': observationSequence == null
        ? null
        : <String, Object?>{
            'completionTokens': completionTokens,
            'responseMillis': responseMillis,
            'latestContextTokens': latestContextTokens,
          },
    'clearedPreviousLive': clearedPreviousLive?.toJson(),
  };
}

/// Driver-only 记录器的一次实际 Client 发布取证。
///
/// 只消费真实发布回调记录的事实：不做轮询采样判定，不把 baseline 计作发布回调，
/// 也不把缺字段/缺清除的样本说成通过。
final class DriverRuntimePublishEvidence {
  const DriverRuntimePublishEvidence._({
    required this.targetThreadId,
    required this.targetTurnId,
    required this.attemptId,
    required this.streamEpoch,
    required this.phase,
    required this.observerCancelled,
    required this.overflowed,
    required this.error,
    required this.factLimit,
    required this.payloadOk,
    required this.facts,
  });

  /// 严格解析记录器的 `runtime-evidence-stop` 响应。
  ///
  /// 形状不符、身份不是被请求的 Thread／Turn、事实种类未知都直接抛错；
  /// 缺失字段不会被默认值填补。
  factory DriverRuntimePublishEvidence.parse(
    Object? decoded, {
    required String expectedThreadId,
    required String expectedTurnId,
  }) {
    final map = _requireMap(decoded, 'runtime-evidence-stop');
    final source = _requireString(map, 'source', 'runtime-evidence-stop');
    if (source != 'clientRuntimePublish') {
      throw StateError(
        'runtime-evidence-stop source is not clientRuntimePublish: $source',
      );
    }
    final threadId = _requireString(map, 'threadId', 'runtime-evidence-stop');
    final turnId = _requireString(map, 'turnId', 'runtime-evidence-stop');
    if (threadId != expectedThreadId || turnId != expectedTurnId) {
      throw StateError(
        'runtime-evidence-stop reported another target: '
        '$threadId/$turnId != $expectedThreadId/$expectedTurnId',
      );
    }
    final rawFacts = map['facts'];
    if (rawFacts is! List) {
      throw StateError('runtime-evidence-stop has no facts list');
    }
    final facts = <DriverRuntimePublishFact>[
      for (var index = 0; index < rawFacts.length; index += 1)
        DriverRuntimePublishFact.parse(rawFacts[index], index),
    ];
    return DriverRuntimePublishEvidence._(
      targetThreadId: threadId,
      targetTurnId: turnId,
      attemptId: _optionalString(map, 'attemptId', 'runtime-evidence-stop'),
      streamEpoch: _optionalInt(map, 'streamEpoch', 'runtime-evidence-stop'),
      phase: _requireString(map, 'phase', 'runtime-evidence-stop'),
      observerCancelled: _requireBool(
        map,
        'observerCancelled',
        'runtime-evidence-stop',
      ),
      overflowed: _requireBool(map, 'overflowed', 'runtime-evidence-stop'),
      error: _optionalString(map, 'error', 'runtime-evidence-stop'),
      factLimit: _requireInt(map, 'factLimit', 'runtime-evidence-stop'),
      payloadOk: _requireBool(map, 'ok', 'runtime-evidence-stop'),
      facts: List<DriverRuntimePublishFact>.unmodifiable(facts),
    );
  }

  final String targetThreadId;
  final String targetTurnId;
  final String? attemptId;
  final int? streamEpoch;
  final String phase;
  final bool observerCancelled;
  final bool overflowed;
  final String? error;
  final int factLimit;
  final bool payloadOk;
  final List<DriverRuntimePublishFact> facts;

  List<DriverRuntimePublishFact> get baselineFacts =>
      <DriverRuntimePublishFact>[
        for (final fact in facts)
          if (fact.isBaseline) fact,
      ];

  List<DriverRuntimePublishFact> get liveFacts => <DriverRuntimePublishFact>[
    for (final fact in facts)
      if (fact.isLive) fact,
  ];

  DriverRuntimePublishFact? get clearedFact {
    for (final fact in facts) {
      if (fact.isCleared) return fact;
    }
    return null;
  }

  /// 记录器确实关闭了自己的观察，且没有溢出/录制错误。
  bool get boundedAndClosed =>
      payloadOk &&
      phase == 'stopped' &&
      observerCancelled &&
      !overflowed &&
      error == null &&
      facts.length <= factLimit;

  /// 事实全部属于被请求的同一 Thread／Turn／epoch，且 live 事实只属于一个 attempt。
  bool get identityStable {
    if (facts.isEmpty || streamEpoch == null) return false;
    final liveAttempt = liveFacts.isEmpty ? null : liveFacts.first.attemptId;
    if (liveFacts.isNotEmpty && (liveAttempt == null || liveAttempt.isEmpty)) {
      return false;
    }
    return facts.every(
          (fact) =>
              fact.threadId == targetThreadId &&
              fact.turnId == targetTurnId &&
              fact.streamEpoch == streamEpoch,
        ) &&
        liveFacts.every((fact) => fact.attemptId == liveAttempt);
  }

  /// 至少两次真实 live 发布，且观察 sequence 严格递增（允许中间帧被合并跳过）。
  bool get liveSequenceIncreasing {
    final live = liveFacts;
    if (live.length < 2) return false;
    if (live.any((fact) => fact.observationSequence == null)) return false;
    for (var index = 1; index < live.length; index += 1) {
      final previous = live[index - 1].observationSequence!;
      if (live[index].observationSequence! <= previous) return false;
    }
    return true;
  }

  /// 每次真实发布的 workspace revision 也严格递增。
  bool get livePublicationRevisionsIncreasing {
    final live = liveFacts;
    if (live.length < 2) return false;
    for (var index = 1; index < live.length; index += 1) {
      if (live[index].publicationRevision <=
          live[index - 1].publicationRevision) {
        return false;
      }
    }
    return true;
  }

  /// 末次 live 之后出现一次显式清除，且清除的发布 revision 真实推进。
  bool get clearedAfterLive {
    final cleared = clearedFact;
    final live = liveFacts;
    if (cleared == null || live.isEmpty) return false;
    final reference = cleared.clearedPreviousLive;
    if (reference == null) return false;
    final lastLive = live.last;
    if (reference.turnId != targetTurnId ||
        reference.attemptId != lastLive.attemptId ||
        reference.lastObservationSequence != lastLive.observationSequence) {
      return false;
    }
    if (cleared.publicationRevision <= lastLive.publicationRevision) {
      return false;
    }
    final lastLiveIndex = facts.lastIndexWhere((fact) => fact.isLive);
    final clearedIndex = facts.indexWhere((fact) => fact.isCleared);
    return clearedIndex > lastLiveIndex;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'source': 'clientRuntimePublish',
    'targetThreadId': targetThreadId,
    'targetTurnId': targetTurnId,
    'attemptId': attemptId,
    'streamEpoch': streamEpoch,
    'phase': phase,
    'observerCancelled': observerCancelled,
    'overflowed': overflowed,
    'error': error,
    'factLimit': factLimit,
    'factCount': facts.length,
    'baselineFactCount': baselineFacts.length,
    'liveFactCount': liveFacts.length,
    'clearedFactCount': clearedFact == null ? 0 : 1,
    'boundedAndClosed': boundedAndClosed,
    'identityStable': identityStable,
    'liveSequenceIncreasing': liveSequenceIncreasing,
    'livePublicationRevisionsIncreasing': livePublicationRevisionsIncreasing,
    'clearedAfterLive': clearedAfterLive,
    'facts': <Object?>[for (final fact in facts) fact.toJson()],
  };
}

Map<String, dynamic> _requireMap(Object? value, String label) {
  if (value is! Map) {
    throw StateError('$label is not a JSON object: $value');
  }
  return value.cast<String, dynamic>();
}

String _requireString(Map<String, dynamic> map, String field, String label) {
  final value = map[field];
  if (value is! String || value.isEmpty) {
    throw StateError('$label.$field is not a non-empty string: $value');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String field, String label) {
  final value = map[field];
  if (value == null) return null;
  if (value is! String) {
    throw StateError('$label.$field is not a string: $value');
  }
  return value.isEmpty ? null : value;
}

int _requireInt(Map<String, dynamic> map, String field, String label) {
  final value = map[field];
  // JSON 整数就是 Dart `int`：浮点与数字字符串都不接受，不做静默截断。
  if (value is! int) {
    throw StateError('$label.$field is not an integer: $value');
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> map, String field, String label) {
  final value = map[field];
  if (value == null) return null;
  if (value is! int) {
    throw StateError('$label.$field is not an integer: $value');
  }
  return value;
}

bool _requireBool(Map<String, dynamic> map, String field, String label) {
  final value = map[field];
  if (value is! bool) {
    throw StateError('$label.$field is not a boolean: $value');
  }
  return value;
}
