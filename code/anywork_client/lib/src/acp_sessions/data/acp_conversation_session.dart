part of 'acp_session_client.dart';

enum AcpConversationHistory {
  newSession,
  loadReplay,
  resumedWithoutHistory,
  residentWithoutObservation,
  incomplete,
}

enum AcpConversationMessageKind { user, assistant, thought }

sealed class AcpConversationContentItem {
  const AcpConversationContentItem();
}

/// Consecutive chunks retain their original blocks, IDs and metadata.
final class AcpConversationMessageItem extends AcpConversationContentItem {
  AcpConversationMessageItem._(
    this.kind,
    Iterable<AcpContentChunkView> chunks, {
    Iterable<AcpContentBlockView>? submittedContent,
  }) : chunks = List.unmodifiable(chunks),
       submittedContent = submittedContent == null
           ? null
           : List.unmodifiable(submittedContent);
  final AcpConversationMessageKind kind;

  /// Original peer chunks, including any context added outside the Client.
  final List<AcpContentChunkView> chunks;

  /// This owner's original submission, retained across its formal echo.
  /// Absent for replay or independently received messages; never persisted.
  final List<AcpContentBlockView>? submittedContent;
}

/// A partial tool update never invents missing title, kind or status values.
final class AcpConversationToolItem extends AcpConversationContentItem {
  const AcpConversationToolItem._(this.toolCallId, this.fields, this.meta);
  final AcpToolCallId toolCallId;
  final AcpToolCallUpdateFieldsView fields;
  final AcpJsonObject? meta;
}

/// Other formal updates remain visible without coercion into message text.
final class AcpConversationUpdateItem extends AcpConversationContentItem {
  const AcpConversationUpdateItem._(this.update);
  final AcpSessionUpdateView update;
}

/// Latest complete usage report accepted by this owner, without protocol metadata.
typedef AcpConversationUsage = ({
  BigInt used,
  BigInt size,
  ({double amount, String currency})? cost,
});

final class AcpConversationState {
  const AcpConversationState._({
    this.target,
    this.capabilities,
    this.remoteSessionId,
    this.ready = false,
    this.openPending = true,
    this.configPending = false,
    this.sendPending = false,
    this.activeRun,
    this.lastCompleted,
    this.error,
    this.configError,
    this.observationGap,
    this.observationEnded = false,
    this.disconnected = false,
    this.hasObservation,
    required this.history,
    this.content = const [],
    this.configOptions,
    this.modes,
    this.plan,
    this.latestUsage,
    this.previousContextUsed,
    this.latestCost,
    this.textPerformance,
    this.metricsLive = false,
    this.serverInfo,
    this.snapshotConfig = const [],
    this.lastStopReasonRaw,
    this.completedTurns,
    this.snapshotUpdatedAt,
    this.usageUpdatedAt,
    this.costUpdatedAt,
    this.textPerformanceUpdatedAt,
    this.pendingPermissions = const [],
  });

  final AcpSessionTargetView? target;
  final AcpAgentCapabilitiesView? capabilities;
  final AcpRemoteSessionId? remoteSessionId;
  final bool ready;
  final bool openPending;
  final bool configPending;
  final bool sendPending;
  final AcpRunIdView? activeRun;
  final AcpCompletedRunView? lastCompleted;
  final Object? error;
  final Object? configError;
  final AcpObservationGapView? observationGap;
  final bool observationEnded;
  final bool disconnected;
  final bool? hasObservation;
  final AcpConversationHistory history;
  final List<AcpConversationContentItem> content;
  final List<AcpSessionConfigOptionView>? configOptions;
  final AcpSessionModeStateView? modes;
  final AcpPlanView? plan;
  final AcpConversationUsage? latestUsage;
  final BigInt? previousContextUsed;
  final ({double amount, String currency})? latestCost;
  final AcpTextPerformanceView? textPerformance;
  final bool metricsLive;
  final AcpServerInfoView? serverInfo;
  final List<AcpConfigItemSnapshotView> snapshotConfig;
  final String? lastStopReasonRaw;
  final int? completedTurns;
  final DateTime? snapshotUpdatedAt;
  final DateTime? usageUpdatedAt;
  final DateTime? costUpdatedAt;
  final DateTime? textPerformanceUpdatedAt;
  final List<AcpPermissionEventView> pendingPermissions;

  bool get usesLegacyModes => configOptions == null && modes != null;
}

/// Client-owned, temporary ACP display state for one original product target.
///
/// Page observers borrow [source]; cancelling a watch cannot release the source,
/// cancel a prompt, close membership or stop replay. No history is persisted.
final class AcpConversationSession {
  AcpConversationSession._(
    this._client,
    this._observation,
    AcpOpenIntentView intent,
  ) : _history = switch (intent) {
        AcpNewIntentView() ||
        AcpDraftIntentView() => AcpConversationHistory.newSession,
        AcpLoadIntentView() => AcpConversationHistory.loadReplay,
        AcpResumeIntentView() => AcpConversationHistory.resumedWithoutHistory,
      } {
    _publish();
  }

  final AcpSessionClient _client;
  final AcpSessionObservation _observation;
  final Completer<void> _accepted = Completer<void>();
  late final LatestValue<AcpConversationState> _source = LatestValue(
    _snapshot(),
  );
  Future<void>? _pump;
  bool _disposing = false;
  bool _released = false;
  bool _canMergeMessage = false;
  AcpConversationMessageItem? _pendingUserEcho;
  int _sendGeneration = 0;
  Object? _configOperation;
  bool _configFutureDone = false;
  bool _configEventSeen = false;
  final Set<AcpPermissionIdView> _answering = {};
  final Map<AcpConfigId, AcpSessionConfigValueView> _configIntents = {};
  AcpModeId? _modeIntent;

  /// Explicit successful user selections, independent of server-owned current state.
  Map<AcpConfigId, AcpSessionConfigValueView> get configIntents =>
      Map.unmodifiable(_configIntents);
  AcpModeId? get modeIntent => _modeIntent;

  AcpSessionTargetView? _target;
  AcpAgentCapabilitiesView? _capabilities;
  AcpRemoteSessionId? _remoteSessionId;
  bool _ready = false;
  bool _openPending = true;
  bool _configPending = false;
  bool _sendPending = false;
  AcpRunIdView? _activeRun;
  AcpCompletedRunView? _lastCompleted;
  Object? _error;
  Object? _configError;
  AcpObservationGapView? _observationGap;
  bool _observationEnded = false;
  bool _disconnected = false;
  bool? _hasObservation;
  AcpConversationHistory _history;
  List<AcpConversationContentItem> _content = const [];
  List<AcpSessionConfigOptionView>? _configOptions;
  AcpSessionModeStateView? _modes;
  AcpPlanView? _plan;
  AcpConversationUsage? _latestUsage;
  BigInt? _previousContextUsed;
  ({double amount, String currency})? _latestCost;
  AcpTextPerformanceView? _textPerformance;
  bool _metricsLive = false;
  AcpServerInfoView? _serverInfo;
  List<AcpConfigItemSnapshotView> _snapshotConfig = const [];
  String? _lastStopReasonRaw;
  int? _completedTurns;
  DateTime? _snapshotUpdatedAt;
  DateTime? _usageUpdatedAt;
  DateTime? _costUpdatedAt;
  DateTime? _textPerformanceUpdatedAt;
  List<AcpPermissionEventView> _permissions = const [];

  AcpConversationState get state => _source.value;
  ValueObservation<AcpConversationState> get source => _source;

  AcpConversationState _snapshot() => AcpConversationState._(
    target: _target,
    capabilities: _capabilities,
    remoteSessionId: _remoteSessionId,
    ready: _ready,
    openPending: _openPending,
    configPending: _configPending,
    sendPending: _sendPending,
    activeRun: _activeRun,
    lastCompleted: _lastCompleted,
    error: _error,
    configError: _configError,
    observationGap: _observationGap,
    observationEnded: _observationEnded,
    disconnected: _disconnected,
    hasObservation: _hasObservation,
    history: _history,
    content: _content,
    configOptions: _configOptions,
    modes: _modes,
    plan: _plan,
    latestUsage: _latestUsage,
    previousContextUsed: _previousContextUsed,
    latestCost: _latestCost,
    textPerformance: _textPerformance,
    metricsLive: _metricsLive,
    serverInfo: _serverInfo,
    snapshotConfig: _snapshotConfig,
    lastStopReasonRaw: _lastStopReasonRaw,
    completedTurns: _completedTurns,
    snapshotUpdatedAt: _snapshotUpdatedAt,
    usageUpdatedAt: _usageUpdatedAt,
    costUpdatedAt: _costUpdatedAt,
    textPerformanceUpdatedAt: _textPerformanceUpdatedAt,
    pendingPermissions: _permissions,
  );

  void _publish() {
    if (!_released) _source.publish(_snapshot());
  }

  Future<void> _start() {
    _pump = _consume();
    return _accepted.future;
  }

  Future<void> _consume() async {
    try {
      while (!_disposing) {
        final frame = await _observation.next();
        if (_disposing) break;
        if (frame == null) {
          _observationEnded = true;
          if (_hasObservation != false) _loseObservation();
          if (!_accepted.isCompleted) {
            throw StateError('ACP open ended before Accepted');
          }
          _publish();
          break;
        }
        switch (frame) {
          case AcpAcceptedFrameView(
            :final target,
            :final hasObservation,
            :final infoSnapshot,
          ):
            if (_target != null) throw StateError('Duplicate ACP Accepted');
            _target = target;
            _hasObservation = hasObservation;
            if (!hasObservation) {
              _history = AcpConversationHistory.residentWithoutObservation;
            }
            if (infoSnapshot != null) {
              _applyInfoSnapshot(infoSnapshot);
            }
            _accepted.complete();
          case AcpSettledFrameView(:final result):
            _openPending = false;
            if (result case AcpFailureView(:final error)) _error = error;
          case AcpEventFrameView(:final event):
            _event(event);
        }
        _publish();
      }
    } catch (error, stack) {
      if (!_disposing) {
        _error = error;
        _observationEnded = true;
        _loseObservation();
        _publish();
      }
      if (!_accepted.isCompleted) _accepted.completeError(error, stack);
    } finally {
      if (!_accepted.isCompleted) {
        _accepted.completeError(const AcpObservationDisposed());
      }
    }
  }

  void _applyInfoSnapshot(AcpSessionInfoSnapshotView snapshot) {
    if (snapshot.cost case final cost?) {
      _latestCost = (amount: cost.amount, currency: cost.currency);
      if (cost.updatedAt > 0) {
        _costUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
          cost.updatedAt * 1000,
          isUtc: true,
        );
      }
    }
    if (snapshot.usage case final usage?) {
      _latestUsage = (used: usage.used, size: usage.size, cost: _latestCost);
      if (usage.updatedAt > 0) {
        _usageUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
          usage.updatedAt * 1000,
          isUtc: true,
        );
      }
    }
    if (snapshot.textPerformance case final perf?) {
      _textPerformance = (
        estimatedOutputTokens: perf.estimatedOutputTokens,
        responseMillis: perf.responseMillis,
      );
      if (perf.updatedAt > 0) {
        _textPerformanceUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
          perf.updatedAt * 1000,
          isUtc: true,
        );
      }
    }
    if (snapshot.serverInfo case final info?) {
      _serverInfo = info;
    }
    if (snapshot.activeConfig.isNotEmpty) {
      _snapshotConfig = List.unmodifiable(snapshot.activeConfig);
    }
    if (snapshot.lastStopReason case final reason?) {
      _lastStopReasonRaw = reason;
    }
    if (snapshot.completedTurns case final turns?) {
      _completedTurns = turns;
    }
    if (snapshot.updatedAt > 0) {
      _snapshotUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
        snapshot.updatedAt * 1000,
        isUtc: true,
      );
    }
    _metricsLive = false;
  }

  void _loseObservation() {
    _metricsLive = false;
    _pendingUserEcho = null;
    _disconnected = true;
    _history = AcpConversationHistory.incomplete;
    // The protocol owner cancels responders whose observation is lost.
    _permissions = const [];
  }

  void _event(AcpSessionEventView event) {
    if (event is! AcpUpdateEventView) _canMergeMessage = false;
    switch (event) {
      case AcpInitializedEventView(:final capabilities, :final serverInfo):
        _capabilities = capabilities;
        if (serverInfo != null) {
          _serverInfo = serverInfo;
        }
      case AcpReadyEventView(:final response):
        _ready = true;
        _remoteSessionId = response.sessionId;
        _configOptions = response.configOptions;
        _modes = response.modes;
      case AcpFailedEventView(:final error):
        _metricsLive = false;
        _pendingUserEcho = null;
        _ready = false;
        _error = error;
      case AcpConfiguredEventView(:final response):
        _configOptions = response.configOptions;
        _configEventSeen = true;
        _settleConfig();
      case AcpModeSetEventView(:final modeId):
        _mode(modeId);
        _configEventSeen = true;
        _settleConfig();
      case AcpPermissionEventView():
        _permissions = List.unmodifiable([..._permissions, event]);
      case AcpCompletedEventView(:final completed):
        _lastCompleted = completed;
        if (_activeRun == null || _activeRun == completed.run) {
          if (completed.textPerformance case final perf?) {
            final now = DateTime.now().toUtc();
            _textPerformance = perf;
            _textPerformanceUpdatedAt = now;
            _snapshotUpdatedAt = now;
          }
          if (completed.result case AcpSuccessView<AcpPromptResponseView>(
            :final value,
          )) {
            _completedTurns = (_completedTurns ?? 0) + 1;
            _lastStopReasonRaw = value.stopReason.name;
            _snapshotUpdatedAt = DateTime.now().toUtc();
          }
          _pendingUserEcho = null;
          _activeRun = null;
          _sendPending = false;
          _permissions = const [];
        }
      case AcpGapEventView(:final gap):
        _observationGap = gap;
        _loseObservation();
      case AcpUpdateEventView(:final update, :final textPerformance):
        if (textPerformance != null) {
          final now = DateTime.now().toUtc();
          _textPerformance = textPerformance;
          _textPerformanceUpdatedAt = now;
          _metricsLive =
              !(_history == AcpConversationHistory.loadReplay && !_ready);
          _snapshotUpdatedAt = now;
        }
        _update(update.update);
    }
  }

  void _mode(AcpModeId id) {
    final modes = _modes;
    if (modes == null || modes.currentModeId == id) return;
    _modes = AcpSessionModeStateView(
      currentModeId: id,
      availableModes: modes.availableModes,
      meta: modes.meta,
    );
  }

  void _update(AcpSessionUpdateView update) {
    if (update case AcpUsageUpdateView(:final used, :final size, :final cost)) {
      final replaying =
          _history == AcpConversationHistory.loadReplay && !_ready;
      if (!_disconnected && !_observationEnded && _hasObservation == true) {
        final now = DateTime.now().toUtc();
        if (_latestUsage case final previous? when previous.used != used) {
          _previousContextUsed = previous.used;
        }
        if (cost != null) {
          _latestCost = (amount: cost.amount, currency: cost.currency);
          _costUpdatedAt = now;
        }
        _latestUsage = (used: used, size: size, cost: _latestCost);
        _usageUpdatedAt = now;
        _metricsLive = !replaying;
        _snapshotUpdatedAt = now;
      }
    }
    if (update is! AcpUserMessageChunkView &&
        update is! AcpAgentMessageChunkView &&
        update is! AcpAgentThoughtChunkView) {
      _canMergeMessage = false;
    }
    switch (update) {
      case AcpUserMessageChunkView(:final chunk):
        final provisional = _pendingUserEcho;
        if (provisional != null) {
          // Formal user content replaces this prompt's temporary display, not
          // another turn or load replay. Do not deduplicate by text.
          _pendingUserEcho = null;
          _content = List.unmodifiable(
            _content.where((item) => !identical(item, provisional)),
          );
          _canMergeMessage = false;
        }
        _message(
          AcpConversationMessageKind.user,
          chunk,
          submittedContent: provisional?.submittedContent,
        );
      case AcpAgentMessageChunkView(:final chunk):
        _pendingUserEcho = null;
        _message(AcpConversationMessageKind.assistant, chunk);
      case AcpAgentThoughtChunkView(:final chunk):
        _pendingUserEcho = null;
        _message(AcpConversationMessageKind.thought, chunk);
      case AcpToolCallSessionUpdateView(:final toolCall):
        _pendingUserEcho = null;
        _tool(
          toolCall.toolCallId,
          AcpToolCallUpdateFieldsView(
            title: toolCall.title,
            name: toolCall.name,
            kind: toolCall.kind,
            status: toolCall.status,
            content: toolCall.content,
            locations: toolCall.locations,
            rawInput: toolCall.rawInput,
            rawOutput: toolCall.rawOutput,
          ),
          toolCall.meta,
          replace: true,
        );
      case AcpToolCallChangedView(:final toolCall):
        _pendingUserEcho = null;
        _tool(toolCall.toolCallId, toolCall.fields, toolCall.meta);
      case AcpPlanView():
        _plan = update;
      case AcpConfigOptionsUpdateView(:final configOptions):
        _configOptions = configOptions;
      case AcpCurrentModeUpdateView(:final currentModeId):
        _mode(currentModeId);
      case AcpAvailableCommandsUpdateView() ||
          AcpSessionInfoUpdateView() ||
          AcpUsageUpdateView() ||
          AcpNoticeView() ||
          AcpCompactionUpdateView() ||
          AcpCompactionSummaryChunkView():
        _content = List.unmodifiable([
          ..._content,
          AcpConversationUpdateItem._(update),
        ]);
    }
  }

  void _message(
    AcpConversationMessageKind kind,
    AcpContentChunkView chunk, {
    List<AcpContentBlockView>? submittedContent,
  }) {
    final last = _content.lastOrNull;
    if (last is AcpConversationMessageItem &&
        _canMergeMessage &&
        last.kind == kind &&
        last.chunks.last.messageId == chunk.messageId) {
      _content = List.unmodifiable([
        ..._content.take(_content.length - 1),
        AcpConversationMessageItem._(kind, [
          ...last.chunks,
          chunk,
        ], submittedContent: last.submittedContent),
      ]);
    } else {
      _content = List.unmodifiable([
        ..._content,
        AcpConversationMessageItem._(kind, [
          chunk,
        ], submittedContent: submittedContent),
      ]);
    }
    _canMergeMessage = true;
  }

  void _tool(
    AcpToolCallId id,
    AcpToolCallUpdateFieldsView fields,
    AcpJsonObject? meta, {
    bool replace = false,
  }) {
    final index = _content.indexWhere(
      (item) => item is AcpConversationToolItem && item.toolCallId == id,
    );
    final previous = index < 0
        ? null
        : _content[index] as AcpConversationToolItem;
    final old = replace ? null : previous?.fields;
    final item = AcpConversationToolItem._(
      id,
      AcpToolCallUpdateFieldsView(
        title: fields.title ?? old?.title,
        name: fields.name ?? old?.name,
        kind: fields.kind ?? old?.kind,
        status: fields.status ?? old?.status,
        content: fields.content ?? old?.content,
        locations: fields.locations ?? old?.locations,
        rawInput: fields.rawInput ?? old?.rawInput,
        rawOutput: fields.rawOutput ?? old?.rawOutput,
      ),
      replace ? meta : meta ?? previous?.meta,
    );
    final next = _content.toList();
    if (index < 0) {
      next.add(item);
    } else {
      next[index] = item;
    }
    _content = List.unmodifiable(next);
  }

  AcpSessionTargetView _requireTarget({bool ready = true}) {
    _client._requireOpen();
    if (_disposing || _released) throw const AcpObservationDisposed();
    final target = _target;
    if (target == null ||
        (ready && (!_ready || _openPending || _disconnected))) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.notReady,
        message: 'ACP conversation is not ready for this action',
      );
    }
    return target;
  }

  Future<AcpRunIdView> send(List<AcpContentBlockView> content) async {
    final target = _requireTarget();
    if (_configPending ||
        _configError != null ||
        _sendPending ||
        _activeRun != null) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.busy,
        message: 'Resolve pending configuration or the current prompt first',
      );
    }
    final capabilities = _capabilities;
    for (final block in content) {
      final supported = switch (block) {
        AcpTextContentView() || AcpResourceLinkView() => true,
        AcpImageContentView() => capabilities?.image == true,
        AcpAudioContentView() => capabilities?.audio == true,
        AcpEmbeddedResourceView() => capabilities?.embeddedContext == true,
      };
      if (!supported) {
        throw AcpBusinessFailureView(
          kind: AcpBusinessFailureKindView.unsupported,
          message: 'The agent has not declared support for this content',
        );
      }
    }
    final generation = ++_sendGeneration;
    _sendPending = true;
    _canMergeMessage = false;
    _pendingUserEcho = null;
    // A new submitted message cannot merge with a previous run's user message.
    if (content.isNotEmpty) {
      final provisional = AcpConversationMessageItem._(
        AcpConversationMessageKind.user,
        content.map((block) => AcpContentChunkView(content: block)),
        submittedContent: content,
      );
      _pendingUserEcho = provisional;
      _content = List.unmodifiable([..._content, provisional]);
    }
    _publish();
    try {
      final run = await _client.prompt(
        AcpPromptRequestView(target: target, content: content),
      );
      if (!_disposing && generation == _sendGeneration) {
        _sendPending = false;
        if (_lastCompleted?.run != run) _activeRun = run;
        _publish();
      }
      return run;
    } catch (error) {
      if (!_disposing && generation == _sendGeneration) {
        _pendingUserEcho = null;
        _sendPending = false;
        _error = error;
        _publish();
      }
      rethrow;
    }
  }

  Future<void> configure(
    AcpConfigId id,
    AcpSessionConfigValueView value,
  ) async {
    final target = _requireTarget();
    await _configure(
      () => _client.configure(
        AcpConfigureRequestView(target: target, configId: id, value: value),
      ),
    );
    _configIntents[id] = value;
  }

  Future<void> setMode(AcpModeId id) async {
    final target = _requireTarget();
    if (_configOptions != null) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.unsupported,
        message: 'Legacy modes are only available when configOptions is absent',
      );
    }
    await _configure(
      () => _client.setMode(AcpSetModeRequestView(target: target, modeId: id)),
    );
    _modeIntent = id;
  }

  Future<void> _configure(Future<void> Function() command) async {
    if (_configPending) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.busy,
        message: 'An ACP configuration change is already pending',
      );
    }
    final operation = Object();
    _configOperation = operation;
    _configFutureDone = false;
    _configEventSeen = false;
    _configPending = true;
    _publish();
    try {
      await command();
      if (_disposing || !identical(operation, _configOperation)) return;
      _configFutureDone = true;
      _settleConfig();
      _publish();
    } catch (error) {
      if (!_disposing && identical(operation, _configOperation)) {
        _configPending = false;
        _configOperation = null;
        _configError = error;
        _error = error;
        _publish();
      }
      rethrow;
    }
  }

  void _settleConfig() {
    if (_configOperation == null || !_configFutureDone || !_configEventSeen)
      return;
    _configPending = false;
    _configOperation = null;
    if (identical(_error, _configError)) _error = null;
    _configError = null;
  }

  /// Explicitly acknowledges a displayed error; this never retries a command.
  void dismissError() {
    _requireTarget(ready: false);
    _error = null;
    _configError = null;
    _publish();
  }

  /// A null option is the existing formal boundary's Cancelled response.
  Future<void> answerPermission(
    AcpPermissionIdView id,
    AcpPermissionOptionId? optionId,
  ) async {
    final target = _requireTarget();
    final permission = _permissions.where((p) => p.id == id).firstOrNull;
    if (permission == null) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.stale,
        message: 'The ACP permission is no longer pending',
      );
    }
    if (optionId != null &&
        !permission.request.options.any((o) => o.optionId == optionId)) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.invalidOption,
        message: 'The ACP permission option was not offered',
      );
    }
    if (!_answering.add(id)) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.busy,
        message: 'The ACP permission answer is already pending',
      );
    }
    try {
      await _client.answerPermission(
        AcpPermissionAnswerRequestView(
          target: target,
          permissionId: id,
          optionId: optionId,
        ),
      );
      if (!_disposing && _permissions.any((p) => identical(p, permission))) {
        _permissions = List.unmodifiable(
          _permissions.where((p) => !identical(p, permission)),
        );
        _publish();
      }
    } catch (error) {
      if (!_disposing) {
        _error = error;
        _publish();
      }
      rethrow;
    } finally {
      _answering.remove(id);
    }
  }

  Future<void> interrupt() async {
    final target = _requireTarget();
    final run = _activeRun;
    final generation = _sendGeneration;
    if (run == null) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.notReady,
        message: 'No qualified ACP run is available to interrupt',
      );
    }
    await _client.interrupt(AcpInterruptRequestView(target: target, run: run));
    if (!_disposing &&
        generation == _sendGeneration &&
        (_activeRun == run || _lastCompleted?.run == run)) {
      _permissions = const [];
      _publish();
    }
  }

  Future<AcpBusinessCloseView> closeMember() async {
    final target = _requireTarget(ready: false);
    final result = await _client.closeMember(target);
    if (!_disposing && result.localComplete) {
      _ready = false;
      _metricsLive = false;
      _permissions = const [];
      _publish();
    }
    return result;
  }

  Future<void> _dispose() async {
    _disposing = true;
    await _observation.close();
    await _pump;
    if (!_released) {
      _released = true;
      _source.close();
    }
  }
}
