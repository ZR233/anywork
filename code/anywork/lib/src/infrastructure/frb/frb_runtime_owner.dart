part of 'studio_api.dart';

/// Owns process initialization and exit state, not a second resource registry.
///
/// The injected startup scope retains native creation and cleanup responsibility.
final class FrbRuntimeOwner {
  FrbRuntimeOwner({required this.startupScope});

  final ClientScope startupScope;
  final startupProgress = ValueNotifier(StudioStartupPhase.loadingBridge);
  final startupRecovery = ValueNotifier<StartupRecoveryReport?>(null);

  Future<void>? _initFuture;
  Future<StudioExitReport>? _shutdownFuture;
  // 早期退出封闭的单一 one-shot 结果：首次调用锚定，重复 close / dispose / driver 复用，
  // 绝不重复并行封闭，也绝不延长单一期限。
  Future<_BeginExitOutcome>? _beginExitOutcome;
  // 早期退出封闭失败时的 memoized 原始错误与 typed issue：协调器据此复用同一 correlation，
  // 避免重复生成 / 重复记录；成功或无 owner 时均为 null。
  Object? _beginExitFailure;
  StudioShutdownIssue? _beginExitIssue;
  Future<void> Function()? _initializationOverrideForTesting;
  bool _rustInitialized = false;
  // runtime owner 是否已成功安装；无 init 的只读事实，供关闭路径在不触发初始化的
  // 前提下判定「确无 owner」还是「未决」。
  bool _runtimeReady = false;

  bool _safeToDisposeAfterShutdown = false;
  bool _closing = false;
  bool _lifecycleClosed = false;

  /// Whether a native runtime was installed, without triggering initialization.
  bool get runtimeOwnerPresent => _runtimeReady;

  /// Records the final root close result before native finalization.
  ///
  /// A timeout or failed cleanup never permits releasing the native library.
  void recordLifecycleCloseReport(CloseReport report) {
    _lifecycleClosed = report.complete;
    if (!report.complete) revokeSafeDispose();
  }

  /// Permanently rejects further runtime initialization and publication.
  void sealForShutdown() => _closing = true;
  void revokeSafeDispose() => _safeToDisposeAfterShutdown = false;

  @visibleForTesting
  void debugOverrideInitialization(
    Future<void> Function()? initialization, {
    bool runtimeOwnerPresent = false,
    bool rustInitialized = false,
  }) {
    if (_initFuture != null || _closing) {
      throw StateError('Initialization override must precede runtime use');
    }
    _initializationOverrideForTesting = initialization;
    _runtimeReady = runtimeOwnerPresent;
    _rustInitialized = rustInitialized;
  }

  /// Allows a failed initialization to run again without reopening exit admission.
  void retryInitialization() {
    // 退出闩不因启动重试复位；进入退出后不再重新初始化。
    if (_closing) return;
    if (startupProgress.value == StudioStartupPhase.failed) {
      _initFuture = null;
    }
  }

  /// Joins the instance's initialization attempt or starts its first side effect.
  ///
  /// Completion and failures are cached until [retryInitialization]. Calls made
  /// after [sealForShutdown] fail without loading or starting the native runtime.
  Future<void> ensureReady() {
    if (_closing) {
      return Future<void>.error(
        _studioFailure(StateError('Studio runtime is shutting down')),
      );
    }
    final existing = _initFuture;
    if (existing != null) {
      return existing;
    }
    final completion = Completer<void>();
    _initFuture = completion.future;
    _observeBackground(completion.future);
    completion.complete(
      Future<void>.sync(() async {
        try {
          final initializationOverride = _initializationOverrideForTesting;
          if (initializationOverride != null) {
            await initializationOverride();
          } else {
            if (!_rustInitialized) {
              startupProgress.value = StudioStartupPhase.loadingBridge;
              final bridgeWatch = Stopwatch()..start();
              // Native startup owns the lease in this exact packaged library.
              // FRB's default search can select a development library from CWD or
              // environment, which would have a different set of Rust statics.
              final executable = File(Platform.resolvedExecutable);
              final bundle = Platform.isLinux || Platform.isMacOS
                  ? File(executable.resolveSymbolicLinksSync()).parent
                  : executable.parent;
              final libraryPath = bundle.uri
                  .resolve(
                    Platform.isWindows
                        ? 'pl_studio_bridge.dll'
                        : Platform.isMacOS
                        ? '../Frameworks/libpl_studio_bridge.dylib'
                        : 'lib/libpl_studio_bridge.so',
                  )
                  .toFilePath();
              await RustLib.init(
                // FRB exposes custom loading through its generated entrypoint.
                // ignore: invalid_use_of_internal_member
                externalLibrary: ExternalLibrary.open(libraryPath),
              );
              _rustInitialized = true;
              debugPrint(
                'startup_stage=load_bridge elapsed_ms=${bridgeWatch.elapsedMilliseconds}',
              );
            }
            // 关闭不触发初始化：RustLib.init() 完成后必须再检查单向闩，绝不再调用
            // native startStudioRuntime，也不发布 ready。
            if (_closing) return;
            await _startStudioRuntimeAttempt();
          }
        } catch (error, stackTrace) {
          _runtimeReady = false;
          // 迟到的失败：退出已开始，绝不把 UI 拉回 failed；仍以错误完成 init future，
          // 让关闭路径据此视为未决而不是「从未安装」。
          if (!_closing) {
            startupProgress.value = StudioStartupPhase.failed;
          }
          Error.throwWithStackTrace(_studioFailure(error), stackTrace);
        }
      }),
    );
    return completion.future;
  }

  Future<void> _startStudioRuntimeAttempt() async {
    final acquisition = startupScope
        .open<_FrbRawEvent<frb.BridgeStartupStage, StudioStartupPhase>>(
          'startup',
          (operation) async {
            final attempt = await frb.prepareStartupAttempt();
            if (operation.closeRequested || _closing) {
              throw const ClientResourceClosed();
            }
            final handle = await frb_startup_sub.subscribeStartupProgress(
              attempt: attempt,
            );
            // No getters, stream attachment or user callbacks before entry takeover.
            return _FrbRawEvent(
              operation.resourceId,
              handle,
              (handle) => handle.startupStream(),
              (stage) {
                if (!_closing) startupProgress.value = _startupPhase(stage);
                return null;
              },
              startupAttempt: attempt,
            );
          },
        );
    try {
      final raw = await acquisition.ready;
      raw.attach();
      if (raw.stopping || _closing) return;
      final runtime = await frb.startStudioRuntime(
        attempt: raw.startupAttempt!,
      );
      if (_closing) {
        _runtimeReady = false;
        return;
      }
      _runtimeReady = true;
      final report = runtime.startupRecovery;
      startupRecovery.value = report == null
          ? null
          : StartupRecoveryReport(
              backupPath: report.backupPath,
              reason: report.reason,
              createdAt: report.createdAt.toInt(),
            );
      startupProgress.value = StudioStartupPhase.ready;
    } finally {
      acquisition.requestClose();
    }
  }

  StudioStartupPhase _startupPhase(frb.BridgeStartupStage stage) =>
      switch (stage) {
        frb.BridgeStartupStage.preparing => StudioStartupPhase.preparing,
        frb.BridgeStartupStage.waitingForSteps =>
          StudioStartupPhase.waitingForSteps,
        frb.BridgeStartupStage.closingResources =>
          StudioStartupPhase.closingResources,
        frb.BridgeStartupStage.backingUp => StudioStartupPhase.backingUp,
        frb.BridgeStartupStage.resetting => StudioStartupPhase.resetting,
        frb.BridgeStartupStage.startingServices =>
          StudioStartupPhase.startingServices,
        frb.BridgeStartupStage.openingStorage =>
          StudioStartupPhase.openingStorage,
        frb.BridgeStartupStage.loadingConfiguration =>
          StudioStartupPhase.loadingConfiguration,
        frb.BridgeStartupStage.readingProjects =>
          StudioStartupPhase.readingProjects,
        frb.BridgeStartupStage.preparingResources =>
          StudioStartupPhase.preparingResources,
        frb.BridgeStartupStage.ready => StudioStartupPhase.ready,
        frb.BridgeStartupStage.failed => StudioStartupPhase.failed,
      };

  /// 共享同一退出 future：重复调用（重复退出请求、dispose、driver）复用同一次收束，
  /// 绝不复位或延长单一期限。[externalIssues] 是 Dart 拥有的外部 owner 在本次预算内收束
  /// 得到的 typed issue，作为关闭的最终成功前置条件随请求交给 runtime 单编排。
  Future<StudioExitReport> shutdownAndDispose({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    StudioExitIntent intent = StudioExitIntent.exit,
  }) {
    final running = _shutdownFuture;
    if (running != null) return running;
    _closing = true;
    final completion = Completer<StudioExitReport>();
    _shutdownFuture = completion.future;
    _observeBackground(completion.future.then<void>((_) {}));
    completion.complete(
      _runShutdownAndDispose(remainingMs, externalIssues, intent),
    );
    return completion.future;
  }

  Future<StudioExitReport> _runShutdownAndDispose(
    int remainingMs,
    List<StudioShutdownIssue> externalIssues,
    StudioExitIntent intent,
  ) async {
    final stopwatch = Stopwatch()..start();
    // 早期退出封闭是同一 coordinator 的第一步：直接消费者（不经 runStudioShutdown）也必须在
    // 任何后续阶段前有界封闭准入，把失败/超时保留为 external issue 继续收尾。经
    // runStudioShutdown 的路径已调用同一 one-shot，这里复用结果，绝不重复并行封闭；已由协调器
    // 并入 externalIssues 的同一 issue（同 correlation）不再重复添加。
    final beginExit = await _runBeginRuntimeExit(remainingMs);
    final beginExitIssue = beginExit.issue;
    var mergedExternalIssues = beginExitIssue == null
        ? externalIssues
        : <StudioShutdownIssue>[
            ...externalIssues,
            if (!externalIssues.any(
              (issue) => issue.correlationId == beginExitIssue.correlationId,
            ))
              beginExitIssue,
          ];
    final initialization = _initFuture;
    var initCompleted = initialization == null;
    // 初始化是否已「有结果」（成功或失败）。与 initCompleted 不同：失败完成也视为已定，
    // 据此区分「确无 owner」与「永久未决」。
    var initSettled = initialization == null;
    if (initialization != null) {
      try {
        // 等待初始化有界：初始化未在预算内完成即视为未决，不无限挂起退出。
        final available = _remainingAfter(remainingMs, stopwatch);
        final wait = available.clamp(0, 5000).toInt();
        await initialization.timeout(Duration(milliseconds: wait));
        initCompleted = true;
        initSettled = true;
      } on TimeoutException {
        initCompleted = false;
        initSettled = false;
      } on Object {
        // 初始化失败完成：若 RustLib 未装载则确无 owner；若已装载则由真实报告判定。
        initCompleted = false;
        initSettled = true;
      }
    }
    // Dart 侧外部 owner（产品/Thread 流与关机进度流）的取消已在协调器的同一预算内、于
    // 本次请求之前完成（见 runStudioShutdown / cancelDartSubscriptions），此处绝不再取消，
    // 避免两份关闭事实。即使 Dart 取消已耗尽预算，仍以 remainingMs=0 立即向已初始化的
    // runtime 广播封闭，绝不整段跳过；bridge 上限 28s、原生 hard deadline 照常。
    if (!initSettled) {
      // Initialization is an owner too. Pass its unresolved fact before native
      // finalization so an installer cannot launch before this owner confirms.
      mergedExternalIssues = [
        ...mergedExternalIssues,
        ..._unresolvedInitReport().issues,
      ];
    }
    // Root results must precede native finalization, including an omitted callback.
    if (!_lifecycleClosed) {
      mergedExternalIssues = [
        ...mergedExternalIssues,
        StudioShutdownIssue(
          stage: 'subscriptions',
          code: 'lifecycleUnresolved',
          message: 'the Dart lifecycle root has not confirmed resource cleanup',
          retryable: true,
          correlationId: newStudioCorrelationId(),
        ),
      ];
    }
    final rustBudget = _remainingAfter(remainingMs, stopwatch);
    StudioShutdownReport report;
    StudioUpdateHandoff updateHandoff = const NoStudioUpdateHandoff();
    var bridgeConsulted = false;
    if (_rustInitialized) {
      bridgeConsulted = true;
      try {
        // 用真实 Rust 报告判定是否安装 runtime，而不是本地标志；外部 issue 随请求交给
        // runtime 与 bridge 自身取消结果一并裁决 Clean/Stopped/实例锁释放。
        final exitReport = await FrbStudioTransport._bridgeCall(
          () => frb.shutdownRuntime(
            remainingMs: rustBudget,
            intent: switch (intent) {
              StudioExitIntent.exit => frb_shutdown.BridgeExitIntent.exit,
              StudioExitIntent.updateRestart =>
                frb_shutdown.BridgeExitIntent.updateRestart,
            },
            externalIssues: [
              for (final issue in mergedExternalIssues)
                _bridgeIssueFromStudio(issue),
            ],
          ),
        );
        report = _shutdownReportFromFrb(exitReport.shutdown);
        updateHandoff = switch (exitReport.updateHandoff) {
          frb_shutdown.BridgeUpdateHandoff_NotRequested() =>
            const NoStudioUpdateHandoff(),
          frb_shutdown.BridgeUpdateHandoff_Launched(:final version) =>
            LaunchedStudioUpdateHandoff(version: version),
          frb_shutdown.BridgeUpdateHandoff_Failed(:final error) =>
            FailedStudioUpdateHandoff(code: error.code, message: error.message),
        };
      } on Object catch (error, stackTrace) {
        // 同一次失败只生成一次 correlation：report issue 与同步诊断共用同一编号。
        final correlationId = _correlationOf(error);
        // 不扔掉已有阶段问题：把桥错误本身与 Dart 订阅问题一起如实上报为 Degraded。
        recordDartError(
          error,
          stackTrace,
          stage: 'shutdown',
          correlationId: correlationId,
        );
        report = StudioShutdownReport(
          outcome: StudioShutdownOutcome.degraded,
          issues: [
            StudioShutdownIssue(
              stage: 'shutdown',
              code: _codeOf(error),
              message: 'studio runtime shutdown reported an error',
              retryable: false,
              correlationId: correlationId,
            ),
          ],
          persistence: const UnknownStudioPendingPersistence(),
        );
      }
      _runtimeReady = false;
    } else if (initSettled) {
      // 初始化已定且 RustLib 未装载：确无 owner，才视为从未安装。
      report = StudioShutdownReport.notStarted;
    } else {
      // 初始化永久未决：可能仍持有 native owner，如实为 Degraded + Unknown。
      report = _unresolvedInitReport();
    }
    // 初始化永久未决时绝不允许正常退出：即使桥报告 NotStarted，也可能仍有尚未安装完成的
    // owner；只有在初始化确有结果（成功或失败完成）时，NotStarted 才能据实判定为 exit 0。
    if (!initSettled && report.allowsCleanExit) {
      report = StudioShutdownReport(
        outcome: StudioShutdownOutcome.degraded,
        issues: [...report.issues, ..._unresolvedInitReport().issues],
        persistence: const UnknownStudioPendingPersistence(),
      );
    }
    // 外部（Dart）issue 是本次关闭的最终成功前置条件：桥未咨询（无 runtime）时在此如实
    // 并入；桥已咨询时以桥的裁决为准，但绝不静默吞掉真实 issue —— 只要事后仍能可靠
    // Clean/NotStarted，就说明这些真实问题未被承认，必须本地降级。
    report = _reflectExternalIssues(
      report,
      mergedExternalIssues,
      bridgeConsulted,
    );
    // 仅 Clean/NotStarted 且初始化已完成才允许稍后安全 dispose；Degraded 或未决初始化
    // 保留 owner 与句柄至进程终止，避免与仍在写库的 writer 竞争。native 与 Dart 订阅
    // 两侧都收敛才允许 dispose；真正的 dispose 由 [finishShutdownDiagnostics] 在调用方
    // 收束/取消 shutdown-progress 订阅之后执行。
    _safeToDisposeAfterShutdown =
        _rustInitialized &&
        initCompleted &&
        report.allowsCleanExit &&
        _lifecycleClosed;
    return StudioExitReport(shutdown: report, updateHandoff: updateHandoff);
  }

  int _remainingAfter(int remainingMs, Stopwatch watch) {
    if (remainingMs <= 0) return 0;
    final left = remainingMs - watch.elapsedMilliseconds;
    return left <= 0 ? 0 : left;
  }

  /// 早期退出封闭本身的有界上限：绝不无界等待桥，也绝不延长单一 30s / 28s 期限。
  static const int _beginExitBoundMs = 2000;

  /// [StudioTransport.beginRuntimeExit] 的单一 one-shot 实现。
  ///
  /// 未加载 runtime（`RustLib.init` 未完成）时确无 owner，跳过且**不**触发初始化；库已加载
  /// 即直接调用 native `begin_runtime_exit` 封闭准入并广播一次取消（令在途 start 无法再发布
  /// runtime），**不**等待 `initFuture`。自身有界（≤2s，随剩余清理预算收紧）。失败/超时保留
  /// 原始错误、堆栈与 memoized typed issue，并记录一次脱敏诊断；调用方据此作为 external
  /// issue 继续收尾，绝不伪成功或 early return。重复调用复用同一结果，绝不重复并行封闭。
  Future<_BeginExitOutcome> _runBeginRuntimeExit(int remainingMs) {
    final existing = _beginExitOutcome;
    if (existing != null) return existing;
    final completion = Completer<_BeginExitOutcome>();
    _beginExitOutcome = completion.future;
    _observeBackground(completion.future.then<void>((_) {}));
    completion.complete(
      Future<_BeginExitOutcome>.sync(() async {
        if (!_rustInitialized) {
          // RustLib 未加载：确无 runtime owner 可封闭。迟到初始化 / start 由单向闩拒绝，
          // 这里跳过而不是触发初始化。
          return const _BeginExitOutcome.success();
        }
        final bound = remainingMs <= 0
            ? 0
            : (remainingMs > _beginExitBoundMs
                  ? _beginExitBoundMs
                  : remainingMs);
        try {
          await FrbStudioTransport._bridgeCall(
            () => frb.beginRuntimeExit(remainingMs: remainingMs),
          ).timeout(Duration(milliseconds: bound));
          return const _BeginExitOutcome.success();
        } on Object catch (error, stackTrace) {
          // 同一次失败只生成一次 correlation：memoized issue 与脱敏诊断共用同一编号。
          final correlationId = _correlationOf(error);
          final issue = StudioShutdownIssue(
            stage: 'exit-seal',
            code: _codeOf(error),
            // 固定安全文案：绝不把任意 error.toString()（可能含正文/凭据）当 wire 安全消息。
            message: 'studio runtime early exit seal did not confirm',
            retryable: false,
            correlationId: correlationId,
          );
          _beginExitFailure = error;
          _beginExitIssue = issue;
          recordDartError(
            error,
            stackTrace,
            stage: 'exit-seal',
            correlationId: correlationId,
          );
          return _BeginExitOutcome.failed(
            issue: issue,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
    return completion.future;
  }

  /// 让最终报告如实反映 Dart 外部取消 issue。
  ///
  /// 桥已被咨询（有 runtime）时，external issue 由 bridge 与自身取消结果一起裁决；只有
  /// 返回仍为可靠 `Clean`/`NotStarted`（无问题）时才说明这些真实 issue 被吞掉，必须本地
  /// 降级，绝不伪 Clean —— 正常情况下桥已并入，不会重复计数。桥未被咨询（无 runtime）时
  /// 直接并入。绝不改写 runtime 报出的待保存事实（未知保持未知）。
  static StudioShutdownReport _reflectExternalIssues(
    StudioShutdownReport report,
    List<StudioShutdownIssue> externalIssues,
    bool bridgeConsulted,
  ) {
    if (externalIssues.isEmpty) return report;
    if (bridgeConsulted && !report.allowsCleanExit) return report;
    return StudioShutdownReport(
      outcome: StudioShutdownOutcome.degraded,
      issues: [...report.issues, ...externalIssues],
      persistence: report.persistence,
    );
  }

  /// 领域 issue 到 bridge wire 的一次穷尽映射；只传允许的诊断字段，绝不携带正文/凭据。
  static frb_shutdown.BridgeShutdownIssue _bridgeIssueFromStudio(
    StudioShutdownIssue issue,
  ) {
    return frb_shutdown.BridgeShutdownIssue(
      stage: issue.stage,
      code: issue.code,
      message: issue.message,
      retryable: issue.retryable,
      correlationId: issue.correlationId,
    );
  }

  static String _correlationOf(Object error) =>
      error is StudioFailure && error.correlationId.isNotEmpty
      ? error.correlationId
      : newStudioCorrelationId();

  static String _codeOf(Object error) => switch (error) {
    StudioFailure(:final code) => code.name,
    TimeoutException() => 'timeout',
    _ => 'unexpected',
  };

  /// 初始化永久未决时的报告：不伪「从未安装」，待保存事实未知。correlation 非空，
  /// 便于与同步日志/桥诊断关联。
  static StudioShutdownReport _unresolvedInitReport() => StudioShutdownReport(
    outcome: StudioShutdownOutcome.degraded,
    issues: [
      StudioShutdownIssue(
        stage: 'initialize',
        code: 'initUnresolved',
        message: 'studio runtime initialization did not complete',
        retryable: false,
        correlationId: newStudioCorrelationId(),
      ),
    ],
    persistence: const UnknownStudioPendingPersistence(),
  );

  /// 独立诊断收尾：即使 runtime 从未安装或安装失败，也回收诊断资源。
  ///
  /// 调用方必须先收束/取消所有 Dart 订阅，之后这里才在必要时真正 `RustLib.dispose()`：
  /// dispose 早于订阅取消正是桥在退出时挂起的点。
  Future<void> finishShutdownDiagnostics() async {
    if (_rustInitialized) {
      try {
        await FrbStudioTransport._bridgeCall(frb.finishShutdownDiagnostics);
      } on Object catch (error, stackTrace) {
        // 诊断收尾失败不阻断退出；真实原因由报告与同步日志承载。
        recordDartError(
          error,
          stackTrace,
          stage: 'diagnostics',
          correlationId: _correlationOf(error),
        );
      }
    }
    // 只有 native 与 Dart 两侧订阅全部收束后才真正 dispose；否则保留 owner，绝不在
    // 仍有 bridge 回调时释放，也绝不把正常关闭拖成 watchdog 的 degraded。
    if (_rustInitialized && _safeToDisposeAfterShutdown && _lifecycleClosed) {
      RustLib.dispose();
      _rustInitialized = false;
      _initFuture = null;
    }
    _safeToDisposeAfterShutdown = false;
  }
}
