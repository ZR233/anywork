// Driver-only 有界 runtime 发布记录器（design/26 §26.9、design/24 实时验收）。
//
// 它被动观察**已经存在**的 Client Session 的公开 runtime read-model 发布：不创建 Session、
// 不建立另一条 transport 订阅、不改变业务 demand，也不写产品状态。记录器只保留小型 typed
// 事实（Thread／Turn／attempt、实际发布 revision、观察 sequence 与轻量计量），不保存正文、
// 整份工作区快照或 Timeline 投影。
//
// 当前 core 的生产链只发布 `live` 观察，attempt 提交时清除它（`runtime.liveUsage` 变回
// null）。因此记录器分别记录同身份的多次真实 `live` Client 发布，以及之后的一次显式
// `cleared`；它不伪造 authoritative 事件、终态 sequence 或计量值，也不把无身份的 unknown
// 快照拼成同身份终态。
//
// 生命周期只有四种状态：idle → recording → stopped | failed。停止与退出都只取消**自己的**
// 观察，从不关闭共享 Session／Client。

import 'package:anywork_client/studio_client.dart';

/// 记录器生命周期。
enum RuntimeEvidencePhase { idle, recording, stopped, failed }

/// 一条真实 Client runtime 发布事实的种类。
///
/// `baseline` 是登记时同一个同步事务里读到的基线，独立标记、**不计作**一次真实发布回调；
/// `live` 是同 Turn／attempt 的一次真实发布；`cleared` 是该观察被显式清除后的独立事实。
enum RuntimePublishFactKind { baseline, live, cleared }

/// `cleared` 事实里被清除对象的引用（不是“None 自带身份”）。
final class RuntimeClearedLiveReference {
  const RuntimeClearedLiveReference({
    required this.turnId,
    required this.attemptId,
    required this.lastObservationSequence,
  });

  final String turnId;
  final String attemptId;
  final int lastObservationSequence;

  Map<String, Object?> toJson() =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'turnId': turnId,
        'attemptId': attemptId,
        'lastObservationSequence': lastObservationSequence,
      });
}

/// 一条小型 typed 发布事实；[toJson] 是它唯一的序列化形状。
///
/// 序列化结果是**不可修改**的（列表/嵌套 map 同样冻结）：停止后不保留任何可改写内部
/// 取证结果的别名。
final class RuntimePublishFact {
  const RuntimePublishFact({
    required this.kind,
    required this.threadId,
    required this.turnId,
    required this.streamEpoch,
    required this.publicationRevision,
    required this.atUnixMillis,
    this.attemptId,
    this.observationSequence,
    this.completionTokens,
    this.decodeMillis,
    this.latestContextTokens,
    this.clearedPreviousLive,
  });

  final RuntimePublishFactKind kind;
  final String threadId;
  final String turnId;
  final int streamEpoch;

  /// 该次实际发布的 `ThreadSessionState.revision`（等于 workspace revision）。
  final int publicationRevision;
  final int atUnixMillis;

  /// `live`／`baseline` 携带的 attempt 身份；`cleared` 不带（清除没有身份）。
  final String? attemptId;

  /// 该次 `liveUsage.observationSequence`；缺失不为 0。
  final int? observationSequence;

  /// account 确认的轻量计量，缺失保持 null，不以 0 猜测。
  final int? completionTokens;
  final int? decodeMillis;
  final int? latestContextTokens;

  /// 仅 `cleared` 携带：被清除的 live 观察引用。
  final RuntimeClearedLiveReference? clearedPreviousLive;

  Map<String, Object?> toJson() =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
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
            : Map<String, Object?>.unmodifiable(<String, Object?>{
                'completionTokens': completionTokens,
                'decodeMillis': decodeMillis,
                'latestContextTokens': latestContextTokens,
              }),
        'clearedPreviousLive': clearedPreviousLive?.toJson(),
      });
}

/// Driver-only runtime 发布记录器。
///
/// 它借用当前 AppGraph 的 Client，在**已存在的** Session 上登记一个观察；登记与首个基线
/// 读取是同一个同步边界（`LatestValue.watchLatest` 语义），因此没有 await 竞态。
final class RuntimeEventEvidenceRecorder {
  RuntimeEventEvidenceRecorder(
    this._client, {
    this.factLimit = defaultFactLimit,
  });

  /// 事实上限：溢出必须显式失败，不能裁剪样本冒完整。
  static const int defaultFactLimit = 4096;

  static const String source = 'clientRuntimePublish';

  final AnyworkClient _client;
  final int factLimit;

  final List<RuntimePublishFact> _facts = <RuntimePublishFact>[];
  RuntimeEvidencePhase _phase = RuntimeEvidencePhase.idle;
  String? _threadId;
  String? _turnId;
  String? _attemptId;
  int? _streamEpoch;

  /// 实际发布前沿：由 baseline 携带的 live 观察初始化（若存在），之后只被**真实**
  /// live 回调推进。等 seq 的再次发布不计事实，回退/换 attempt/错 Turn 明确失败。
  int? _lastLiveRevision;
  int? _lastLiveSequence;

  /// 是否已经记录过**至少一次真实 live 回调**。baseline 永远不算；
  /// 没有真实 live 回调时，`liveUsage == null` 不是清除事实。
  bool _hasActualLive = false;
  bool _cleared = false;
  bool _overflowed = false;
  bool _observerCancelled = false;
  bool _cancelledByShutdown = false;
  String? _error;
  int? _startedAtUnixMillis;
  int? _stoppedAtUnixMillis;
  Map<String, Object?>? _result;
  void Function()? _cancelObservation;

  RuntimeEvidencePhase get phase => _phase;

  /// 开始记录；成功返回基线事实，失败返回 typed 错误（不抛给 Driver 命令入口）。
  ///
  /// 任前置条件不满足都明确失败：记录器不复用旧 run、不新建资源、不猜身份。
  Map<String, Object?> start({
    required String threadId,
    required String turnId,
  }) {
    if (threadId.isEmpty || turnId.isEmpty) {
      return _rejection(
        'runtime-evidence-start',
        'invalidTarget',
        'threadId and turnId must be non-empty',
      );
    }
    if (_phase == RuntimeEvidencePhase.recording) {
      return _rejection(
        'runtime-evidence-start',
        'alreadyRecording',
        'this recorder is already recording',
      );
    }
    if (_phase != RuntimeEvidencePhase.idle) {
      return _rejection(
        'runtime-evidence-start',
        'runCompleted',
        'a finished run is never reused; create a new recorder',
      );
    }
    final session = _client.existingSession(threadId);
    if (session == null) {
      return _rejection(
        'runtime-evidence-start',
        'sessionNotOpen',
        'no existing Client Session for thread $threadId',
      );
    }
    if (!session.isActive) {
      return _rejection(
        'runtime-evidence-start',
        'sessionNotActive',
        'the existing Session is retired',
      );
    }
    final current = session.state;
    if (!current.hasSnapshot || current.workspace == null) {
      return _rejection(
        'runtime-evidence-start',
        'sessionHasNoSnapshot',
        'the existing Session has no applied Thread snapshot',
      );
    }
    if (current.runtime == null) {
      return _rejection(
        'runtime-evidence-start',
        'sessionHasNoRuntime',
        'the existing Session workspace carries no runtime view',
      );
    }
    if (current.threadId != threadId) {
      return _rejection(
        'runtime-evidence-start',
        'threadMismatch',
        'the Session belongs to another thread',
      );
    }
    final activeTurnId = current.activeTurn?.turnId;
    final latestTurnId = current.workspace?.latestTurn?.turnId;
    if (activeTurnId != turnId && latestTurnId != turnId) {
      return _rejection(
        'runtime-evidence-start',
        'targetTurnMismatch',
        'activeTurn=$activeTurnId latestTurn=$latestTurnId do not match $turnId',
      );
    }
    // 登记与基线读取是同一个同步边界：watchLatest 同步登记观察者并返回登记时的值，
    // 因此下面的基线事实就是登记那一刻的发布事实，不可能是“稍后再读”的样本。
    final watch = session.source.watchLatest(_onPublish);
    final baselineState = watch.value;
    final baselineEpoch = baselineState.streamEpoch;
    if (baselineEpoch == null) {
      watch.observation.cancel();
      return _rejection(
        'runtime-evidence-start',
        'missingStreamEpoch',
        'the state stream has no epoch watermark yet',
      );
    }
    if (baselineState.threadId != threadId ||
        baselineState.workspace == null ||
        baselineState.runtime == null) {
      watch.observation.cancel();
      return _rejection(
        'runtime-evidence-start',
        'baselineUnusable',
        'the registered baseline lost its thread/workspace/runtime facts',
      );
    }
    final baselineUsage = baselineState.runtime!.liveUsage;
    // baseline 携带 live 观察时，它必须真的是本目标 Turn 的 live 事实：不把别的 Turn
    // 的 usage 贴上目标标签，也不把非 live 状态当成 live 起点。
    if (baselineUsage != null) {
      if (baselineUsage.turnId != turnId) {
        watch.observation.cancel();
        return _rejection(
          'runtime-evidence-start',
          'baselineForeignTurn',
          'baseline live usage belongs to ${baselineUsage.turnId}, not $turnId',
        );
      }
      if (baselineUsage.state != ThreadRuntimeUsageState.live) {
        watch.observation.cancel();
        return _rejection(
          'runtime-evidence-start',
          'baselineNotLive',
          'baseline usage state is ${baselineUsage.state.name}, not live',
        );
      }
      if (baselineUsage.attemptId.isEmpty) {
        watch.observation.cancel();
        return _rejection(
          'runtime-evidence-start',
          'baselineMissingAttempt',
          'baseline live usage carries no attempt identity',
        );
      }
    }
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    _cancelObservation = watch.observation.cancel;
    _threadId = threadId;
    _turnId = turnId;
    _streamEpoch = baselineEpoch;
    if (baselineUsage != null) {
      // 与真实回调共用同一前沿：之后必须相对 baseline 的 attempt/seq/rev 继续推进。
      _attemptId = baselineUsage.attemptId;
      _lastLiveSequence = baselineUsage.observationSequence;
      _lastLiveRevision = baselineState.revision;
    }
    _startedAtUnixMillis = startedAt;
    _phase = RuntimeEvidencePhase.recording;
    final baseline = RuntimePublishFact(
      kind: RuntimePublishFactKind.baseline,
      threadId: threadId,
      turnId: turnId,
      streamEpoch: baselineEpoch,
      publicationRevision: baselineState.revision,
      atUnixMillis: startedAt,
      attemptId: baselineUsage?.attemptId,
      observationSequence: baselineUsage?.observationSequence,
      completionTokens: baselineUsage?.completionTokens,
      decodeMillis: baselineUsage?.decodeMillis,
      latestContextTokens: baselineUsage?.latestContextTokens,
    );
    _facts.add(baseline);
    return <String, Object?>{
      'ok': true,
      'cmd': 'runtime-evidence-start',
      'source': source,
      'phase': _phase.name,
      'threadId': threadId,
      'turnId': turnId,
      'streamEpoch': baselineEpoch,
      'attemptId': baselineUsage?.attemptId,
      'baselinePublicationRevision': baselineState.revision,
      'baseline': baseline.toJson(),
    };
  }

  /// 同步取消自己的观察并返回不可变结果副本。
  ///
  /// 未开始、重复停止都不会复用旧 run；录制中的 typed 错误随结果一起返回，宿主据此判失败。
  Map<String, Object?> stop() {
    if (_phase == RuntimeEvidencePhase.idle) {
      return _rejection(
        'runtime-evidence-stop',
        'notStarted',
        'runtime evidence was never started',
      );
    }
    final existing = _result;
    if (existing != null) {
      return <String, Object?>{
        ...existing,
        'ok': false,
        'error': 'alreadyStopped',
        'recordedError': existing['error'],
      };
    }
    _cancelOwnObservation();
    if (_cancelledByShutdown) {
      _error ??= 'cancelledByShutdown';
      if (_phase == RuntimeEvidencePhase.recording) {
        _phase = RuntimeEvidencePhase.failed;
      }
    }
    _stoppedAtUnixMillis = DateTime.now().millisecondsSinceEpoch;
    if (_phase == RuntimeEvidencePhase.recording) {
      _phase = RuntimeEvidencePhase.stopped;
    }
    final orderedFacts = List<RuntimePublishFact>.unmodifiable(_facts);
    // 结果与其 facts、嵌套 map 全部不可修改：调用方拿不到可改写内部取证的别名。
    final result = Map<String, Object?>.unmodifiable(<String, Object?>{
      'ok': _error == null && !_overflowed,
      'cmd': 'runtime-evidence-stop',
      'source': source,
      'phase': _phase.name,
      'observerCancelled': _observerCancelled,
      'overflowed': _overflowed,
      'error': _error,
      'threadId': _threadId,
      'turnId': _turnId,
      'attemptId': _attemptId,
      'streamEpoch': _streamEpoch,
      'startedAtUnixMillis': _startedAtUnixMillis,
      'stoppedAtUnixMillis': _stoppedAtUnixMillis,
      'factLimit': factLimit,
      'factCount': orderedFacts.length,
      'liveFactCount': orderedFacts
          .where((fact) => fact.kind == RuntimePublishFactKind.live)
          .length,
      'cleared': _cleared,
      'facts': List<Object?>.unmodifiable(<Object?>[
        for (final fact in orderedFacts) fact.toJson(),
      ]),
    });
    _result = result;
    return result;
  }

  /// 退出路径在 `graph.close` 之前取消自己的观察；不关闭共享 Session／Client，
  /// 也不改变业务 demand。
  void cancelForShutdown() {
    if (_phase != RuntimeEvidencePhase.recording) return;
    _cancelledByShutdown = true;
    _error ??= 'cancelledByShutdown';
    _cancelOwnObservation();
    _phase = RuntimeEvidencePhase.failed;
  }

  /// 观察者回调：同步、无 await、不修改业务状态，异常自己收下并取消本观察。
  ///
  /// `LatestValue.publish` 会同步逐个投递，listener 抛错会变成 Zone 未捕获错误，所以
  /// 这里必须自己捕获：存成有界 typed error 让 `stop()` 失败，而不是抛回业务回调或吞成成功。
  void _onPublish(ThreadSessionState state) {
    if (_phase != RuntimeEvidencePhase.recording) return;
    try {
      _observe(state);
    } on Object catch (error) {
      _fail('observerError', '$error');
    }
  }

  void _observe(ThreadSessionState state) {
    if (state.threadId != _threadId) {
      _fail('threadIdentityChanged', '$_threadId -> ${state.threadId}');
      return;
    }
    if (state.streamEpoch != _streamEpoch) {
      _fail('streamEpochChanged', '$_streamEpoch -> ${state.streamEpoch}');
      return;
    }
    final workspace = state.workspace;
    if (workspace == null) {
      _fail('workspaceUnavailable', 'a publication carried no workspace');
      return;
    }
    final usage = workspace.runtime.liveUsage;
    if (usage == null) {
      _observeCleared(state, workspace);
      return;
    }
    if (usage.turnId != _turnId) {
      _fail('foreignLiveTurn', 'expected $_turnId, observed ${usage.turnId}');
      return;
    }
    if (usage.state != ThreadRuntimeUsageState.live) {
      // 只有真正处于 live 的观察才是 live 事实；authoritative/其他状态不能被记成
      // “同身份 live 继续”（当前生产链不发布它）。
      _fail(
        'nonLiveUsage',
        'runtime usage state is ${usage.state.name}, not live',
      );
      return;
    }
    if (usage.attemptId.isEmpty) {
      _fail(
        'missingAttemptIdentity',
        'a live observation carried no attemptId',
      );
      return;
    }
    final boundAttempt = _attemptId;
    if (boundAttempt == null) {
      _attemptId = usage.attemptId;
    } else if (boundAttempt != usage.attemptId) {
      // 换 attempt（重试）不是同一观察的继续：不能把它记成同身份终态。
      _fail('attemptChanged', '$boundAttempt -> ${usage.attemptId}');
      return;
    }
    final sequence = usage.observationSequence;
    if (_lastLiveSequence == sequence) {
      // 同一次观察被再次发布（Turn／Activity／Storage 帧）：它不是新的 live 发布。
      return;
    }
    final previousSequence = _lastLiveSequence;
    if (previousSequence != null && sequence <= previousSequence) {
      _fail(
        'liveSequenceNotIncreasing',
        '$previousSequence -> $sequence is not strictly increasing',
      );
      return;
    }
    final revision = state.revision;
    final previousRevision = _lastLiveRevision;
    if (previousRevision != null && revision <= previousRevision) {
      _fail(
        'publishRevisionNotIncreasing',
        '$previousRevision -> $revision is not strictly increasing',
      );
      return;
    }
    if (_cleared) {
      _fail(
        'liveAfterClear',
        'a live observation arrived after the clear fact',
      );
      return;
    }
    final recorded = _add(
      RuntimePublishFact(
        kind: RuntimePublishFactKind.live,
        threadId: state.threadId,
        turnId: usage.turnId,
        streamEpoch: state.streamEpoch!,
        publicationRevision: revision,
        atUnixMillis: DateTime.now().millisecondsSinceEpoch,
        attemptId: usage.attemptId,
        observationSequence: sequence,
        completionTokens: usage.completionTokens,
        decodeMillis: usage.decodeMillis,
        latestContextTokens: usage.latestContextTokens,
      ),
    );
    if (!recorded) return;
    _hasActualLive = true;
    _lastLiveSequence = sequence;
    _lastLiveRevision = revision;
  }

  /// 显式清除：只有已经观察到同一身份的真实 live 发布之后，`liveUsage == null` 才是清除。
  ///
  /// 事实里带被清除对象引用，同时独立记录当前实际发布 revision 与 stream epoch；
  /// 不声称“None 自带身份或 sequence”。
  void _observeCleared(ThreadSessionState state, ThreadWorkspace workspace) {
    final lastSequence = _lastLiveSequence;
    final lastAttempt = _attemptId;
    final lastRevision = _lastLiveRevision;
    if (!_hasActualLive ||
        lastSequence == null ||
        lastAttempt == null ||
        lastRevision == null) {
      // 还没有任何**真实** live 回调（baseline 不算）：这是执行前/执行间的普通帧，
      // 也可能只是 baseline→None；两者都不是清除事实。
      return;
    }
    if (_cleared) return;
    final revision = state.revision;
    if (revision <= lastRevision) {
      _fail(
        'clearRevisionNotAfterLive',
        '$lastRevision -> $revision does not advance the publication',
      );
      return;
    }
    final activeTurnId = workspace.activeTurn?.turnId;
    final latestTurnId = workspace.latestTurn?.turnId;
    if (activeTurnId != _turnId && latestTurnId != _turnId) {
      _fail(
        'clearWithoutTargetTurn',
        'activeTurn=$activeTurnId latestTurn=$latestTurnId no longer carry $_turnId',
      );
      return;
    }
    final recorded = _add(
      RuntimePublishFact(
        kind: RuntimePublishFactKind.cleared,
        threadId: state.threadId,
        turnId: _turnId!,
        streamEpoch: state.streamEpoch!,
        publicationRevision: revision,
        atUnixMillis: DateTime.now().millisecondsSinceEpoch,
        clearedPreviousLive: RuntimeClearedLiveReference(
          turnId: _turnId!,
          attemptId: lastAttempt,
          lastObservationSequence: lastSequence,
        ),
      ),
    );
    if (recorded) _cleared = true;
  }

  /// 记录一条事实；返回它是否真的入账（溢出即显式失败且不入账）。
  bool _add(RuntimePublishFact fact) {
    if (_phase != RuntimeEvidencePhase.recording) return false;
    if (_facts.length >= factLimit) {
      _overflowed = true;
      _fail(
        'factOverflow',
        'limit $factLimit reached; samples are never trimmed',
      );
      return false;
    }
    _facts.add(fact);
    return true;
  }

  void _fail(String code, String detail) {
    if (_phase != RuntimeEvidencePhase.recording) return;
    _error = '$code: $detail';
    _cancelOwnObservation();
    _phase = RuntimeEvidencePhase.failed;
  }

  void _cancelOwnObservation() {
    final cancel = _cancelObservation;
    _cancelObservation = null;
    if (cancel == null) return;
    try {
      cancel();
      _observerCancelled = true;
    } on Object catch (error) {
      _error ??= 'observerCancelFailed: $error';
    }
  }

  Map<String, Object?> _rejection(String command, String code, String detail) =>
      <String, Object?>{
        'ok': false,
        'cmd': command,
        'source': source,
        'phase': _phase.name,
        'error': code,
        'detail': detail,
      };
}
