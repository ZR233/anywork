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
  AcpConversationMessageItem._(this.kind, Iterable<AcpContentChunkView> chunks)
    : chunks = List.unmodifiable(chunks);
  final AcpConversationMessageKind kind;
  final List<AcpContentChunkView> chunks;
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
        AcpNewIntentView() => AcpConversationHistory.newSession,
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
  int _sendGeneration = 0;
  Object? _configOperation;
  bool _configFutureDone = false;
  bool _configEventSeen = false;
  final Set<AcpPermissionIdView> _answering = {};

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
          case AcpAcceptedFrameView(:final target, :final hasObservation):
            if (_target != null) throw StateError('Duplicate ACP Accepted');
            _target = target;
            _hasObservation = hasObservation;
            if (!hasObservation) {
              _history = AcpConversationHistory.residentWithoutObservation;
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

  void _loseObservation() {
    _disconnected = true;
    _history = AcpConversationHistory.incomplete;
    // The protocol owner cancels responders whose observation is lost.
    _permissions = const [];
  }

  void _event(AcpSessionEventView event) {
    if (event is! AcpUpdateEventView) _canMergeMessage = false;
    switch (event) {
      case AcpInitializedEventView(:final capabilities):
        _capabilities = capabilities;
      case AcpReadyEventView(:final response):
        _ready = true;
        _remoteSessionId = response.sessionId;
        _configOptions = response.configOptions;
        _modes = response.modes;
      case AcpFailedEventView(:final error):
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
          _activeRun = null;
          _sendPending = false;
          _permissions = const [];
        }
      case AcpGapEventView(:final gap):
        _observationGap = gap;
        _loseObservation();
      case AcpUpdateEventView(:final update):
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
    if (update is! AcpUserMessageChunkView &&
        update is! AcpAgentMessageChunkView &&
        update is! AcpAgentThoughtChunkView) {
      _canMergeMessage = false;
    }
    switch (update) {
      case AcpUserMessageChunkView(:final chunk):
        _message(AcpConversationMessageKind.user, chunk);
      case AcpAgentMessageChunkView(:final chunk):
        _message(AcpConversationMessageKind.assistant, chunk);
      case AcpAgentThoughtChunkView(:final chunk):
        _message(AcpConversationMessageKind.thought, chunk);
      case AcpToolCallSessionUpdateView(:final toolCall):
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

  void _message(AcpConversationMessageKind kind, AcpContentChunkView chunk) {
    final last = _content.lastOrNull;
    if (last is AcpConversationMessageItem &&
        _canMergeMessage &&
        last.kind == kind &&
        last.chunks.last.messageId == chunk.messageId) {
      _content = List.unmodifiable([
        ..._content.take(_content.length - 1),
        AcpConversationMessageItem._(kind, [...last.chunks, chunk]),
      ]);
    } else {
      _content = List.unmodifiable([
        ..._content,
        AcpConversationMessageItem._(kind, [chunk]),
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
    // A new submitted message cannot merge with a previous run's user message.
    if (content.isNotEmpty) {
      _content = List.unmodifiable([
        ..._content,
        AcpConversationMessageItem._(
          AcpConversationMessageKind.user,
          content.map((block) => AcpContentChunkView(content: block)),
        ),
      ]);
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
        _sendPending = false;
        _error = error;
        _publish();
      }
      rethrow;
    }
  }

  Future<void> configure(AcpConfigId id, AcpSessionConfigValueView value) {
    final target = _requireTarget();
    return _configure(
      () => _client.configure(
        AcpConfigureRequestView(target: target, configId: id, value: value),
      ),
    );
  }

  Future<void> setMode(AcpModeId id) {
    final target = _requireTarget();
    if (_configOptions != null) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.unsupported,
        message: 'Legacy modes are only available when configOptions is absent',
      );
    }
    return _configure(
      () => _client.setMode(AcpSetModeRequestView(target: target, modeId: id)),
    );
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
