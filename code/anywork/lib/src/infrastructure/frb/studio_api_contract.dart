part of 'studio_api.dart';

frb_attachment_types.BridgeStudioPromptInput _bridgePromptInput(
  StudioPromptInput input,
) {
  return frb_attachment_types.BridgeStudioPromptInput(
    inputId: input.inputId,
    text: input.text,
    attachmentDraftIds: input.attachmentDraftIds,
  );
}

AttachmentDraftView _attachmentDraftFromFrb(
  frb_attachment_types.BridgeAttachmentDraft value,
) {
  return AttachmentDraftView(
    id: value.draftId,
    modality: switch (value.modality) {
      frb_attachment_types.BridgeAttachmentModality.image =>
        AttachmentModalityView.image,
      frb_attachment_types.BridgeAttachmentModality.video =>
        AttachmentModalityView.video,
      frb_attachment_types.BridgeAttachmentModality.file =>
        AttachmentModalityView.file,
    },
    mediaType: value.mediaType,
    filename: value.filename,
    byteSize: value.byteSize.toInt(),
    width: value.width,
    height: value.height,
  );
}

void _observeBackground(Future<void> future) {
  unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
}

/// Adapter-owned layers only. ClientScope owns opening, close attempts and retry.
abstract class _FrbRawResource implements ClientResource {
  _FrbRawResource(this.resourceId);
  @override
  final ClientResourceId resourceId;
  bool stopping = false;
  bool _nativeAcknowledged = false;
  bool _nativeDisposed = false;

  void requestNativeClose();
  Future<void> cancelNative();
  void disposeNative();
  void stopDelivery() {}
  Future<void> closeChildren() async {}
  Future<void> closeDart() async {}

  @override
  void requestClose() {
    if (stopping) return;
    stopping = true;
    stopDelivery();
    requestNativeClose();
  }

  Future<void> _joinNative() async {
    if (_nativeAcknowledged) return;
    await cancelNative();
    _nativeAcknowledged = true;
  }

  @override
  Future<void> close() async {
    requestClose();
    // Start every independent child before joining; a failure cannot skip siblings.
    await Future.wait<void>([_joinNative(), Future<void>.sync(closeChildren)]);
    if (!_nativeDisposed) {
      disposeNative();
      _nativeDisposed = true;
    }
    // Never cancel the original Dart subscription before real native ACK/dispose.
    await closeDart();
  }

  @override
  Future<void> retryClose() => close();
}

/// A public port references an entry; it is never that entry's actual resource.
abstract class _FrbPortProxy<R extends _FrbRawResource>
    implements ClientResource {
  _FrbPortProxy(this._entry, this._raw);
  final ClientAcquisition<R> _entry;
  final R _raw;
  @override
  ClientResourceId get resourceId => _entry.resourceId;
  @override
  void requestClose() => _entry.requestClose();
  @override
  Future<void> close() => _entry.close();
  @override
  Future<void> retryClose() => _entry.retryClose();
}

/// Retains a raw pull handle and the existing single-next protocol guard.
final class _FrbRawPull<H, T> extends _FrbRawResource {
  _FrbRawPull(
    super.resourceId,
    H handle,
    this._nextFrame,
    this._request,
    this._cancel,
    this._dispose,
  ) : _handle = handle;
  H? _handle;
  H get handle => _handle as H;
  final Future<T?> Function(H) _nextFrame;
  final void Function(H) _request;
  final Future<void> Function(H) _cancel;
  final void Function(H) _dispose;
  Future<T?>? _reading;

  Future<T?> next() {
    if (stopping) return Future.value(null);
    if (_reading != null) {
      return Future.error(StateError('Observation next is already in flight'));
    }
    final work = FrbStudioTransport._bridgeCall(() => _nextFrame(handle));
    _reading = work;
    unawaited(
      work.then<void>(
        (_) {
          if (identical(_reading, work)) _reading = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_reading, work)) _reading = null;
        },
      ),
    );
    return work;
  }

  @override
  void requestNativeClose() => _request(handle);
  @override
  Future<void> cancelNative() =>
      FrbStudioTransport._bridgeCall(() => _cancel(handle));
  @override
  void disposeNative() {
    _dispose(handle);
    _handle = null;
  }

  @override
  Future<void> closeDart() async {
    final pending = _reading;
    if (pending != null) {
      await pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    }
  }
}

/// Raw subscription, native ACK and Dart listener are kept in this one entry.
final class _FrbRawEvent<E, T> extends _FrbRawResource {
  _FrbRawEvent(
    super.resourceId,
    frb.BridgeEventSubscription handle,
    this._stream,
    this._convert, {
    this.startupAttempt,
    this.isTerminal,
  }) : _handle = handle;
  frb.BridgeEventSubscription? _handle;
  frb.BridgeEventSubscription get handle => _handle!;
  final Stream<E> Function(frb.BridgeEventSubscription) _stream;
  final T? Function(E) _convert;
  final BigInt? startupAttempt;
  final bool Function(E)? isTerminal;
  final output = StreamController<T>();
  StreamSubscription<E>? _subscription;

  Stream<T> get frames => output.stream;
  void attach({void Function()? onFailure}) {
    if (stopping) return;
    _subscription = _stream(handle).listen(
      (event) {
        if (stopping || output.isClosed) return;
        try {
          if (isTerminal?.call(event) ?? false) {
            _observeBackground(output.close());
            return;
          }
          final frame = _convert(event);
          if (frame != null && !stopping && !output.isClosed) output.add(frame);
        } catch (error, stack) {
          if (!output.isClosed) output.addError(_studioFailure(error), stack);
          onFailure?.call();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!stopping && !output.isClosed) {
          output.addError(_studioFailure(error), stack);
        }
      },
      onDone: () => _observeBackground(output.close()),
    );
  }

  @override
  void stopDelivery() => _observeBackground(output.close());
  @override
  void requestNativeClose() {} // This endpoint has asynchronous cancel only.
  @override
  Future<void> cancelNative() => handle.cancel();
  @override
  void disposeNative() {
    handle.dispose();
    _handle = null;
  }

  @override
  Future<void> closeDart() async {
    final subscription = _subscription;
    if (subscription != null) {
      await subscription.cancel();
      _subscription = null;
    }
  }
}

final class _FrbProductTopicObservation
    extends
        _FrbPortProxy<
          _FrbRawEvent<
            frb_topic_types.BridgeProductTopicStreamEnvelope,
            ProductTopicFrame
          >
        >
    implements ProductTopicObservation {
  _FrbProductTopicObservation(super.entry, super.raw);
  @override
  Stream<ProductTopicFrame> get frames => _raw.frames;
}

Future<T> _publishRaw<R extends _FrbRawResource, T>(
  ClientAcquisition<R> entry,
  T Function(R) publish,
) async {
  try {
    final raw = await entry.ready;
    if (raw.stopping) throw const ClientResourceClosed();
    return publish(raw);
  } catch (error, stack) {
    entry.requestClose();
    if (error is ClientResourceClosed) Error.throwWithStackTrace(error, stack);
    Error.throwWithStackTrace(_studioFailure(error), stack);
  }
}

/// 一次早期退出封闭（[StudioTransport.beginRuntimeExit]）的单一 one-shot 结果。
///
/// 成功或「无 owner 跳过」时无 issue；失败/超时保留 typed issue、原始错误与堆栈，供调用方
/// 作为 external issue 继续收尾。同一进程只结算一次：重复 close / dispose / driver 复用同一
/// 结果，绝不重复并行封闭，也绝不延长单一期限。
class _BeginExitOutcome {
  const _BeginExitOutcome.success()
    : issue = null,
      error = null,
      stackTrace = null;

  const _BeginExitOutcome.failed({
    required StudioShutdownIssue this.issue,
    required Object this.error,
    required StackTrace this.stackTrace,
  });

  final StudioShutdownIssue? issue;
  final Object? error;
  final StackTrace? stackTrace;
}

frb.AccountModelInput _manualModelInput(AccountModelCommand model) =>
    frb.AccountModelInput(
      modelId: model.modelId,
      displayName: model.displayName,
      wireApi: model.wireApi,
      contextWindow: model.contextWindow == null
          ? null
          : BigInt.from(model.contextWindow!),
      maxOutputTokens: model.maxOutputTokens == null
          ? null
          : BigInt.from(model.maxOutputTokens!),
    );
frb.AccountSecretInput _secretInput(AccountSecretCommand secret) =>
    switch (secret.action) {
      AccountSecretAction.preserve => const frb.AccountSecretInput.preserve(),
      AccountSecretAction.clear => const frb.AccountSecretInput.clear(),
      AccountSecretAction.replace => frb.AccountSecretInput.replace(
        value: secret.value ?? '',
      ),
    };
frb_accounts.BridgeAccountTextPatch _textPatchInput(AccountTextPatch patch) =>
    switch (patch) {
      AccountTextKeep() => const frb_accounts.BridgeAccountTextPatch.keep(),
      AccountTextSet(:final value) => frb_accounts.BridgeAccountTextPatch.set_(
        value: value,
      ),
      AccountTextRestore() =>
        const frb_accounts.BridgeAccountTextPatch.restore(),
    };

final class _FrbThreadsObservation
    extends
        _FrbPortProxy<
          _FrbRawPull<
            frb_directory_feed.BridgeThreadsObservation,
            ThreadDirectoryFrame
          >
        >
    implements ThreadsObservationHandle {
  _FrbThreadsObservation(super.entry, super.raw);
  @override
  Future<ThreadDirectoryFrame?> next() => _raw.next();
}

final class _FrbThreadObservation
    extends
        _FrbPortProxy<
          _FrbRawPull<
            frb_directory_feed.BridgeThreadObservation,
            ThreadMetadataFrame
          >
        >
    implements ThreadObservationHandle {
  _FrbThreadObservation(super.entry, super.raw);
  @override
  Future<ThreadMetadataFrame?> next() => _raw.next();
}

final class _FrbAccountDomainObservation
    extends
        _FrbPortProxy<
          _FrbRawPull<
            frb_account_feed.BridgeAccountObservation,
            AccountDomainFrame
          >
        >
    implements AccountDomainObservation {
  _FrbAccountDomainObservation(super.entry, super.raw);
  @override
  Future<AccountDomainFrame?> next() => _raw.next();
}

/// Adapts native ports with independently injected content and progress owners.
class FrbStudioTransport
    implements
        StudioTransport,
        PersistenceQueueReader,
        AccountFeedPort,
        AccountConfigurationPort,
        AccountModelsPort,
        AccountUsagePort,
        AcpPort {
  FrbStudioTransport({
    required this.runtime,
    required this.contentScope,
    required this.progressScope,
  });

  final FrbRuntimeOwner runtime;
  final ClientScope contentScope;
  final ClientScope progressScope;

  @override
  Future<RecoveryStateSnapshot> retryRecovery() async {
    await _ensureReady();
    return _recoveryStateFromFrb(await _bridgeCall(frb.retryRecovery));
  }

  @override
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target, {
    required ClientResourceId resourceId,
  }) async {
    final entry = contentScope
        .open<
          _FrbRawPull<
            frb_account_feed.BridgeAccountObservation,
            AccountDomainFrame
          >
        >('account-observation', (operation) async {
          await _ensureReady();
          final handle = await _bridgeCall(
            () => frb_account_feed.openAccountObservation(
              target: _accountTargetToFrb(target),
            ),
          );
          return _FrbRawPull(
            operation.resourceId,
            handle,
            (handle) async {
              final frame = await handle.next();
              return frame == null ? null : _accountFrameFromFrb(frame);
            },
            (handle) => handle.requestClose(),
            (handle) => handle.close(),
            (handle) => handle.dispose(),
          );
        }, identity: resourceId);
    return _FrbAccountDomainObservation(entry, await entry.ready);
  }

  @override
  Future<AccountDomainFrame> readAccountDomain(
    AccountObservationTarget target,
  ) async {
    await _ensureReady();
    return _accountFrameFromFrb(
      await _bridgeCall(
        () => frb_account_feed.readAccountDomain(
          target: _accountTargetToFrb(target),
        ),
      ),
    );
  }

  @override
  Future<ChatGptLoginCommandReply> startChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    await _ensureReady();
    return _chatGptLoginCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_account_chatgpt.startChatgptLogin(
          loginId: loginId,
          editorId: editorId,
          accountId: accountId,
        ),
      ),
    );
  }

  @override
  Future<ChatGptLoginCommandReply> cancelChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) async {
    await _ensureReady();
    return _chatGptLoginCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_account_chatgpt.cancelChatgptLogin(
          loginId: loginId,
          editorId: editorId,
          accountId: accountId,
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> patchAccount(
    int revision,
    PatchAccountCommand command, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_account_commands.patchAccount(
          operationId: operationId.value,
          expectedSettingsRevision: BigInt.from(revision),
          accountId: command.identity.accountId,
          input: frb_accounts.BridgePatchAccountInput(
            authentication: _accountAuthenticationIntentToFrb(
              command.authentication,
            ),
            name: _textPatchInput(command.name),
            baseUrl: _textPatchInput(command.baseUrl),
            templateId: _textPatchInput(command.templateId),
            protocol: _textPatchInput(command.protocol),
            secret: _secretInput(command.secret),
            customModels: switch (command.customModels) {
              AccountModelsKeep() =>
                const frb_accounts.BridgeAccountModelsPatch.keep(),
              AccountModelsRestore() =>
                const frb_accounts.BridgeAccountModelsPatch.restore(),
              AccountModelsSet(:final models) =>
                frb_accounts.BridgeAccountModelsPatch.set_(
                  models: models.map(_manualModelInput).toList(),
                ),
            },
          ),
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> setAccountModelAutoCompact(
    int revision,
    AccountModelIdentity identity,
    AutoCompactIntent intent, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_account_commands.setAccountModelAutoCompact(
          operationId: operationId.value,
          expectedSettingsRevision: BigInt.from(revision),
          accountId: identity.accountId,
          modelId: identity.modelId,
          intent: switch (intent) {
            SetAutoCompactLimit(:final limit) =>
              frb_accounts.BridgeAutoCompactIntent.set_(
                limit: BigInt.from(limit),
              ),
            ClearAutoCompactLimit() =>
              const frb_accounts.BridgeAutoCompactIntent.clear(),
          },
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> setAccountModelConnection(
    int revision,
    AccountModelIdentity identity,
    ModelConnectionIntent intent, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_account_commands.setAccountModelConnection(
          operationId: operationId.value,
          expectedSettingsRevision: BigInt.from(revision),
          accountId: identity.accountId,
          modelId: identity.modelId,
          intent: switch (intent) {
            SetModelConnection(:final mode) =>
              frb_accounts.BridgeModelConnectionIntent.set_(
                mode: switch (mode) {
                  AccountConnectionMode.http =>
                    frb_accounts.BridgeAccountConnectionMode.http,
                  AccountConnectionMode.webSocket =>
                    frb_accounts.BridgeAccountConnectionMode.webSocket,
                },
              ),
            ClearModelConnection() =>
              const frb_accounts.BridgeModelConnectionIntent.clear(),
          },
        ),
      ),
    );
  }

  @override
  Future<ModelSyncAdmission> syncAccountModels(
    NativeAccountIdentity identity, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    final reply = await _bridgeCall(
      () => frb_account_commands.syncAccountModels(
        operationId: operationId.value,
        accountId: identity.accountId,
      ),
    );
    return ModelSyncAdmission(
      operationId: OperationId(reply.operationId),
      account: NativeAccountIdentity(reply.accountId),
      queryGeneration: reply.queryGeneration.toInt(),
      joinedExisting: reply.joinedExisting,
    );
  }

  @override
  Future<AccountUsageFrame> queryAccountUsage(
    NativeAccountIdentity identity,
  ) async {
    await _ensureReady();
    final frame = _accountFrameFromFrb(
      await _bridgeCall(
        () => frb_account_commands.checkAccountUsage(
          accountId: identity.accountId,
        ),
      ),
    );
    if (frame is! AccountUsageFrame) {
      throw StateError('Usage query returned another domain');
    }
    return frame;
  }

  AccountCatalogView? _accountCatalogCache;
  Future<AccountCatalogView>? _accountCatalogFuture;
  AcpAccountCatalogView? _acpCatalogCache;
  Future<AcpAccountCatalogView>? _acpCatalogFuture;

  Future<void> _ensureReady() async {
    await runtime.ensureReady();
    if (runtime._closing) throw const ClientResourceClosed();
  }

  @override
  void sealForShutdown() => runtime.sealForShutdown();

  @override
  void revokeSafeDispose() => runtime.revokeSafeDispose();

  /// Closes content and startup concurrently using the caller's shared budget.
  ///
  /// Progress remains open for its independent shutdown phase.
  @override
  Future<DartResourceCloseResult> cancelDartSubscriptions({
    required ClientCloseBudget budget,
  }) async {
    final reports = await Future.wait([
      contentScope.close(budget: budget),
      runtime.startupScope.close(budget: budget),
    ]);
    return DartResourceCloseResult(
      resources: CloseReport(
        unresolved: [for (final report in reports) ...report.unresolved],
      ),
    );
  }

  /// Joins the independent progress owner without closing content or the root.
  @override
  Future<DartResourceCloseResult> closeShutdownProgress({
    required ClientCloseBudget budget,
  }) async => DartResourceCloseResult(
    resources: await progressScope.close(budget: budget),
  );

  @override
  StudioShutdownIssue? recordedBeginExitIssue(Object error) {
    final issue = runtime._beginExitIssue;
    return issue != null && identical(error, runtime._beginExitFailure)
        ? issue
        : null;
  }

  @override
  Future<void> finishShutdownDiagnostics() =>
      runtime.finishShutdownDiagnostics();

  @override
  Future<AccountCatalogView> loadAccountCatalog() async {
    final cached = _accountCatalogCache;
    if (cached != null) return cached;
    final inFlight = _accountCatalogFuture;
    if (inFlight != null) return inFlight;
    final future = _loadAccountCatalog();
    _accountCatalogFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_accountCatalogFuture, future)) {
        _accountCatalogFuture = null;
      }
    }
  }

  Future<AccountCatalogView> _loadAccountCatalog() async {
    await _ensureReady();
    final catalog = accountCatalogFromFrb(
      await _bridgeCall(frb.loadAccountCatalog),
    );
    if (catalog.isUsable) {
      _accountCatalogCache = catalog;
    }
    return catalog;
  }

  @override
  Future<AcpAccountCatalogView> loadAcpAccountCatalog() async {
    final cached = _acpCatalogCache;
    if (cached != null) return cached;
    final inFlight = _acpCatalogFuture;
    if (inFlight != null) return inFlight;
    final future = _loadAcpAccountCatalog();
    _acpCatalogFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_acpCatalogFuture, future)) {
        _acpCatalogFuture = null;
      }
    }
  }

  Future<AcpAccountCatalogView> _loadAcpAccountCatalog() async {
    await _ensureReady();
    final catalog = _acpCatalogFromFrb(
      await _bridgeCall(frb.loadAcpAccountCatalog),
    );
    if (catalog.isUsable) {
      _acpCatalogCache = catalog;
    }
    return catalog;
  }

  @override
  Future<AcpLocalDetectionCommandReply> startAcpLocalDetection({
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _acpLocalDetectionReplyFromFrb(
      await _bridgeCall(
        () => frb.startAcpLocalDetection(operationId: operationId.value),
      ),
    );
  }

  @override
  Future<AcpLocalDetectionCommandReply> cancelAcpLocalDetection({
    required OperationId operationId,
    required OperationId targetOperationId,
  }) async {
    await _ensureReady();
    return _acpLocalDetectionReplyFromFrb(
      await _bridgeCall(
        () => frb.cancelAcpLocalDetection(
          operationId: operationId.value,
          targetOperationId: targetOperationId.value,
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> saveAcpAccount(
    AcpAccountUpdateView account, {
    required OperationId operationId,
    required BigInt? expectedDocumentRevision,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.saveAcpAccount(
          operationId: operationId.value,
          expectedDocumentRevision: expectedDocumentRevision,
          account: _acpAccountUpdateToFrb(account),
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> removeAcpAccount(
    String accountId, {
    required OperationId operationId,
    required BigInt expectedDocumentRevision,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.removeAcpAccount(
          operationId: operationId.value,
          expectedDocumentRevision: expectedDocumentRevision,
          accountId: accountId,
        ),
      ),
    );
  }

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    await _ensureReady();
    return _acpAuthReplyFromFrb(
      await _bridgeCall(
        () => frb.startAcpAuth(
          operationId: operationId.value,
          accountId: accountId,
          expectedConnectionRevision: BigInt.from(expectedConnectionRevision),
          action: _acpAuthActionToFrb(action),
        ),
      ),
    );
  }

  @override
  Future<AcpAuthCommandReply> continueAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required OperationId targetOperationId,
    required String methodId,
  }) async {
    await _ensureReady();
    return _acpAuthReplyFromFrb(
      await _bridgeCall(
        () => frb.continueAcpAuth(
          operationId: operationId.value,
          accountId: accountId,
          expectedConnectionRevision: BigInt.from(expectedConnectionRevision),
          targetOperationId: targetOperationId.value,
          methodId: methodId,
        ),
      ),
    );
  }

  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) async {
    await _ensureReady();
    return _acpAuthReplyFromFrb(
      await _bridgeCall(
        () => frb.cancelAcpAuth(
          operationId: operationId.value,
          accountId: accountId,
          targetOperationId: targetOperationId.value,
        ),
      ),
    );
  }

  @override
  Future<AcpInstallCommandReply> startAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
  }) async {
    await _ensureReady();
    return _acpInstallReplyFromFrb(
      await _bridgeCall(
        () => frb.startAcpInstall(
          operationId: operationId.value,
          provider: _acpProviderToFrb(provider),
        ),
      ),
    );
  }

  @override
  Future<AcpInstallCommandReply> cancelAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
    required OperationId targetOperationId,
  }) async {
    await _ensureReady();
    return _acpInstallReplyFromFrb(
      await _bridgeCall(
        () => frb.cancelAcpInstall(
          operationId: operationId.value,
          provider: _acpProviderToFrb(provider),
          targetOperationId: targetOperationId.value,
        ),
      ),
    );
  }

  @override
  Future<AcpInstallCommandReply> checkAcpInstallUpdate({
    required OperationId operationId,
    required AcpProviderView provider,
  }) async {
    await _ensureReady();
    return _acpInstallReplyFromFrb(
      await _bridgeCall(
        () => frb.checkAcpInstallUpdate(
          operationId: operationId.value,
          provider: _acpProviderToFrb(provider),
        ),
      ),
    );
  }

  @override
  Future<AgentProfilesStateView> readAgentProfilesState() async {
    await _ensureReady();
    return _agentProfilesStateFromFrb(
      await _bridgeCall(frb.readAgentProfilesState),
    );
  }

  @override
  Future<List<AgentProfileView>> readAgentProfiles() async {
    return (await readAgentProfilesState()).data.profiles;
  }

  @override
  Future<SettingsCommandReply> setSystemAgentEnabled({
    required OperationId operationId,
    required String profileId,
    required bool enabled,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.setSystemAgentEnabled(
          operationId: operationId.value,
          profileId: profileId,
          enabled: enabled,
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> saveUserAgentProfile(
    AgentProfileDraft draft, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.saveUserAgentProfile(
          operationId: operationId.value,
          expectedDocumentRevision: draft.definition.revision.isEmpty
              ? null
              : draft.definition.revision,
          profileId: draft.id,
          enabled: draft.enabled,
          displayName: draft.definition.displayName,
          description: draft.definition.description,
          whenToUse: draft.definition.whenToUse,
          binding: agentBindingToFrb(draft.binding),
          workspaceMode: switch (draft.workspaceMode) {
            AgentWorkspaceMode.unrestricted =>
              frb.BridgeAgentWorkspaceMode.unrestricted,
            AgentWorkspaceMode.directory =>
              frb.BridgeAgentWorkspaceMode.directory,
            AgentWorkspaceMode.worktree =>
              frb.BridgeAgentWorkspaceMode.worktree,
            AgentWorkspaceMode.review => frb.BridgeAgentWorkspaceMode.review,
          },
        ),
      ),
    );
  }

  @override
  Future<void> cleanupPreservedWorktree({
    required String ownerKind,
    required String ownerThreadId,
    required int expectedLeaseRevision,
  }) async {
    await _ensureReady();
    await _bridgeCall(
      () => frb.cleanupPreservedWorktree(
        ownerKind: ownerKind,
        ownerThreadId: ownerThreadId,
        expectedLeaseRevision: BigInt.from(expectedLeaseRevision),
      ),
    );
  }

  @override
  Future<StudioBootstrap> readBootstrap() async {
    await _ensureReady();
    final watch = Stopwatch()..start();
    final state = studioBootstrapFromFrbSnapshot(
      await _bridgeCall(frb.readStudioState),
    );
    debugPrint(
      'startup_stage=read_state elapsed_ms=${watch.elapsedMilliseconds}',
    );
    return state;
  }

  @override
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window, {
    required ClientResourceId resourceId,
  }) async {
    final entry = contentScope
        .open<
          _FrbRawPull<
            frb_directory_feed.BridgeThreadsObservation,
            ThreadDirectoryFrame
          >
        >('thread-directory', (operation) async {
          await _ensureReady();
          final handle = await _bridgeCall(
            () => frb_directory_feed.openThreadsObservation(
              query: frb_directory_types.BridgeThreadDirectoryQuery(
                workspaceId: query.workspaceId,
                search: query.search,
                archived: query.archived,
                filter: switch (query.filter) {
                  DirectoryFilter.all =>
                    frb_directory_types.BridgeThreadDirectoryFilter.all,
                  DirectoryFilter.running =>
                    frb_directory_types.BridgeThreadDirectoryFilter.running,
                  DirectoryFilter.attention =>
                    frb_directory_types.BridgeThreadDirectoryFilter.attention,
                },
                threadIds: query.threadIds,
                excludedThreadIds: query.excludedThreadIds,
              ),
              window: frb_directory_types.BridgeThreadDirectoryWindow(
                before: window.before,
                limit: window.limit,
              ),
            ),
          );
          return _FrbRawPull(
            operation.resourceId,
            handle,
            (handle) async {
              final frame = await handle.next();
              return frame == null ? null : _threadDirectoryFrameFromFrb(frame);
            },
            (handle) => handle.requestClose(),
            (handle) => handle.close(),
            (handle) => handle.dispose(),
          );
        }, identity: resourceId);
    return _FrbThreadsObservation(entry, await entry.ready);
  }

  @override
  Future<ThreadObservationHandle> openThreadObservation(
    String threadId, {
    required ClientResourceId resourceId,
  }) async {
    final entry = contentScope
        .open<
          _FrbRawPull<
            frb_directory_feed.BridgeThreadObservation,
            ThreadMetadataFrame
          >
        >('thread-metadata', (operation) async {
          await _ensureReady();
          final handle = await _bridgeCall(
            () => frb_directory_feed.openThreadObservation(threadId: threadId),
          );
          return _FrbRawPull(
            operation.resourceId,
            handle,
            (handle) async {
              final frame = await handle.next();
              return frame == null ? null : _threadMetadataFrameFromFrb(frame);
            },
            (handle) => handle.requestClose(),
            (handle) => handle.close(),
            (handle) => handle.dispose(),
          );
        }, identity: resourceId);
    return _FrbThreadObservation(entry, await entry.ready);
  }

  @override
  Future<SessionDirectoryRow> restoreThread(String threadId) async {
    await _ensureReady();
    return _sessionDirectoryRowFromFrb(
      await _bridgeCall(() => frb.restoreThread(threadId: threadId)),
    );
  }

  @override
  Future<WorkflowRuntimeGraphSnapshotView?> getThreadWorkflowGraph(
    String threadId,
  ) async {
    await _ensureReady();
    final graph = await _bridgeCall(
      () => frb.getThreadWorkflowGraph(threadId: threadId),
    );
    return graph == null ? null : acp_mapper.workflowGraphFromFrb(graph);
  }

  @override
  Future<StudioProject> renameProject(String workspaceId, String name) async {
    await _ensureReady();
    return _projectFromFrb(
      await _bridgeCall(
        () => frb.renameProject(workspaceId: workspaceId, name: name),
      ),
    );
  }

  @override
  Future<StudioProject> openProject(String path) async {
    await _ensureReady();
    return _projectFromFrb(
      await _bridgeCall(() => frb.openProject(path: path)),
    );
  }

  @override
  Future<ProjectDirectoryState> prepareStandaloneWorkspace() async {
    await _ensureReady();
    return _projectDirectoryFromFrb(
      await _bridgeCall(frb.prepareStandaloneWorkspace),
    );
  }

  @override
  Future<List<SshServer>> listSshServers() async {
    await _ensureReady();
    final servers = await _bridgeCall(frb_ssh.listSshServers);
    return servers.map(_sshServerFromFrb).toList(growable: false);
  }

  @override
  Future<SshServer> saveSshServer(SaveSshServerCommand command) async {
    await _ensureReady();
    final server = await _bridgeCall(
      () => frb_ssh.saveSshServer(
        request: frb_ssh_types.SaveSshServerRequest(
          alias: command.alias,
          hostName: command.hostName,
          port: command.port,
          username: command.username,
          identityFile: command.identityFile,
          password: switch (command.password.action) {
            SshPasswordAction.preserve =>
              const frb_ssh_types.SshPasswordInput.preserve(),
            SshPasswordAction.replace => frb_ssh_types.SshPasswordInput.replace(
              value: command.password.value!,
            ),
            SshPasswordAction.clear =>
              const frb_ssh_types.SshPasswordInput.clear(),
          },
        ),
      ),
    );
    return _sshServerFromFrb(server);
  }

  @override
  Future<void> deleteSshServer(String alias) async {
    await _ensureReady();
    await _bridgeCall(() => frb_ssh.deleteSshServer(alias: alias));
  }

  @override
  Future<SshConnectionView> authenticateSshServer(
    AuthenticateSshServerCommand command,
  ) async {
    await _ensureReady();
    final snapshot = await _bridgeCall(
      () => frb_ssh.authenticateSshServer(
        request: frb_ssh_types.AuthenticateSshServerRequest(
          alias: command.alias,
          password: command.password,
          rememberPassword: command.rememberPassword,
        ),
      ),
    );
    return SshConnectionView(
      alias: snapshot.alias,
      state: snapshot.state,
      helperVersion: snapshot.helperVersion,
      architecture: snapshot.architecture,
      errorCode: snapshot.errorCode,
      errorMessage: snapshot.errorMessage,
    );
  }

  @override
  Future<SshConnectionView> testSshConnection(String alias) async {
    await _ensureReady();
    final snapshot = await _bridgeCall(
      () => frb_ssh.testSshConnection(alias: alias),
    );
    return SshConnectionView(
      alias: snapshot.alias,
      state: snapshot.state,
      helperVersion: snapshot.helperVersion,
      architecture: snapshot.architecture,
      errorCode: snapshot.errorCode,
      errorMessage: snapshot.errorMessage,
    );
  }

  @override
  Future<SshConnectionView> reconnectSshServer(String alias) async {
    await _ensureReady();
    final snapshot = await _bridgeCall(
      () => frb_ssh.reconnectSshServer(alias: alias),
    );
    return SshConnectionView(
      alias: snapshot.alias,
      state: snapshot.state,
      helperVersion: snapshot.helperVersion,
      architecture: snapshot.architecture,
      errorCode: snapshot.errorCode,
      errorMessage: snapshot.errorMessage,
    );
  }

  @override
  Future<RemoteDirectoryListing> browseRemoteDirectories(
    String alias, {
    String? path,
    String? cursor,
  }) async {
    await _ensureReady();
    final listing = await _bridgeCall(
      () => frb_ssh.browseRemoteDirectories(
        alias: alias,
        path: path,
        cursor: cursor,
      ),
    );
    return RemoteDirectoryListing(
      path: listing.path,
      parent: listing.parent,
      nextCursor: listing.nextCursor,
      entries: listing.entries
          .map(
            (entry) => RemoteDirectoryEntry(name: entry.name, path: entry.path),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> closeRemoteDirectory(String alias, String cursor) async {
    await _ensureReady();
    await _bridgeCall(
      () => frb_ssh.closeRemoteDirectory(alias: alias, cursor: cursor),
    );
  }

  @override
  Future<StudioProject> openRemoteProject(String alias, String path) async {
    await _ensureReady();
    return _projectFromFrb(
      await _bridgeCall(
        () => frb_ssh.openRemoteProject(alias: alias, path: path),
      ),
    );
  }

  @override
  Future<void> activateProject(String workspaceId) async {
    await _ensureReady();
    await _bridgeCall(() => frb.activateProject(workspaceId: workspaceId));
  }

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String workspaceId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    String? serviceTier,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  }) async* {
    await _ensureReady();
    try {
      await for (final event in frb.startNewThread(
        request: frb.BridgeStartNewThreadRequest(
          workspaceId: workspaceId,
          input: _bridgePromptInput(input),
          mode: mode.id,
          accountId: route.accountId,
          modelId: route.modelId,
          effort: route.effort.isEmpty ? null : route.effort,
          serviceTier: serviceTier,
          workspaceMode: workspaceMode,
          delegationMode: _delegationModeToFrb(delegationMode),
          delegationPreference: _delegationPreferenceToFrb(
            delegationPreference,
          ),
        ),
      )) {
        yield _newThreadStartEventFromFrb(event);
      }
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_studioFailure(error), stackTrace);
    }
  }

  @override
  Future<RenameThreadCommandReply> renameThread(
    String threadId,
    String title, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.renameThread(
        operationId: operationId.value,
        threadId: threadId,
        title: title,
      ),
    );
    return RenameThreadCommandReply(
      thread: _sessionDirectoryRowFromFrb(response.thread),
      receipt: _commandReceiptFromFrb(response.receipt),
    );
  }

  @override
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () =>
          frb.archiveThread(operationId: operationId.value, threadId: threadId),
    );
    return ArchiveThreadCommandReply(
      result: ArchiveThreadResult(
        archivedRootId: response.result.archivedRootId,
        removedThreadIds: response.result.removedThreadIds,
        nextRoot: response.result.nextRoot == null
            ? null
            : _sessionDirectoryRowFromFrb(response.result.nextRoot!),
      ),
      receipt: _commandReceiptFromFrb(response.receipt),
    );
  }

  @override
  Future<DeleteThreadCommandReply?> deleteThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () =>
          frb.deleteThread(operationId: operationId.value, threadId: threadId),
    );
    if (response == null) return null;
    return DeleteThreadCommandReply(
      result: DeleteThreadResult(
        deletedRootId: response.result.deletedRootId,
        deletedThreadIds: response.result.deletedThreadIds,
        nextRoot: response.result.nextRoot == null
            ? null
            : _sessionDirectoryRowFromFrb(response.result.nextRoot!),
      ),
      receipt: _commandReceiptFromFrb(response.receipt),
    );
  }

  @override
  Future<void> archiveProject(String workspaceId) async {
    await _ensureReady();
    await _bridgeCall(() => frb.archiveProject(workspaceId: workspaceId));
  }

  @override
  Future<PersistenceStateSnapshot> retryPersistence() async {
    await _ensureReady();
    return _persistenceStateFromFrb(await _bridgeCall(frb.retryPersistence));
  }

  @override
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  ) async {
    await _ensureReady();
    return _persistenceQueueFromFrb(
      await _bridgeCall(
        () => frb.retryThreadHistory(
          threadId: threadId,
          faultGeneration: BigInt.from(faultGeneration),
        ),
      ),
    );
  }

  @override
  Future<PersistenceQueueStateView> readPersistenceQueueState() async {
    await _ensureReady();
    return _persistenceQueueStateFromFrb(
      await _bridgeCall(frb.readPersistenceQueue),
    );
  }

  @override
  Future<PersistenceQueueSnapshot> readPersistenceQueue() async {
    return (await readPersistenceQueueState()).queue;
  }

  @override
  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  ) async {
    await _ensureReady();
    return _persistenceQueueFromFrb(
      await _bridgeCall(
        () => frb.resumeThreadHistory(
          threadId: threadId,
          faultGeneration: BigInt.from(faultGeneration),
        ),
      ),
    );
  }

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute({
    required OperationId operationId,
    required String threadId,
    required int expectedModelRouteRevision,
    required String accountId,
    required String modelId,
    String? effort,
    String? serviceTier,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.setThreadModelRoute(
        request: frb_command.BridgeSetThreadModelRouteRequest(
          operationId: operationId.value,
          threadId: threadId,
          expectedModelRouteRevision: BigInt.from(expectedModelRouteRevision),
          accountId: accountId,
          modelId: modelId,
          effort: effort,
          serviceTier: serviceTier,
        ),
      ),
    );
    return ThreadModelRouteCommandReply(
      receipt: _commandReceiptFromFrb(response.receipt),
      runtime: _threadRuntimeFromFrb(response.runtime),
      settings: _settingsStateFromFrb(response.settings),
      modeDefaultSaved: response.modeDefaultSaved,
      warning: response.warning,
    );
  }

  @override
  Future<void> compactThread(String threadId) async {
    await _ensureReady();
    await _bridgeCall(() => frb.compactThread(threadId: threadId));
  }

  @override
  Future<ThreadModeCommandReply> setThreadMode({
    required OperationId operationId,
    required String threadId,
    required ThreadModeId mode,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.setThreadMode(
        operationId: operationId.value,
        threadId: threadId,
        mode: mode.id,
      ),
    );
    return ThreadModeCommandReply(
      receipt: _commandReceiptFromFrb(response.receipt),
    );
  }

  @override
  Future<ModeDefinitionSnapshot> readThreadModeDefinition(String modeId) async {
    await _ensureReady();
    return _modeDefinitionSnapshotFromFrb(
      await _bridgeCall(
        () => frb_mode_editor.readThreadModeDefinition(modeId: modeId),
      ),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> saveThreadModeDefinition(
    ModeDocument document, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _modeDefinitionCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_mode_editor.saveThreadModeDefinition(
          operationId: operationId.value,
          expectedRevision: BigInt.from(expectedRevision),
          document: _bridgeModeDocument(document),
        ),
      ),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> deleteThreadModeDefinition(
    String modeId, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _modeDefinitionCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_mode_editor.deleteThreadModeDefinition(
          operationId: operationId.value,
          expectedRevision: BigInt.from(expectedRevision),
          modeId: modeId,
        ),
      ),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> reloadThreadModeDefinitions({
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _modeDefinitionCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_mode_editor.reloadThreadModeDefinitions(
          operationId: operationId.value,
          expectedRevision: BigInt.from(expectedRevision),
        ),
      ),
    );
  }

  @override
  Future<ModeValidationResult> validateThreadModeDefinition(String json) async {
    await _ensureReady();
    return _modeValidationResultFromFrb(
      await _bridgeCall(
        () => frb_mode_editor.validateThreadModeDefinition(json: json),
      ),
    );
  }

  @override
  Future<String> threadModeDefinitionSchema() async {
    await _ensureReady();
    return _bridgeCall(frb_mode_editor.threadModeDefinitionSchema);
  }

  @override
  Future<WorkflowPreviewSnapshot> previewThreadModeWorkflow(
    WorkflowPreviewRequest request,
  ) async {
    await _ensureReady();
    return _workflowPreviewSnapshotFromFrb(
      await _bridgeCall(
        () => frb_mode_editor.previewThreadModeWorkflow(
          request: _bridgeWorkflowPreviewRequest(request),
        ),
      ),
    );
  }

  @override
  Stream<StudioShutdownProgress> subscribeShutdownProgress() {
    if (!runtime.runtimeOwnerPresent) return const Stream.empty();
    final entry = progressScope
        .open<_FrbRawEvent<frb.BridgeShutdownProgress, StudioShutdownProgress>>(
          'shutdown-progress',
          (operation) async {
            final handle = await _bridgeCall(
              frb_shutdown_sub.subscribeShutdownProgress,
            );
            return _FrbRawEvent(
              operation.resourceId,
              handle,
              (handle) => handle.shutdownStream(),
              (event) => switch (event) {
                frb.BridgeShutdownProgress_StoppingSubscriptions() =>
                  const StoppingSubscriptionsProgress(),
                frb.BridgeShutdownProgress_CancellingTurns() =>
                  const CancellingTurnsProgress(),
                frb.BridgeShutdownProgress_FlushingPersistence(
                  :final pendingCommits,
                ) =>
                  FlushingPersistenceProgress(
                    pendingCommits: pendingCommits.toInt(),
                  ),
                frb.BridgeShutdownProgress_StoppingAgents() =>
                  const StoppingAgentsProgress(),
                frb.BridgeShutdownProgress_StoppingMcp() =>
                  const StoppingMcpProgress(),
                frb.BridgeShutdownProgress_StoppingLsp() =>
                  const StoppingLspProgress(),
                frb.BridgeShutdownProgress_Stopped() => const StoppedProgress(),
              },
            );
          },
        );
    // Stream cancellation controls only its consumer; the independent progress
    // scope is closed and joined explicitly by the existing coordinator.
    return Stream.fromFuture(
      _publishRaw(entry, (raw) {
        raw.attach(onFailure: entry.requestClose);
        return raw.frames;
      }),
    ).asyncExpand((frames) => frames);
  }

  @override
  Future<void> beginRuntimeExit({required int remainingMs}) async {
    runtime.sealForShutdown();
    final outcome = await runtime._runBeginRuntimeExit(remainingMs);
    final error = outcome.error;
    if (error != null) {
      // 原始错误/堆栈抛给协调器：协调器据 memoized issue（同一 correlation）作为 external
      // issue 继续收尾，绝不用无界等待或伪成功。
      Error.throwWithStackTrace(
        error,
        outcome.stackTrace ?? StackTrace.current,
      );
    }
  }

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    bool externalDartResourcesReported = false,
    StudioExitIntent intent = StudioExitIntent.exit,
  }) {
    // The declaration never replaces the runtime's final root acknowledgement
    // and is not part of the native FRB wire.
    return runtime.shutdownAndDispose(
      remainingMs: remainingMs,
      externalIssues: externalIssues,
      intent: intent,
    );
  }

  @override
  Future<InteractionCommandReply> respondInteraction(
    String hostThreadId,
    String interactionId,
    int expectedRevision,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.respondInteraction(
        operationId: operationId.value,
        hostThreadId: hostThreadId,
        expectedRevision: BigInt.from(expectedRevision),
        interactionId: interactionId,
        resolution: _interactionResolutionFromDomain(resolution),
      ),
    );
    return InteractionCommandReply(
      interaction: _interactionFromFrb(response.interaction),
      receipt: _commandReceiptFromFrb(response.receipt),
    );
  }

  static Future<T> _bridgeCall<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_studioFailure(error), stackTrace);
    }
  }

  @override
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.stopThread(
        operationId: operationId.value,
        threadId: threadId,
        expectedExecutionId: executionId,
      ),
    );
    return StopThreadCommandReply(
      threadId: response.threadId,
      executionId: response.executionId,
      stopped: response.stopped,
      receipt: _commandReceiptFromFrb(response.receipt),
    );
  }

  @override
  Future<ContinueThreadCommandReply> continueThread(
    String threadId,
    String continuationId, {
    required int expectedModelRouteRevision,
    required OperationId operationId,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.continueThread(
        operationId: operationId.value,
        threadId: threadId,
        expectedContinuationToken: continuationId,
        expectedModelRouteRevision: BigInt.from(expectedModelRouteRevision),
      ),
    );
    return ContinueThreadCommandReply(
      threadId: response.threadId,
      inputId: response.inputId,
      continuationId: response.continuationId,
      cursor: response.cursor.toInt(),
      receipt: _commandReceiptFromFrb(response.receipt),
    );
  }

  @override
  Future<ContinuationOperationView> readContinuationOperation(
    String threadId,
    String operationId,
    String expectedContinuationToken,
  ) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.readContinuationOperation(
        threadId: threadId,
        operationId: operationId,
        expectedContinuationToken: expectedContinuationToken,
      ),
    );
    return ContinuationOperationView(
      threadId: response.threadId,
      operationId: response.operationId,
      expectedContinuationToken: response.expectedContinuationToken,
      state:
          response.state == frb_command.BridgeContinuationOperationState.known
          ? ContinuationOperationState.known
          : ContinuationOperationState.notAccepted,
      acceptanceEpoch: response.acceptanceEpoch,
      executionId: response.executionId,
      turnId: response.turnId,
      acceptedRevision: response.acceptedRevision?.toInt(),
      disposition: response.disposition == null
          ? null
          : switch (response.disposition!) {
              frb_command.BridgeContinuationDisposition_Scheduled() =>
                ContinuationDisposition.scheduled,
              frb_command.BridgeContinuationDisposition_Effective() =>
                ContinuationDisposition.effective,
              frb_command.BridgeContinuationDisposition_NotExecuted() =>
                ContinuationDisposition.notExecuted,
            },
      notExecutedReason: switch (response.disposition) {
        frb_command.BridgeContinuationDisposition_NotExecuted(:final reason) =>
          reason,
        _ => null,
      },
      receipt: response.receipt == null
          ? null
          : _commandReceiptFromFrb(response.receipt!),
    );
  }

  @override
  Future<List<ChildInteractionSummary>> readChildInteractions(
    String threadId,
  ) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.readChildInteractions(threadId: threadId),
    );
    return response.map(_childInteractionFromFrb).toList();
  }

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) {
    final entry = contentScope
        .open<
          _FrbRawEvent<
            frb_topic_types.BridgeProductTopicStreamEnvelope,
            ProductTopicFrame
          >
        >('product-topic', (operation) async {
          await _ensureReady();
          final handle = await _bridgeCall(
            () => frb_topic_sub.createProductTopicSubscription(
              topic: bridgeProductTopic(topic),
            ),
          );
          return _FrbRawEvent(
            operation.resourceId,
            handle,
            (handle) => handle.productTopicStream(),
            (envelope) => productTopicFrameFromEnvelope(topic, envelope),
            isTerminal: (envelope) =>
                envelope
                    is frb_topic_types.BridgeProductTopicStreamEnvelope_Closed,
          );
        }, identity: resourceId);
    return _publishRaw(entry, (raw) {
      raw.attach(onFailure: entry.requestClose);
      return _FrbProductTopicObservation(entry, raw);
    });
  }

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) {
    final entry = contentScope.open<_FrbRawHistoryReader>('history', (
      operation,
    ) async {
      await _ensureReady();
      final handle = await _bridgeCall(
        () => frb_timeline.openHistoryReader(
          threadId: threadId,
          historyProtocolVersion: historyProtocolVersion,
        ),
      );
      return _FrbRawHistoryReader(operation.resourceId, handle);
    });
    return _publishRaw(entry, (raw) {
      final reader = FrbHistoryReader._(entry, raw);
      reader.metadata;
      reader.threadId;
      return reader;
    });
  }

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) {
    final watchesScope = contentScope.child('current-watches');
    final entry = contentScope.open<_FrbRawCurrentReader>('current', (
      operation,
    ) async {
      await _ensureReady();
      final handle = await _bridgeCall(
        () => frb_timeline.openCurrentReader(
          threadId: threadId,
          currentProtocolVersion: currentProtocolVersion,
          demand: _readDemandToFrb(demand),
        ),
      );
      return _FrbRawCurrentReader(
        operation.resourceId,
        handle,
        watchesScope,
        _ensureReady,
      );
    }, onFailure: (_, _) => watchesScope.requestClose());
    return _publishRaw(entry, (raw) {
      final reader = FrbCurrentReader._(entry, raw);
      reader.metadata;
      reader.threadId;
      reader.initialView;
      return reader;
    });
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) async {
    await _ensureReady();
    final response = await _bridgeCall(
      () => frb.submitPrompt(
        threadId: threadId,
        input: _bridgePromptInput(input),
        expectedModelRouteRevision: BigInt.from(expectedModelRouteRevision),
      ),
    );
    return SubmitPromptReceipt(
      threadId: response.threadId,
      inputId: response.inputId,
      cursor: response.revision.toInt(),
    );
  }

  @override
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) async {
    await _ensureReady();
    final drafts = await _bridgeCall(
      () => frb_attachment.admitAttachmentDrafts(
        context: switch (context) {
          ExistingThreadAttachmentAdmissionContext(:final threadId) =>
            frb_attachment_types
                .BridgeAttachmentAdmissionContext.existingThread(
              threadId: threadId,
            ),
          NewThreadAttachmentAdmissionContext(:final route) =>
            frb_attachment_types.BridgeAttachmentAdmissionContext.newThread(
              route: frb.BridgeNewThreadModelRoute(
                accountId: route.accountId,
                modelId: route.modelId,
                effort: route.effort.isEmpty ? null : route.effort,
              ),
            ),
        },
        sources: [
          for (final source in sources)
            switch (source) {
              LocalFileAttachmentDraftSource(:final path) =>
                frb_attachment_types.BridgeAttachmentDraftSource.localFile(
                  path: path,
                ),
              RemoteUrlAttachmentDraftSource(:final url, :final filename) =>
                frb_attachment_types.BridgeAttachmentDraftSource.remoteUrl(
                  url: url,
                  filename: filename,
                ),
            },
        ],
      ),
    );
    return [for (final draft in drafts) _attachmentDraftFromFrb(draft)];
  }

  @override
  Future<bool> removeAttachmentDraft(String draftId) async {
    await _ensureReady();
    return _bridgeCall(
      () => frb_attachment.removeAttachmentDraft(draftId: draftId),
    );
  }

  @override
  Future<Uint8List> readAttachmentDraft(String draftId) async {
    await _ensureReady();
    return _bridgeCall(
      () => frb_attachment.readAttachmentDraft(draftId: draftId),
    );
  }

  @override
  Future<Uint8List> readThreadAttachment(
    String threadId,
    String attachmentId,
  ) async {
    await _ensureReady();
    return _bridgeCall(
      () => frb_attachment.readThreadAttachment(
        threadId: threadId,
        attachmentId: attachmentId,
      ),
    );
  }

  @override
  Future<SettingsCommandReply> saveRuntimePermissionMode(
    PermissionMode mode, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.saveRuntimePermissionMode(
          operationId: operationId.value,
          mode: _permissionModeLabel(mode),
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> createAccount(
    int expectedSettingsRevision,
    CreateAccountCommand command, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.createAccount(
          operationId: operationId.value,
          expectedSettingsRevision: BigInt.from(expectedSettingsRevision),
          input: frb.AccountSettingsInput(
            account: frb.AccountInput(
              accountId: command.identity.accountId,
              authentication: _accountAuthenticationIntentToFrb(
                command.authentication,
              ),
              templateId: command.templateId,
              protocol: command.protocol,
              name: command.name,
              baseUrl: command.baseUrl,
              secret: _secretInput(command.secret),
              initialBillingKind: command.initialBillingKind == null
                  ? null
                  : _billingKindToFrb(command.initialBillingKind!),
              customModels: command.customModels
                  .map(_manualModelInput)
                  .toList(),
              modelConnectionModes: [
                for (final connection in command.modelConnectionModes)
                  frb.AccountModelConnectionInput(
                    modelId: connection.modelId,
                    connectionMode: connection.connectionMode,
                  ),
              ],
              modelAutoCompactLimits: [
                for (final compact in command.modelAutoCompactLimits)
                  frb.AccountModelAutoCompactInput(
                    modelId: compact.modelId,
                    limit: BigInt.from(compact.limit),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> setDefaultAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.setDefaultAccount(
          operationId: operationId.value,
          expectedSettingsRevision: BigInt.from(expectedSettingsRevision),
          accountId: accountId,
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> removeAccountModel(
    int expectedSettingsRevision,
    String accountId,
    String modelId, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.removeAccountModel(
          operationId: operationId.value,
          expectedSettingsRevision: BigInt.from(expectedSettingsRevision),
          accountId: accountId,
          modelId: modelId,
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> setAccountModelEnabled(
    String accountId,
    String modelId,
    bool enabled, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.setAccountModelEnabled(
          operationId: operationId.value,
          accountId: accountId,
          modelId: modelId,
          enabled: enabled,
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> setAccountBillingKind(
    String accountId,
    BillingKind? billingKind, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.setAccountBillingKind(
          operationId: operationId.value,
          accountId: accountId,
          billingKind: billingKind == null
              ? null
              : _billingKindToFrb(billingKind),
        ),
      ),
    );
  }

  @override
  Future<DelegationModelList> listDelegationModels(
    ListDelegationModelsRequest request,
  ) async {
    await _ensureReady();
    return _delegationListFromFrb(
      await _bridgeCall(
        () => frb.listDelegationModels(
          request: _delegationListRequestToFrb(request),
        ),
      ),
    );
  }

  @override
  Future<DelegationModelDetail> getDelegationModel(
    DelegationModelKey key,
  ) async {
    await _ensureReady();
    return delegationModelDetailFromFrb(
      await _bridgeCall(
        () => frb.getDelegationModel(
          request: frb.BridgeGetDelegationModelRequest(
            accountId: key.accountId,
            modelId: key.modelId,
          ),
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> removeAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
    String? replacementAccountId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.removeAccount(
          operationId: operationId.value,
          expectedSettingsRevision: BigInt.from(expectedSettingsRevision),
          accountId: accountId,
          input: frb.RemoveAccountInput(
            replacementAccountId: replacementAccountId,
          ),
        ),
      ),
    );
  }

  @override
  Future<SettingsCommandReply> applySettingsField(
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) async {
    await _ensureReady();
    return _settingsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb.applySettingsField(
          operationId: operationId.value,
          input: _settingsFieldInputFromDomain(command),
        ),
      ),
    );
  }

  @override
  Future<SettingsStateSnapshot> readSettingsState() async {
    await _ensureReady();
    return _settingsStateFromFrb(await _bridgeCall(frb.readSettingsState));
  }

  @override
  Future<SkillsStateSnapshot> readSkillsState(String workspaceId) async {
    await _ensureReady();
    return _skillsStateFromFrb(
      await _bridgeCall(() => frb.readSkillsState(workspaceId: workspaceId)),
    );
  }

  @override
  Future<SkillsStateSnapshot> discoverSkills(String workspaceId) async {
    await _ensureReady();
    return _skillsStateFromFrb(
      await _bridgeCall(() => frb.discoverSkills(workspaceId: workspaceId)),
    );
  }

  @override
  Future<SkillSearchResultView> searchSkills(
    String workspaceId,
    String query, {
    int limit = 50,
  }) async {
    await _ensureReady();
    return _skillSearchResultFromFrb(
      await _bridgeCall(
        () => frb.searchSkills(
          workspaceId: workspaceId,
          query: query,
          limit: limit,
        ),
      ),
    );
  }

  @override
  Future<McpCatalogSnapshot> readMcpCatalog(McpScope scope) async {
    await _ensureReady();
    return _mcpCatalogFromFrb(
      await _bridgeCall(() => frb.readMcpCatalog(scope: _mcpScopeToFrb(scope))),
    );
  }

  @override
  Future<McpCatalogSnapshot> reloadMcpCatalog(McpScope scope) async {
    await _ensureReady();
    return _mcpCatalogFromFrb(
      await _bridgeCall(
        () => frb.reloadMcpCatalog(scope: _mcpScopeToFrb(scope)),
      ),
    );
  }

  @override
  Future<McpDocumentContent> readMcpDocument(McpDocumentRef document) async {
    await _ensureReady();
    return _mcpDocumentContentFromFrb(
      await _bridgeCall(
        () => frb.readMcpDocument(document: _mcpDocumentRefToFrb(document)),
      ),
    );
  }

  @override
  Future<McpDocumentCommitReceipt> createMcpDocument({
    required McpScope scope,
    required String id,
    required String rawToml,
  }) async {
    await _ensureReady();
    return _mcpDocumentCommitReceiptFromFrb(
      await _bridgeCall(
        () => frb.createMcpDocument(
          input: frb.BridgeCreateMcpDocumentInput(
            scope: _mcpScopeToFrb(scope),
            id: id,
            rawToml: rawToml,
          ),
        ),
      ),
    );
  }

  @override
  Future<McpDocumentCommitReceipt> updateMcpDocument({
    required McpDocumentRef document,
    required int expectedRevision,
    required String rawToml,
  }) async {
    await _ensureReady();
    return _mcpDocumentCommitReceiptFromFrb(
      await _bridgeCall(
        () => frb.updateMcpDocument(
          input: frb.BridgeUpdateMcpDocumentInput(
            document: _mcpDocumentRefToFrb(document),
            expectedRevision: BigInt.from(expectedRevision),
            rawToml: rawToml,
          ),
        ),
      ),
    );
  }

  @override
  Future<McpDocumentCommitReceipt> deleteMcpDocument({
    required McpDocumentRef document,
    required int expectedRevision,
  }) async {
    await _ensureReady();
    return _mcpDocumentCommitReceiptFromFrb(
      await _bridgeCall(
        () => frb.deleteMcpDocument(
          input: frb.BridgeDeleteMcpDocumentInput(
            document: _mcpDocumentRefToFrb(document),
            expectedRevision: BigInt.from(expectedRevision),
          ),
        ),
      ),
    );
  }

  @override
  Future<ThreadMcpStateSnapshot> readThreadMcp(String threadId) async {
    await _ensureReady();
    return _threadMcpStateFromFrb(
      await _bridgeCall(() => frb.readThreadMcp(threadId: threadId)),
    );
  }

  @override
  Future<ThreadMcpStateSnapshot> reconnectThreadMcp({
    required String threadId,
    String? serverId,
  }) async {
    await _ensureReady();
    return _threadMcpStateFromFrb(
      await _bridgeCall(
        () => frb.reconnectThreadMcp(
          input: frb.BridgeReconnectThreadMcpInput(
            threadId: threadId,
            serverId: serverId,
          ),
        ),
      ),
    );
  }

  @override
  Future<ThreadLspStateSnapshot> readThreadLspState(String threadId) async {
    await _ensureReady();
    return _threadLspStateFromFrb(
      await _bridgeCall(() => frb.readThreadLspState(threadId: threadId)),
    );
  }

  @override
  Future<ThreadLspStateSnapshot> resetThreadLspServer({
    required String threadId,
    required String bindingId,
    required String serverId,
  }) async {
    await _ensureReady();
    return _threadLspStateFromFrb(
      await _bridgeCall(
        () => frb.resetThreadLspServer(
          input: frb_thread_lsp_types.ThreadLspResetInput(
            threadId: threadId,
            bindingId: bindingId,
            serverId: serverId,
          ),
        ),
      ),
    );
  }

  @override
  Future<LspStateSnapshot> readLspState() async {
    await _ensureReady();
    return _lspStateFromFrb(await _bridgeCall(frb.readLspState));
  }

  @override
  Future<LspStateSnapshot> probeLspServer(String workspaceId) async {
    await _ensureReady();
    return _lspStateFromFrb(
      await _bridgeCall(() => frb.probeLspServer(workspaceId: workspaceId)),
    );
  }

  @override
  Future<LspStateSnapshot> resetLspServer(
    String workspaceId,
    String serverId,
  ) async {
    await _ensureReady();
    return _lspStateFromFrb(
      await _bridgeCall(
        () => frb.resetLsp(
          input: frb.LspScopeInput.server(
            workspaceId: workspaceId,
            serverId: serverId,
          ),
        ),
      ),
    );
  }

  @override
  Future<LspStateSnapshot> resetLspWorkspace(String workspaceId) async {
    await _ensureReady();
    return _lspStateFromFrb(
      await _bridgeCall(
        () => frb.resetLsp(
          input: frb.LspScopeInput.workspace(workspaceId: workspaceId),
        ),
      ),
    );
  }

  @override
  Future<BotsStateSnapshot> readBots() async {
    await _ensureReady();
    return _botsStateFromFrb(await _bridgeCall(frb_bots.readBots));
  }

  @override
  Future<BotsCommandReply> saveBot(SaveBotRequest request) async {
    await _ensureReady();
    return _botsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.saveBot(request: _saveBotToFrb(request)),
      ),
    );
  }

  @override
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  ) async {
    await _ensureReady();
    return _botsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.startBotRegistration(
          request: frb_bots_types.BridgeStartBotRegistrationRequest(
            operationId: request.operationId,
            name: request.name,
            workspaceId: request.workspaceId,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  ) async {
    await _ensureReady();
    return _botsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.cancelBotRegistration(
          request: frb_bots_types.BridgeCancelBotRegistrationRequest(
            operationId: request.operationId,
            attemptId: request.attemptId,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request) async {
    await _ensureReady();
    return _botsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.setBotEnabled(
          request: frb_bots_types.BridgeSetBotEnabledRequest(
            operationId: request.operationId,
            botId: request.botId,
            expectedConfigRevision: BigInt.from(request.expectedConfigRevision),
            enabled: request.enabled,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotsCommandReply> retryBotConnection(
    RetryBotConnectionRequest request,
  ) async {
    await _ensureReady();
    return _botsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.retryBotConnection(
          request: frb_bots_types.BridgeRetryBotConnectionRequest(
            operationId: request.operationId,
            botId: request.botId,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotsCommandReply> setBotTrustedUser(
    SetBotTrustedUserRequest request,
  ) async {
    await _ensureReady();
    return _botsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.setBotTrustedUser(
          request: frb_bots_types.BridgeSetBotTrustedUserRequest(
            operationId: request.operationId,
            botId: request.botId,
            expectedConfigRevision: BigInt.from(request.expectedConfigRevision),
            openId: request.openId,
            trusted: request.trusted,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotsCommandReply> setBotTrustedChat(
    SetBotTrustedChatRequest request,
  ) async {
    await _ensureReady();
    return _botsCommandReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.setBotTrustedChat(
          request: frb_bots_types.BridgeSetBotTrustedChatRequest(
            operationId: request.operationId,
            botId: request.botId,
            expectedConfigRevision: BigInt.from(request.expectedConfigRevision),
            chatId: request.chatId,
            trusted: request.trusted,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotConversationPage> listBotConversations(
    ListBotConversationsRequest request,
  ) async {
    await _ensureReady();
    return _conversationPageFromFrb(
      await _bridgeCall(
        () => frb_bots.listBotConversations(
          request: frb_bots_types.BridgeListBotConversationsRequest(
            botId: request.botId,
            cursor: request.cursor,
            limit: request.limit,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotMessagePage> readBotMessages(ReadBotMessagesRequest request) async {
    await _ensureReady();
    return _messagePageFromFrb(
      await _bridgeCall(
        () => frb_bots.readBotMessages(
          request: frb_bots_types.BridgeReadBotMessagesRequest(
            botId: request.botId,
            chatId: request.chatId,
            startTime: request.startTime,
            endTime: request.endTime,
            cursor: request.cursor,
            limit: request.limit,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotSendResult> sendBotMessage(SendBotMessageRequest request) async {
    await _ensureReady();
    return _sendResultFromFrb(
      await _bridgeCall(
        () => frb_bots.sendBotMessage(
          request: frb_bots_types.BridgeSendBotMessageRequest(
            operationId: request.operationId,
            botId: request.botId,
            chatId: request.chatId,
            text: request.text,
          ),
        ),
      ),
    );
  }

  @override
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  ) async {
    await _ensureReady();
    return _conversationThreadReplyFromFrb(
      await _bridgeCall(
        () => frb_bots.createBotConversationThread(
          request: frb_bots_types.BridgeCreateBotConversationThreadRequest(
            operationId: request.operationId,
            botId: request.botId,
            chatId: request.chatId,
            expectedConfigRevision: BigInt.from(request.expectedConfigRevision),
            expectedBindingRevision: BigInt.from(
              request.expectedBindingRevision,
            ),
          ),
        ),
      ),
    );
  }
}

/// DTO 到领域的一次转换：数据层消费 typed 报告，界面只读领域形状。
StudioShutdownReport _shutdownReportFromFrb(
  frb_shutdown.BridgeShutdownReport report,
) {
  return StudioShutdownReport(
    outcome: switch (report.outcome) {
      frb_shutdown.BridgeShutdownOutcome.notStarted =>
        StudioShutdownOutcome.notStarted,
      frb_shutdown.BridgeShutdownOutcome.clean => StudioShutdownOutcome.clean,
      frb_shutdown.BridgeShutdownOutcome.degraded =>
        StudioShutdownOutcome.degraded,
    },
    issues: [
      for (final issue in report.issues)
        StudioShutdownIssue(
          stage: issue.stage,
          code: issue.code,
          message: issue.message,
          retryable: issue.retryable,
          correlationId: issue.correlationId,
        ),
    ],
    persistence: switch (report.persistence) {
      frb_shutdown.BridgePendingPersistence_Unknown() =>
        const UnknownStudioPendingPersistence(),
      frb_shutdown.BridgePendingPersistence_Pending(:final count) =>
        PendingStudioPendingPersistence(count: count.toInt()),
      frb_shutdown.BridgePendingPersistence_Drained() =>
        const DrainedStudioPendingPersistence(),
    },
  );
}
