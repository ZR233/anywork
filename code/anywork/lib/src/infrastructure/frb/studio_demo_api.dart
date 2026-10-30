part of 'studio_api.dart';

const WorkflowDefinition _demoTaskWorkflow = WorkflowDefinition(
  title: '任务流程',
  goal: '完成任务并交付可验证结果',
  initialStateId: 'implement',
  states: [
    WorkflowState(
      id: 'implement',
      title: '实现',
      instructions: '完成用户请求并验证结果。',
      completionCriteria: ['实现完成', '验证通过'],
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowState(
      id: 'done',
      title: '完成',
      instructions: '汇总结果并结束任务。',
      completionCriteria: ['结果已交付'],
      kind: WorkflowStateKind.finalState,
    ),
  ],
  transitions: [
    WorkflowTransition(
      sourceStateId: 'implement',
      targetStateId: 'done',
      guard: '实现完成且验证通过',
    ),
  ],
);

class DemoStudioTransport extends StudioTransport
    implements
        PersistenceQueueReader,
        AccountFeedPort,
        AccountConfigurationPort,
        AccountModelsPort,
        AccountUsagePort,
        AcpPort {
  @override
  Future<RecoveryStateSnapshot> retryRecovery() async => _demoRecoveryState();

  DemoStudioTransport({
    this.lspActivityLoop = false,
    this._accountCatalog = demoAccountCatalogFixture,
  });

  /// 目录分页窗口的页大小；Driver 模式填充大量历史会话以验收触底加载。
  static const int directoryPageSize = 20;

  final AccountCatalogView _accountCatalog;
  final Map<DemoAccountObservation, AccountObservationTarget>
  _accountObservations = {};
  final Map<NativeAccountIdentity, AccountUsageObservation> _usageFacts = {};
  final Map<NativeAccountIdentity, ModelSyncAdmission> _modelSyncs = {};
  bool _accountAdmissionsSealed = false;
  int _modelCatalogRevision = 1;
  int _usageIdentitySequence = 1;
  int _modelQuerySequence = 0;
  bool _runtimeExiting = false;
  final Set<Future<void>> _demoJobs = {};
  final Set<_DemoDelay> _demoDelays = {};
  final List<StudioShutdownIssue> _demoBusinessIssues = [];
  Future<void>? _demoBusinessStopped;
  Future<StudioExitReport>? _demoShutdown;

  void _ensureDemoRunning() {
    if (_runtimeExiting) {
      throw const StudioFailure(
        code: StudioFailureCode.runtimeStopped,
        message: 'Demo runtime is stopping',
        retryable: false,
        correlationId: 'demo-runtime-stopped',
      );
    }
  }

  Future<void> _waitDemo(Duration duration) {
    if (_runtimeExiting) return Future.value();
    final delay = _DemoDelay(duration);
    _demoDelays.add(delay);
    return delay.done.future.whenComplete(() {
      _demoDelays.remove(delay);
    });
  }

  void _runDemoJob(Future<void> Function() run) {
    if (_runtimeExiting) return;
    final completed = Completer<void>();
    final joined = completed.future;
    _demoJobs.add(joined);
    void finish() {
      _demoJobs.remove(joined);
      completed.complete();
    }

    unawaited(
      Future<void>.sync(run).then<void>(
        (_) {
          finish();
        },
        onError: (Object _, StackTrace _) {
          _demoBusinessIssues.add(
            const StudioShutdownIssue(
              stage: 'demo-business',
              code: 'taskFailed',
              message: 'Demo task failed',
              retryable: false,
              correlationId: 'demo-task',
            ),
          );
          finish();
        },
      ),
    );
  }

  void _stopDemoBusiness() {
    if (_runtimeExiting) return;
    _runtimeExiting = true;
    for (final feed in _ownedConversationFeeds.toList()) {
      feed.requestClose();
    }
    _lspActivityTimer?.cancel();
    _lspActivityTimer = null;
    for (final entry in _acpInstallTimers.entries.toList()) {
      entry.value.cancel();
      final operation = _acpInstalls[entry.key]?.operationId;
      if (operation != null) {
        _publishInstall(
          entry.key,
          AcpInstallCancelledState(operationId: operation),
        );
      }
    }
    _acpInstallTimers.clear();
    _modelSyncs.clear();
    for (final thread in _promptGenerations.keys.toList()) {
      _promptGenerations[thread] = _promptGenerations[thread]! + 1;
    }
    for (final delay in _demoDelays.toList()) {
      delay.cancel();
    }
  }

  Future<void> _joinDemoBusiness() =>
      _demoBusinessStopped ??= Future.wait(_demoJobs.toList())
          .then<void>((_) {});

  @override
  void sealForShutdown() {
    _accountAdmissionsSealed = true;
    _stopDemoBusiness();
    for (final observation in _accountObservations.keys.toList()) {
      observation.requestClose();
    }
  }

  @override
  Future<List<StudioShutdownIssue>> cancelDartSubscriptions({
    required int budgetMs,
  }) async {
    sealForShutdown();
    final deadline = DateTime.now().add(Duration(milliseconds: budgetMs));
    final issues = <StudioShutdownIssue>[];
    await Future.wait([
      () async {
        try {
          final remaining = deadline.difference(DateTime.now());
          await _joinDemoConversations().timeout(
            remaining > Duration.zero
                ? remaining
                : const Duration(microseconds: 1),
          );
        } catch (_) {
          issues.add(
            const StudioShutdownIssue(
              stage: 'demo-conversation',
              code: 'closeFailed',
              message: 'Demo conversation handles did not close',
              retryable: true,
              correlationId: 'demo-conversation-close',
            ),
          );
        }
      }(),
      () async {
        try {
          final remaining = deadline.difference(DateTime.now());
          await _joinDemoBusiness().timeout(
            remaining > Duration.zero
                ? remaining
                : const Duration(microseconds: 1),
          );
        } catch (_) {
          issues.add(
            const StudioShutdownIssue(
              stage: 'demo-business',
              code: 'joinFailed',
              message: 'Demo business tasks did not stop',
              retryable: true,
              correlationId: 'demo-business-close',
            ),
          );
        }
      }(),
      for (final observation in _accountObservations.keys.toList())
        () async {
          try {
            final remaining = deadline.difference(DateTime.now());
            await observation.close().timeout(
              remaining > Duration.zero
                  ? remaining
                  : const Duration(microseconds: 1),
            );
          } catch (_) {
            issues.add(
              const StudioShutdownIssue(
                stage: 'demo-account-observation',
                code: 'closeFailed',
                message: 'Account observation did not close',
                retryable: true,
                correlationId: 'demo-account-close',
              ),
            );
          }
        }(),
    ]);
    return [...issues, ..._demoBusinessIssues];
  }

  @override
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target,
  ) async {
    if (_accountAdmissionsSealed) {
      throw StateError('Demo account observation is closed');
    }
    late final DemoAccountObservation observation;
    observation = DemoAccountObservation(
      read: () => _readAccountDomain(target),
      onClosed: () {
        _accountObservations.remove(observation);
      },
    );
    _accountObservations[observation] = target;
    return observation;
  }

  @override
  Future<AccountDomainFrame> readAccountDomain(
    AccountObservationTarget target,
  ) async => _readAccountDomain(target);

  NativeAccountDetails _nativeDetails(AccountSettingsView account) =>
      NativeAccountDetails(
        identity: NativeAccountIdentity(account.id),
        name: account.name,
        protocol: account.protocol,
        templateId: account.templateId,
        baseUrl: account.baseUrl,
        hasBearerToken: account.hasBearerToken,
        credentialRequired: account.credentialRequired,
        usageQueryRevision: account.usageQueryRevision,
        customModels: [
          for (final model in account.models.where(
            (model) => model.origin == ModelOrigin.manual,
          ))
            AccountModelCommand(
              modelId: model.modelId,
              displayName: model.displayName,
              wireApi: model.wireApi,
              contextWindow: model.contextWindow,
              maxOutputTokens: model.maxOutputTokens,
            ),
        ],
      );

  AccountDomainFrame _readAccountDomain(AccountObservationTarget target) {
    final accounts = _accounts ?? [_demoDefaultAccount()];
    switch (target) {
      case AccountSummariesTarget():
        return AccountSummariesFrame(
          _demoStamp('settings', _settingsRevision),
          [
            for (final account in accounts)
              AccountSummary(
                identity: NativeAccountIdentity(account.id),
                name: account.name,
                brandKey: account.templateId,
                displayEndpoint: null,
                isDefault:
                    account.id ==
                    (_defaultAccountId ?? accounts.firstOrNull?.id),
                billingKind: account.billingKind,
                billingKindOverride: account.billingKindOverride,
                credentialReady:
                    account.hasBearerToken || !account.credentialRequired,
                usageQueryRevision: account.usageQueryRevision,
                capabilities: AccountCapabilities(
                  setDefault: true,
                  edit: true,
                  remove: true,
                  queryUsage:
                      _accountCatalog
                          .template(account.templateId ?? '')
                          ?.supportsUsageQuery ==
                      true,
                  syncModels: account.modelCatalog.supported,
                  editModels: true,
                  acpAuth: false,
                ),
              ),
            for (final account in _acpAccounts)
              AccountSummary(
                identity: AcpAccountIdentity(account.accountId),
                name: account.name,
                brandKey: account.provider.wire,
                displayEndpoint: null,
                isDefault: false,
                acpConnectionRevision: account.connectionRevision,
                capabilities: const AccountCapabilities(
                  setDefault: false,
                  edit: true,
                  remove: true,
                  queryUsage: false,
                  syncModels: false,
                  editModels: false,
                  acpAuth: true,
                ),
              ),
          ],
        );
      case AccountDetailTarget(:final identity):
        final AccountDetails? detail;
        switch (identity) {
          case NativeAccountIdentity(:final accountId):
            final account = accounts
                .where((account) => account.id == accountId)
                .firstOrNull;
            detail = account == null ? null : _nativeDetails(account);
          case AcpAccountIdentity(:final accountId):
            final account = _acpAccounts
                .where((account) => account.accountId == accountId)
                .firstOrNull;
            detail = account == null ? null : AcpAccountDetails(account);
        }
        final native = identity is NativeAccountIdentity
            ? accounts
                  .where((account) => account.id == identity.accountId)
                  .firstOrNull
            : null;
        return AccountDetailFrame(
          _demoStamp('settings', _settingsRevision),
          identity,
          detail,
          modelConfiguration: native == null
              ? null
              : AccountModelConfiguration(
                  modelEnabledOverrides: native.modelEnabledOverrides,
                  connections: {
                    for (final entry in native.modelConnectionModes.entries)
                      entry.key: switch (entry.value) {
                        'http' => AccountConnectionMode.http,
                        'web_socket' => AccountConnectionMode.webSocket,
                        final mode => throw FormatException(
                          'Unknown demo connection: $mode',
                        ),
                      },
                  },
                  autoCompactLimits: {
                    for (final compact in native.autoCompactLimits.entries)
                      compact.key: ?compact.value.overrideLimit,
                  },
                ),
        );
      case AccountModelsTarget(:final identity):
        final account = accounts
            .where((account) => account.id == identity.accountId)
            .firstOrNull;
        return AccountModelsFrame(
          _demoStamp('model-catalog', _modelCatalogRevision),
          identity,
          account == null
              ? null
              : AccountModelCatalog(
                  identity: identity,
                  models: account.models,
                  status: account.modelCatalog,
                ),
        );
      case AccountUsageTarget():
        return AccountUsageFrame(
          _demoStamp('account-usage', _accountUsageRevision),
          [
            for (final account in accounts)
              if (_usageFacts[NativeAccountIdentity(account.id)]
                  case final usage?
                  when usage.queryRevision == account.usageQueryRevision)
                usage
              else
                AccountUsageObservation(
                  identity: NativeAccountIdentity(account.id),
                  queryRevision: account.usageQueryRevision,
                  revision: _accountUsageRevision,
                  phase: AccountUsagePhase.unchecked,
                ),
          ],
        );
      case AcpAuthTarget():
        return AcpAuthFrame(
          _demoStamp('acp-auth', _demoAcpAuth.snapshot.revision),
          _demoAcpAuth.snapshot,
        );
      case AcpInstallTarget():
        return AcpInstallFrame(
          _demoStamp('acp-install', _demoInstallSnapshot().revision),
          _demoInstallSnapshot(),
        );
    }
  }

  @override
  Future<AccountUsageFrame> queryAccountUsage(
    NativeAccountIdentity identity,
  ) async {
    _ensureDemoRunning();
    final account = (_accounts ?? [_demoDefaultAccount()])
        .where((account) => account.id == identity.accountId)
        .firstOrNull;
    if (account == null) throw ArgumentError('Account is unavailable');
    _accountUsageRevision++;
    _usageFacts[identity] = AccountUsageObservation(
      identity: identity,
      queryRevision: account.usageQueryRevision,
      revision: _accountUsageRevision,
      phase: account.hasBearerToken || !account.credentialRequired
          ? AccountUsagePhase.unsupported
          : AccountUsagePhase.missingCredential,
    );
    _publishProductPayload(
      AccountUsageStateChangedPayload(_demoAccountUsageState()),
    );
    return _readAccountDomain(const AccountUsageTarget()) as AccountUsageFrame;
  }

  @override
  Future<SettingsCommandReply> patchAccount(
    int revision,
    PatchAccountCommand command, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(revision);
    final current = before.accounts
        .where((account) => account.id == command.identity.accountId)
        .firstOrNull;
    if (current == null) throw ArgumentError('Account is unavailable');
    final templateId = switch (command.templateId) {
      AccountTextKeep() => current.templateId,
      AccountTextSet(:final value) => value,
      AccountTextRestore() => null,
    };
    final template = _accountCatalog.template(templateId ?? '');
    String text(AccountTextPatch patch, String current, String? initial) =>
        switch (patch) {
          AccountTextKeep() => current,
          AccountTextSet(:final value) => value,
          AccountTextRestore() =>
            initial ?? (throw ArgumentError('No applicable template default')),
        };
    final manual = switch (command.customModels) {
      AccountModelsKeep() =>
        current.models
            .where((model) => model.origin == ModelOrigin.manual)
            .toList(),
      AccountModelsRestore() => <AccountModelView>[],
      AccountModelsSet(:final models) => [
        for (final model in models)
          AccountModelView(
            modelId: model.modelId,
            displayName: model.displayName,
            reasoningEfforts: const [],
            wireApi: model.wireApi,
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            origin: ModelOrigin.manual,
          ),
      ],
    };
    final removed = current.models
        .where(
          (model) =>
              model.origin == ModelOrigin.manual &&
              !manual.any((next) => next.modelId == model.modelId),
        )
        .map((model) => model.modelId)
        .toSet();
    final next = current.copyWith(
      name: text(command.name, current.name, template?.displayName),
      baseUrl: text(command.baseUrl, current.baseUrl, template?.baseUrl),
      protocol: text(command.protocol, current.protocol, template?.protocol),
      templateId: templateId,
      hasBearerToken: switch (command.secret.action) {
        AccountSecretAction.preserve => current.hasBearerToken,
        AccountSecretAction.clear => false,
        AccountSecretAction.replace =>
          command.secret.value?.isEmpty != false
              ? current.hasBearerToken
              : true,
      },
      models: [
        for (final model in current.models)
          if (model.origin != ModelOrigin.manual) model,
        ...manual,
      ],
      modelEnabledOverrides: {...current.modelEnabledOverrides}
        ..removeWhere((id, _) => removed.contains(id)),
      modelConnectionModes: {...current.modelConnectionModes}
        ..removeWhere((id, _) => removed.contains(id)),
      autoCompactLimits: {...current.autoCompactLimits}
        ..removeWhere((id, _) => removed.contains(id)),
      usageQueryRevision:
          command.baseUrl is AccountTextKeep &&
              command.protocol is AccountTextKeep &&
              command.templateId is AccountTextKeep &&
              command.secret.action == AccountSecretAction.preserve
          ? current.usageQueryRevision
          : ++_usageIdentitySequence,
    );
    _accounts = [
      for (final account in before.accounts)
        account.id == current.id ? next : account,
    ];
    _settingsRevision++;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> setAccountModelAutoCompact(
    int revision,
    AccountModelIdentity identity,
    AutoCompactIntent intent, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(revision);
    final current = before.accounts
        .where((account) => account.id == identity.accountId)
        .firstOrNull;
    if (current == null ||
        !current.models.any((model) => model.modelId == identity.modelId)) {
      throw ArgumentError('Account model is unavailable');
    }
    final next = current.withAutoCompactLimit(
      AccountModelAutoCompactView(
        modelId: identity.modelId,
        overrideLimit: switch (intent) {
          SetAutoCompactLimit(:final limit) => limit,
          ClearAutoCompactLimit() => null,
        },
      ),
    );
    _accounts = [
      for (final account in before.accounts)
        account.id == current.id ? next : account,
    ];
    _settingsRevision++;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> setAccountModelConnection(
    int revision,
    AccountModelIdentity identity,
    ModelConnectionIntent intent, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(revision);
    final current = before.accounts
        .where((account) => account.id == identity.accountId)
        .firstOrNull;
    final model = current?.models
        .where((model) => model.modelId == identity.modelId)
        .firstOrNull;
    if (current == null || model == null) {
      throw ArgumentError('Account model is unavailable');
    }
    final mode = switch (intent) {
      SetModelConnection(:final mode) =>
        mode == AccountConnectionMode.http ? 'http' : 'web_socket',
      ClearModelConnection() => model.defaultConnectionMode,
    };
    if (!model.supportedConnectionModes.contains(mode)) {
      throw ArgumentError('Model connection is unsupported');
    }
    final overrides = {...current.modelConnectionModes};
    if (intent is ClearModelConnection) {
      overrides.remove(identity.modelId);
    } else {
      overrides[identity.modelId] = mode;
    }
    _accounts = [
      for (final account in before.accounts)
        account.id == current.id
            ? current.copyWith(
                modelConnectionModes: overrides,
                models: [
                  for (final candidate in current.models)
                    candidate.modelId == identity.modelId
                        ? candidate.copyWith(connectionMode: mode)
                        : candidate,
                ],
              )
            : account,
    ];
    _settingsRevision++;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<ModelSyncAdmission> syncAccountModels(
    NativeAccountIdentity identity, {
    required OperationId operationId,
  }) async {
    _ensureDemoRunning();
    final account = (_accounts ?? [_demoDefaultAccount()])
        .where((account) => account.id == identity.accountId)
        .firstOrNull;
    if (account == null || !account.modelCatalog.supported) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Account model discovery is unsupported',
        retryable: false,
        correlationId: 'demo-model-sync',
      );
    }
    final running = _modelSyncs[identity];
    if (running != null) {
      return ModelSyncAdmission(
        operationId: running.operationId,
        account: identity,
        queryGeneration: running.queryGeneration,
        joinedExisting: true,
      );
    }
    final admission = ModelSyncAdmission(
      operationId: operationId,
      account: identity,
      queryGeneration: ++_modelQuerySequence,
      joinedExisting: false,
    );
    _modelSyncs[identity] = admission;
    void publish(bool probing) {
      _accounts = [
        for (final item in _accounts ?? [_demoDefaultAccount()])
          item.id == identity.accountId
              ? item.copyWith(
                  modelCatalog: ModelCatalogStatusView(
                    supported: true,
                    source: item.modelCatalog.source,
                    probing: probing,
                    operationId: operationId.value,
                    queryGeneration: admission.queryGeneration,
                    lastSuccessAt: item.modelCatalog.lastSuccessAt,
                    checkedAt: item.modelCatalog.checkedAt,
                    error: item.modelCatalog.error,
                    cacheWarning: item.modelCatalog.cacheWarning,
                  ),
                )
              : item,
      ];
      _modelCatalogRevision++;
      _publishProductPayload(
        ModelCatalogStateChangedPayload(_demoSettingsState()),
      );
    }

    publish(true);
    _runDemoJob(() async {
      await Future<void>.value();
      if (_runtimeExiting) return;
      if (identical(_modelSyncs[identity], admission)) {
        publish(false);
        _modelSyncs.remove(identity);
      }
    });
    return admission;
  }

  /// 是否周期推进 demo LSP 索引活动；GUI demo 构建开启，测试默认关闭保持确定性。
  final bool lspActivityLoop;

  /// 每 topic 的 typed fanout 接收者：receiver 先登记其 sink，再取得该 topic 基线；
  /// 无关领域不进入该 receiver 的缓冲。发布只走已登记 sink，不做全局 mixed bus。
  final Map<ProductTopic, Set<void Function(ProductTopicEventPayload)>>
  _topicSinks = {};
  final String _ownerEpoch = 'demo:${newStudioCorrelationId()}';
  int _productEventSequence = 0;
  int _threadDirectoryRevision = 0;
  int _agentProfilesRevision = 0;
  final Map<String, Set<_DemoConversationFeed>> _conversationFeeds = {};
  // 受管句柄不等于 GUI demand：未监听句柄和迟到 factory 也有真实关闭责任。
  final Set<ConversationFeed> _ownedConversationFeeds =
      Set<ConversationFeed>.identity();
  final Set<Future<void>> _openingConversationFeeds = {};
  final Map<ConversationFeed, Future<void>> _conversationCloses =
      Map<ConversationFeed, Future<void>>.identity();

  Future<void> _closeDemoConversation(ConversationFeed feed) {
    final existing = _conversationCloses[feed];
    if (existing != null) return existing;
    final joined = Completer<void>();
    _conversationCloses[feed] = joined.future;
    Future<void> closeOwned() async {
      try {
        feed.requestClose();
        await feed.close();
        _ownedConversationFeeds.remove(feed);
        joined.complete();
      } catch (error, stack) {
        // 失败 owner 仍留在 owned；只清本轮 in-flight，允许下次真实重试。
        joined.completeError(error, stack);
      } finally {
        _conversationCloses.remove(feed);
      }
    }

    unawaited(closeOwned());
    return joined.future;
  }

  Future<void> _joinDemoConversations() async {
    await Future.wait([
      for (final feed in _ownedConversationFeeds.toList())
        _closeDemoConversation(feed),
      ..._openingConversationFeeds,
    ]);
    // 迟到 factory 自己汇合其返回的 owner。失败 owner 留在集合供下次 cleanup。
    if (_ownedConversationFeeds.isNotEmpty) {
      throw StateError('Demo conversation close still has unresolved owners');
    }
  }

  final _shutdownEvents = StreamController<StudioShutdownProgress>.broadcast();

  /// 每个 Thread 的内存条目：正文不属于 Thread 状态，只由内容连接按页/尾部交付。
  final Map<String, List<ConversationItem>> _threadItems = {};

  /// 每个 Thread 自己的内容版本；与 Thread 状态 revision、持久化水位无关。
  final Map<String, int> _contentVersions = {};
  Timer? _lspActivityTimer;
  final Map<String, ThreadWorkspace> _workspaces = {};
  final Map<String, int> _promptGenerations = {};

  /// 每个会话当前的继续点投影；demo 用它模拟「还有未完成工作」。
  final Map<String, ContinuationView> _demoContinuationPoints = {};
  final Map<String, _DemoContinuation> _demoContinuations = {};
  int _continuationSequence = 0;
  final Map<String, ThreadModeId> _threadModes = {};
  int _threadModeCatalogRevision = 1;
  final Set<String> _readOnlyModeIds = {'mode.simple', 'mode.task'};
  final Map<String, ModeDocument> _modeDocuments = {
    'mode.simple': const ModeDocument(
      definition: ModeDefinition(
        id: 'mode.simple',
        displayName: '简洁',
        description: '直接对话',
        order: 0,
        prompt: '直接回答用户请求。',
      ),
    ),
    'mode.task': const ModeDocument(
      definition: ModeDefinition(
        id: 'mode.task',
        displayName: '任务',
        description: '通过工作流完成任务',
        order: 1,
        prompt: '按工作流推进任务并确认阶段完成。',
        workflow: _demoTaskWorkflow,
      ),
    ),
  };
  final Map<String, AttachmentDraftView> _attachmentDrafts = {};
  final Set<String> _archivedProjectIds = {};
  final Map<String, String> _projectNames = {};
  final Set<String> _archivedThreadIds = {};
  final Map<
    String,
    ({
      PendingInteraction interaction,
      Object resolution,
      StudioCommandReceipt receipt,
    })
  >
  _resolvedInteractions = {};
  final List<StudioThread> _createdRootThreads = [];
  final List<StudioThread> _pageFillThreads = [];
  final List<SshServer> _sshServers = [
    const SshServer(
      alias: 'arm-dev',
      hostName: '192.168.100.12',
      port: 22,
      username: 'root',
      managed: true,
    ),
    const SshServer(
      alias: 'handwritten',
      hostName: '203.0.113.10',
      port: 2222,
      username: 'deploy',
      managed: false,
    ),
  ];

  /// Driver 模式注入的历史会话数量；普通 demo 为 0。
  int get directoryPageFillCount => 0;

  List<AccountSettingsView>? _accounts;
  String? _defaultAccountId;
  List<ModeModelRouteView>? _modeRoutes;
  List<RoleSettingsView>? _roles;
  InstructionsSettingsView _instructions = const InstructionsSettingsView();
  SkillsSettingsView _skills = const SkillsSettingsView();
  GeneralSettingsView _general = const GeneralSettingsView();
  DelegationSettingsView _delegation = const DelegationSettingsView();
  WebSearchSettingsView _webSearch = const WebSearchSettingsView(
    effectiveMode: 'disabled',
    availability: 'available',
    accountId: 'openai',
    modelId: 'gpt-5',
  );
  DeepSeekWebSearchSettingsView _deepSeekWebSearch =
      const DeepSeekWebSearchSettingsView(
        effectiveEnabled: true,
        configuredFetchEnabled: true,
        effectiveFetchEnabled: true,
        availability: 'available',
        accountId: 'deepseek-primary',
      );
  PermissionMode _permissionMode = PermissionMode.requestApproval;
  int _turnSequence = 0;
  int _threadSequence = 0;
  int _settingsRevision = 1;
  int _attachmentSequence = 0;
  int _skillsRevision = 1;
  int _accountUsageRevision = 1;
  List<AcpAccountSettingsView> _acpAccounts = const [];
  final DemoAcpAuth _demoAcpAuth = DemoAcpAuth();
  int _acpInstallRevision = 0;
  final Map<AcpProviderView, AcpInstallStateView> _acpInstalls = {};
  final Map<AcpProviderView, Timer> _acpInstallTimers = {};
  int _mcpRevision = 0;
  int _lspRevision = 0;
  int? _lspActivityPercentage = 40;
  int _projectDirectoryRevision = 1;
  final Set<String> _disabledSystemAgents = <String>{};
  final Map<String, AgentProfileView> _userAgentProfiles = {};
  final List<StudioProject> _openedRemoteProjects = [];
  StudioProject? _standaloneProject;

  Iterable<StudioProject> get _standaloneProjects {
    final project = _standaloneProject;
    return project == null ? const <StudioProject>[] : [project];
  }

  String? _selectedProjectId;
  String? _selectedThreadId;
  DateTime? _fixtureNow;
  int _botsRevision = 0;
  final List<BotSnapshot> _bots = [];
  BotRegistrationAttempt? _registration;
  final List<BotPendingCredentialOperation> _pendingCredentialOps = [];
  final Map<String, List<BotConversation>> _botConversations = {};
  final Map<String, List<BotMessage>> _botMessages = {};
  final Map<String, BotConversationThreadBinding> _botBindings = {};

  Duration get promptStartDelay => const Duration(milliseconds: 120);

  Duration get promptActivityDelay => const Duration(milliseconds: 350);

  Duration get promptToolDelay => const Duration(milliseconds: 500);

  /// 模拟关机每个阶段的停留时长。
  Duration get shutdownPhaseDelay => const Duration(milliseconds: 80);

  /// demo LSP 索引活动每个步进的停留时长。
  Duration get lspActivityStepDelay => const Duration(seconds: 2);

  @override
  Stream<StudioShutdownProgress> subscribeShutdownProgress() {
    return _shutdownEvents.stream;
  }

  @override
  Future<void> beginRuntimeExit({required int remainingMs}) async {
    sealForShutdown();
    await _joinDemoBusiness().timeout(
      Duration(milliseconds: remainingMs > 0 ? remainingMs : 1),
    );
  }

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    StudioExitIntent intent = StudioExitIntent.exit,
  }) => _demoShutdown ??= _shutdownDemo(
    remainingMs: remainingMs,
    externalIssues: externalIssues,
  );

  Future<StudioExitReport> _shutdownDemo({
    required int remainingMs,
    required List<StudioShutdownIssue> externalIssues,
  }) async {
    final ownIssues = await cancelDartSubscriptions(budgetMs: remainingMs);
    final issues = [...externalIssues, ...ownIssues];
    for (final phase in StudioShutdownPhase.values) {
      if (shutdownPhaseDelay > Duration.zero) {
        await Future<void>.delayed(shutdownPhaseDelay);
      }
      if (phase == StudioShutdownPhase.flushingPersistence) {
        _emitShutdownProgress(
          const FlushingPersistenceProgress(pendingCommits: 3),
        );
        if (shutdownPhaseDelay > Duration.zero) {
          await Future<void>.delayed(shutdownPhaseDelay);
        }
        _emitShutdownProgress(
          const FlushingPersistenceProgress(pendingCommits: 0),
        );
        continue;
      }
      _emitShutdownProgress(_demoShutdownProgress(phase));
    }
    await _shutdownEvents.close();
    // Demo 的确定性结局：所有阶段成功且持久化已排空。外部（Dart）取消 issue 是本次关闭
    // 的最终成功前置条件，只要存在就如实为 Degraded，绝不伪 Clean。
    if (issues.isEmpty) {
      return const StudioExitReport(
        shutdown: StudioShutdownReport(
          outcome: StudioShutdownOutcome.clean,
          issues: [],
          persistence: DrainedStudioPendingPersistence(),
        ),
      );
    }
    return StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: StudioShutdownOutcome.degraded,
        issues: issues,
        persistence: const DrainedStudioPendingPersistence(),
      ),
    );
  }

  void _emitShutdownProgress(StudioShutdownProgress progress) {
    _shutdownEvents.add(progress);
  }

  StudioShutdownProgress _demoShutdownProgress(StudioShutdownPhase phase) {
    return switch (phase) {
      StudioShutdownPhase.stoppingSubscriptions =>
        const StoppingSubscriptionsProgress(),
      StudioShutdownPhase.cancellingTurns => const CancellingTurnsProgress(),
      StudioShutdownPhase.flushingPersistence =>
        const FlushingPersistenceProgress(pendingCommits: 0),
      StudioShutdownPhase.stoppingAgents => const StoppingAgentsProgress(),
      StudioShutdownPhase.stoppingMcp => const StoppingMcpProgress(),
      StudioShutdownPhase.stoppingLsp => const StoppingLspProgress(),
      StudioShutdownPhase.stopped => const StoppedProgress(),
    };
  }

  @override
  Future<StudioBootstrap> readBootstrap() async {
    // Bootstrap only assembles independently versioned owner snapshots. Normal
    // commands and topic baselines query their own domain directly.
    final projects = _demoProjectDirectory();
    final threads = _demoThreadDirectory();
    final selectedProjectId =
        projects.values
            .where((project) => project.id == _selectedProjectId)
            .firstOrNull
            ?.id ??
        projects.values.firstOrNull?.id;
    final selectedThreadId = _sortedDirectoryThreads()
        .where(
          (thread) =>
              thread.id == _selectedThreadId &&
              thread.projectId == selectedProjectId,
        )
        .firstOrNull
        ?.id;
    return StudioBootstrap(
      ownerEpoch: _ownerEpoch,
      projectDirectory: projects,
      threadDirectory: threads,
      agentDirectory: _demoAgentDirectory(),
      settingsState: _demoSettingsState(),
      recoveryState: _demoRecoveryState(),
      mcpState: _demoMcpState(),
      lspState: _demoLspState(),
      skillsByProject: {
        for (final project in projects.values)
          project.id: _demoSkillsState(project.id, _skillsRevision),
      },
      threadModeCatalog: _demoThreadModeCatalog(),
      updaterState: _demoUpdaterState(),
      persistenceState: _demoPersistenceState(),
      persistenceQueueState: _demoPersistenceQueueState(),
      agentProfilesState: readAgentProfilesStateSync(),
      sessionCostsByRoot: {
        for (final root in _sortedDirectoryThreads().where(
          (thread) => thread.isRoot,
        ))
          root.id: _demoSessionCosts(root.id),
      },
      selectedProjectId: selectedProjectId,
      selectedThreadId: selectedThreadId,
    );
  }

  DateTime get _fixtureTime => _fixtureNow ??= DateTime.now();

  ThreadModeCatalogView _demoThreadModeCatalog() {
    final documents = _modeDocuments.values.toList()
      ..sort((left, right) {
        final byOrder = left.definition.order.compareTo(right.definition.order);
        return byOrder != 0
            ? byOrder
            : left.definition.id.compareTo(right.definition.id);
      });
    return ThreadModeCatalogView(
      revision: _threadModeCatalogRevision,
      modes: [
        for (final document in documents)
          ThreadModeDescriptorView(
            id: document.definition.id,
            displayName: document.definition.displayName,
            description: document.definition.description,
            order: document.definition.order,
            hasWorkflow: document.definition.workflow != null,
            readOnly: _readOnlyModeIds.contains(document.definition.id),
          ),
      ],
    );
  }

  ProjectDirectoryState _demoProjectDirectory() {
    final fixture = _ensureWorkspaceFixture();
    final projects =
        [fixture.project, ..._openedRemoteProjects, ..._standaloneProjects]
            .where((project) => !_archivedProjectIds.contains(project.id))
            .map(
              (project) => StudioProject(
                id: project.id,
                name: _projectNames[project.id] ?? project.name,
                path: project.path,
                kind: project.kind,
                sshAlias: project.sshAlias,
              ),
            )
            .toList();
    return ProjectDirectoryState.fromState(
      state: _demoReadyResource(_projectDirectoryRevision, projects),
    );
  }

  ThreadDirectoryWindow _demoThreadDirectory() {
    final directory = _sortedDirectoryThreads();
    return ThreadDirectoryWindow(
      threads: directory.take(directoryPageSize).toList(),
      nextCursor: directory.length > directoryPageSize
          ? _demoDirectoryCursor(directoryPageSize - 1)
          : null,
      hasMore: directory.length > directoryPageSize,
      revision: _threadDirectoryRevision,
    );
  }

  ThreadDirectoryPage _demoDirectoryPage() {
    final window = _demoThreadDirectory();
    return ThreadDirectoryPage(
      threads: window.threads,
      nextCursor: window.nextCursor,
      revision: window.revision,
    );
  }

  AgentDirectoryState _demoAgentDirectory() =>
      AgentDirectoryState.fromState(state: _demoInitialResource());

  RecoveryStateSnapshot _demoRecoveryState() =>
      RecoveryStateSnapshot.fromState(state: _demoInitialResource());

  AccountSettingsView _demoDefaultAccount() {
    final template = _accountCatalog.templates.first;
    return _accountsFromCreateCommands([
      CreateAccountCommand(
        identity: NativeAccountIdentity(template.id),
        name: template.displayName,
        protocol: template.protocol,
        templateId: template.id,
        baseUrl: template.baseUrl,
        secret: const AccountSecretCommand.preserve(),
      ),
    ], catalog: _accountCatalog).single.copyWith(
      hasBearerToken: true,
      status: 'ready',
      updatedAt: 'Loaded',
    );
  }

  SettingsStateSnapshot _demoSettingsState() {
    final defaultAccount = _demoDefaultAccount();
    final defaultModel = defaultAccount.models
        .where((model) => model.modelId == defaultAccount.defaultModelId)
        .firstOrNull;
    final effort = defaultModel?.defaultReasoningEffort;
    final resolvedEffort = effort?.isNotEmpty == true
        ? effort!
        : defaultModel?.reasoningEfforts.firstOrNull ?? '';
    return _settingsSnapshot(
      accounts: _accounts ?? [defaultAccount],
      modeRoutes:
          _modeRoutes ??
          [
            for (final mode in [ThreadModeId.simple, ThreadModeId.task])
              ModeModelRouteView(
                modeId: mode,
                accountId: defaultAccount.id,
                modelId: defaultAccount.defaultModelId,
                effort: resolvedEffort,
              ),
          ],
      roles:
          _roles ??
          [
            for (final role in const [
              'explorer',
              'executor',
              'worktree_executor',
              'reviewer',
            ])
              RoleSettingsView(
                key: role,
                accountId: defaultAccount.id,
                modelId: defaultAccount.defaultModelId,
                effort: resolvedEffort,
              ),
          ],
    );
  }

  AccountUsageStateSnapshot _demoAccountUsageState() {
    final accounts = _accounts ?? [_demoDefaultAccount()];
    final usages = [for (final account in accounts) _demoAccountUsage(account)];
    return AccountUsageStateSnapshot.fromState(
      state: _demoReadyResource(
        _accountUsageRevision,
        AccountUsageStateData(configFingerprint: 'demo', usages: usages),
      ),
    );
  }

  SessionCostsStateView _demoSessionCosts(String rootThreadId) =>
      SessionCostsStateView(
        rootThreadId: rootThreadId,
        revision: rootThreadId == 'thread-main' || rootThreadId == 'thread-alt'
            ? 1
            : 0,
        updatedAt: _fixtureTime,
        cost: switch (rootThreadId) {
          'thread-main' => const SessionCostView(
            rootThreadId: 'thread-main',
            estimatedCosts: [
              RuntimeCostView(currency: 'CNY', amount: 0.14),
              RuntimeCostView(currency: 'USD', amount: 0.02),
            ],
            hasUnpricedUsage: false,
          ),
          'thread-alt' => const SessionCostView(
            rootThreadId: 'thread-alt',
            estimatedCosts: [],
            hasUnpricedUsage: true,
          ),
          _ => null,
        },
      );

  UpdaterStateSnapshot _demoUpdaterState() => UpdaterStateSnapshot.idle(
    revision: 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  PersistenceStateSnapshot _demoPersistenceState() =>
      const PersistenceStateSnapshot.ready();

  PersistenceQueueStateView _demoPersistenceQueueState() =>
      const PersistenceQueueStateView(
        revision: 0,
        queue: PersistenceQueueSnapshot.empty(),
      );

  ThreadWorkspace _demoWorkspace(String threadId) {
    _ensureWorkspaceFixture();
    final workspace = _workspaces[threadId];
    if (workspace == null) throw StateError('unknown demo thread $threadId');
    return workspace;
  }

  SettingsStateSnapshot _settingsSnapshot({
    required List<AccountSettingsView> accounts,
    required List<ModeModelRouteView> modeRoutes,
    required List<RoleSettingsView> roles,
  }) {
    return SettingsStateSnapshot.fromState(
      state: _demoReadyResource(
        _settingsRevision,
        SettingsStateData(
          modelCatalogRevision: _modelCatalogRevision,
          accounts: accounts,
          acpAccounts: _acpAccounts,
          defaultAccountId: _defaultAccountId ?? accounts.firstOrNull?.id,
          modeModelRoutes: modeRoutes,
          roles: roles,
          instructions: _instructions,
          skills: _skills,
          general: _general,
          delegation: _delegation,
          webSearch: _webSearch,
          deepSeekWebSearch: _deepSeekWebSearch,
          permissionMode: _permissionMode,
        ),
      ),
    );
  }

  ModeModelRouteView _demoModeRoute(ThreadModeId mode) {
    final saved =
        _modeRoutes?.where((route) => route.modeId == mode).firstOrNull ??
        _modeRoutes
            ?.where((route) => route.modeId == ThreadModeId.simple)
            .firstOrNull;
    if (saved != null) return saved;
    final template = _accountCatalog.templates.first;
    final models = _accountCatalog.modelsFor(template.modelCatalogId);
    final model =
        models
            .where(
              (candidate) => candidate.modelId == template.suggestedModelId,
            )
            .firstOrNull ??
        models.first;
    return ModeModelRouteView(
      modeId: mode,
      accountId: template.id,
      modelId: model.modelId,
      effort: model.defaultReasoningEffort.isNotEmpty
          ? model.defaultReasoningEffort
          : model.reasoningEfforts.firstOrNull ?? '',
    );
  }

  ({StudioProject project, List<StudioThread> threads})
  _ensureWorkspaceFixture() {
    final now = _fixtureNow ??= DateTime.now();
    const project = StudioProject(
      id: 'project-local',
      name: 'pure-lang',
      path: r'C:\Projects\pure-lang',
    );
    final rootMode = _threadModes['thread-main'] ?? ThreadModeId.simple;
    final reviewerMode = _threadModes['thread-reviewer'] ?? ThreadModeId.simple;
    final alternateMode = _threadModes['thread-alt'] ?? ThreadModeId.simple;
    final root = StudioThread(
      id: 'thread-main',
      projectId: project.id,
      title: 'Flutter + FRB 重构',
      mode: rootMode,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      role: 'planner',
      createdAt: now.subtract(const Duration(minutes: 10)),
      updatedAt: now,
      lastUserMessageAt: now,
      agentPath: 'root',
      workspacePath: project.path,
    );
    final reviewer = StudioThread(
      id: 'thread-reviewer',
      projectId: project.id,
      title: 'Driver reviewer',
      mode: reviewerMode,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      createdAt: now.subtract(const Duration(minutes: 7)),
      updatedAt: now.subtract(const Duration(minutes: 7)),
      parentThreadId: root.id,
      rootThreadId: root.id,
      agentPath: 'root/reviewer',
      role: 'reviewer',
      status: ThreadStatusView.waitingInteraction,
      workspacePath: project.path,
    );
    final alternate = StudioThread(
      id: 'thread-alt',
      projectId: project.id,
      title: 'Riverpod selector audit',
      mode: alternateMode,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      role: 'planner',
      createdAt: now.subtract(const Duration(minutes: 3)),
      updatedAt: now.subtract(const Duration(minutes: 3)),
      agentPath: 'root-alt',
      workspacePath: project.path,
    );
    _workspaces.putIfAbsent(root.id, () => _rootWorkspace(root, now));
    _workspaces.putIfAbsent(
      reviewer.id,
      () => _singleMessageWorkspace(
        reviewer,
        'Driver agent workspace selected.',
        'reviewer/model',
        now.subtract(const Duration(minutes: 6)),
      ),
    );
    _workspaces.putIfAbsent(
      alternate.id,
      () => _singleMessageWorkspace(
        alternate,
        'Riverpod selector boundary is isolated.',
        'future-model',
        now.subtract(const Duration(minutes: 2)),
      ),
    );
    _workspaces[root.id] = _workspaces[root.id]!.copyWith(thread: root);
    _workspaces[reviewer.id] = _workspaces[reviewer.id]!.copyWith(
      thread: reviewer,
    );
    _workspaces[alternate.id] = _workspaces[alternate.id]!.copyWith(
      thread: alternate,
    );
    final threads = [root, reviewer, alternate, ..._createdRootThreads]
        .where(
          (thread) =>
              !_archivedThreadIds.contains(thread.id) &&
              !_archivedThreadIds.contains(thread.effectiveRootThreadId),
        )
        .toList();
    for (final thread in _createdRootThreads) {
      _workspaces.putIfAbsent(
        thread.id,
        () => ThreadWorkspace(
          thread: thread,
          revision: 0,
          interactions: const [],
          runtime: _emptyRuntimeView(),
        ),
      );
    }
    _ensurePageFillThreads(project.id, project.path, now);
    return (project: project, threads: threads);
  }

  /// Driver 模式的历史会话填充：保证触底分页有足够数据。
  void _ensurePageFillThreads(
    String projectId,
    String projectPath,
    DateTime now,
  ) {
    if (directoryPageFillCount <= 0 || _pageFillThreads.isNotEmpty) {
      return;
    }
    for (var index = 0; index < directoryPageFillCount; index++) {
      final updated = now.subtract(Duration(minutes: 30 + index * 17));
      final thread = StudioThread(
        id: 'thread-page-$index',
        projectId: projectId,
        title: '历史会话 ${index + 1}',
        mode: ThreadModeId.simple,
        delegationMode: DelegationMode.profile,
        delegationPreference: DelegationPreference.balanced,
        role: 'planner',
        createdAt: updated,
        updatedAt: updated,
        agentPath: 'root-page-$index',
        workspacePath: projectPath,
      );
      _pageFillThreads.add(thread);
      _workspaces.putIfAbsent(
        thread.id,
        () => ThreadWorkspace(
          thread: thread,
          revision: 0,
          interactions: const [],
          runtime: _emptyRuntimeView(),
        ),
      );
    }
  }

  /// 目录完整排序视图（最近用户消息时间倒序、id 倒序），分页窗口的模拟数据源。
  List<StudioThread> _sortedDirectoryThreads() {
    final fixture = _ensureWorkspaceFixture();
    final threads =
        [
              ...fixture.threads,
              ..._pageFillThreads.where(
                (thread) => !_archivedThreadIds.contains(thread.id),
              ),
            ]
            .where((thread) => !_archivedProjectIds.contains(thread.projectId))
            .toList()
          ..sort(StudioThread.compareDirectoryOrder);
    return threads;
  }

  @override
  Future<ThreadDirectoryPage> queryThreads(
    DirectoryQuery query, {
    String? cursor,
    int limit = 50,
  }) async {
    final projects = _demoProjectDirectory().values;
    final all = <String, StudioThread>{
      for (final thread in [
        ..._workspaces.values.map((w) => w.thread),
        ..._createdRootThreads,
        ..._pageFillThreads,
      ])
        thread.id: thread.copyWith(
          archived: _archivedThreadIds.contains(thread.effectiveRootThreadId),
        ),
    };
    final rows =
        all.values.where((thread) => query.matches(thread, projects)).toList()
          ..sort(StudioThread.compareDirectoryOrder);
    final offset = cursor == null ? 0 : int.parse(cursor);
    return ThreadDirectoryPage(
      threads: rows.skip(offset).take(limit).toList(),
      nextCursor: offset + limit < rows.length ? '${offset + limit}' : null,
      revision: _threadDirectoryRevision,
    );
  }

  @override
  Future<StudioThread> restoreThread(String threadId) async {
    _archivedThreadIds.remove(threadId);
    final restored = _sortedDirectoryThreads().firstWhere(
      (thread) => thread.id == threadId,
    );
    _emitThreadDirectoryUpdate(restored);
    return restored;
  }

  String _demoDirectoryCursor(int lastIndex) => 'demo:$lastIndex';

  @override
  Future<ThreadDirectoryPage> listThreadsPage({
    String? cursor,
    int limit = 50,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final directory = _sortedDirectoryThreads();
    final lastIndex = cursor == null
        ? -1
        : int.tryParse(cursor.replaceFirst('demo:', '')) ?? -1;
    final page = directory
        .skip(lastIndex + 1)
        .take(limit.clamp(1, 100))
        .toList();
    final nextLastIndex = lastIndex + page.length;
    return ThreadDirectoryPage(
      threads: page,
      nextCursor: nextLastIndex < directory.length - 1
          ? _demoDirectoryCursor(nextLastIndex)
          : null,
      revision: _threadDirectoryRevision,
    );
  }

  ThreadWorkspace _rootWorkspace(StudioThread thread, DateTime now) {
    final route = _demoModeRoute(thread.mode);
    final userCreatedAt = now.subtract(const Duration(minutes: 9));
    final agentCreatedAt = now.subtract(const Duration(minutes: 8));
    _threadItems[thread.id] = List.unmodifiable([
      _messageItem(
        id: 'turn-demo:user',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 0,
        channel: ThreadTextChannel.user,
        text:
            '用 Flutter 重构 anywork。\n\n'
            '- timeline 要像 Web 版一样即时渲染 Markdown\n'
            '- streaming 中的代码块和表格不要抖动',
        createdAt: userCreatedAt,
      ),
      _demoItem(
        id: 'turn-demo:reasoning',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 1,
        revision: 0,
        createdAt: agentCreatedAt,
        updatedAt: agentCreatedAt,
        content: _demoThinking(
          summary: const ['## 判断\n\nUI 只消费当前 Thread 的高频通知。'],
          content: const [],
          lifecycle: CompletedThreadContentView(agentCreatedAt),
        ),
      ),
      _demoItem(
        id: 'turn-demo:tool',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 2,
        revision: 0,
        createdAt: agentCreatedAt,
        updatedAt: agentCreatedAt,
        content: _demoTool(
          invocation: const ConversationToolInvocation(
            toolCallId: 'turn-demo:tool-call',
            name: 'cargo test -p pl-studio-bridge',
          ),
          lifecycle: ConversationToolSucceeded(
            completedAt: agentCreatedAt,
            output: const ConversationToolOutputDescriptor(attachments: []),
          ),
          result: '1 passed; bridge envelope uses typed payload.',
        ),
      ),
      _messageItem(
        id: 'turn-demo:final',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 4,
        channel: ThreadTextChannel.finalAnswer,
        text:
            '### Streaming Markdown preview\n\n'
            '正文、**加粗**、`inline code` 和链接都按 GFM 渲染。',
        createdAt: agentCreatedAt,
      ),
    ]);
    return ThreadWorkspace(
      thread: thread,
      revision: 1,
      interactions: const [],
      runtime: ThreadRuntimeView(
        modelId: 'planner/local-responses',
        modelRoute: ThreadModelRouteView(
          accountId: route.accountId,
          modelId: route.modelId,
          effort: route.effort,
          revision: 1,
          available: true,
        ),
        contextTokens: 18342,
        contextWindow: 96000,
        maxContextWindow: 128000,
        autoCompactLimit: 86400,
        totalTokens: 26320,
        promptTokens: 22160,
        completionTokens: 4160,
        cachedPromptTokens: 8860,
        cacheWriteTokens: 1240,
        reasoningTokens: 1520,
        inferenceCount: 6,
        cacheUsage: CacheUsageView(
          inputTokens: 22160,
          cacheReadTokens: 8860,
          hitRate: 0.4,
        ),
        estimatedCosts: [
          RuntimeCostView(currency: 'CNY', amount: 0.13),
          RuntimeCostView(currency: 'USD', amount: 0.02),
        ],
        estimatedCacheSavings: [RuntimeCostView(currency: 'CNY', amount: 0.05)],
        costLabel: '￥0.13 + \$0.02',
        activeSkills: ['flutter-apply-architecture-best-practices'],
        activeMcpServers: ['dart'],
        activeLspServers: ['rust-analyzer'],
        turnCompletionTokens: 150,
        turnResponseMillis: 1000,
      ),
    );
  }

  ThreadWorkspace _singleMessageWorkspace(
    StudioThread thread,
    String text,
    String modelId,
    DateTime createdAt,
  ) {
    _threadItems[thread.id] = List.unmodifiable([
      _messageItem(
        id: '${thread.id}:final',
        threadId: thread.id,
        turnId: '${thread.id}:turn',
        ordinal: 0,
        channel: ThreadTextChannel.finalAnswer,
        text: text,
        createdAt: createdAt,
      ),
    ]);
    return ThreadWorkspace(
      thread: thread,
      revision: 1,
      interactions: const [],
      runtime: ThreadRuntimeView(
        modelId: modelId,
        modelRoute: ThreadModelRouteView(
          accountId: _demoModeRoute(thread.mode).accountId,
          modelId: modelId,
          effort: null,
          revision: 1,
          available: true,
        ),
        contextTokens: 320,
        contextWindow: 128000,
        maxContextWindow: 128000,
        totalTokens: 512,
        estimatedCosts: const [RuntimeCostView(currency: 'CNY', amount: 0.01)],
        costLabel: '￥0.01',
        activeSkills: const [],
        activeMcpServers: const ['dart'],
        activeLspServers: const [],
        turnCompletionTokens: 216,
        turnResponseMillis: 2500,
      ),
    );
  }

  @override
  Future<AccountCatalogView> loadAccountCatalog() async => _accountCatalog;

  @override
  Future<AcpAccountCatalogView> loadAcpAccountCatalog() async =>
      demoAcpAccountCatalogFixture;

  AcpAccountSettingsView _demoAcpAccount(String accountId) {
    final account = _acpAccounts
        .where((candidate) => candidate.accountId == accountId)
        .firstOrNull;
    if (account == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'ACP account is unavailable: $accountId',
        retryable: false,
        correlationId: 'demo-acp',
      );
    }
    return account;
  }

  AcpAuthCommandReply _demoAcpReply(
    OperationId operationId,
    AcpAuthSnapshotView snapshot, {
    CommitDisposition disposition = CommitDisposition.applied,
  }) {
    _publishProductPayload(AcpAuthStateChangedPayload(snapshot));
    return AcpAuthCommandReply(
      receipt: _demoReceipt(
        operationId,
        changed: disposition == CommitDisposition.applied,
        targets: [_demoStamp('acp-auth', snapshot.revision)],
        effect: EffectPoint.immediate,
      ),
      snapshot: snapshot,
    );
  }

  @override
  Future<SettingsCommandReply> saveAcpAccount(
    int expectedSettingsRevision,
    AcpAccountUpdateView account, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    if (account.accountId.trim().isEmpty || account.name.trim().isEmpty) {
      throw StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'ACP account requires an id and a name',
        retryable: false,
        correlationId: 'demo-acp',
      );
    }
    final previous = _acpAccounts
        .where((candidate) => candidate.accountId == account.accountId)
        .firstOrNull;
    final identityChanged =
        previous == null || previous.provider != account.provider;
    final saved = AcpAccountSettingsView(
      accountId: account.accountId,
      name: account.name,
      provider: account.provider,
      connectionRevision: identityChanged
          ? (previous?.connectionRevision ?? 0) + 1
          : previous.connectionRevision,
    );
    _acpAccounts = [
      for (final candidate in _acpAccounts)
        if (candidate.accountId != saved.accountId) candidate,
      saved,
    ];
    _demoAcpAuth.retain(saved);
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> removeAcpAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    _acpAccounts = [
      for (final account in _acpAccounts)
        if (account.accountId != accountId) account,
    ];
    _demoAcpAuth.forget(accountId);
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    _ensureDemoRunning();
    final account = _demoAcpAccount(accountId);
    if (account.connectionRevision != expectedConnectionRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'ACP connection identity changed for $accountId',
        retryable: false,
        correlationId: 'demo-acp',
      );
    }
    final snapshot = switch (action) {
      AcpCheckActionView() => _demoAcpAuth.check(account),
      AcpAuthenticateActionView(:final methodId) => _demoAcpAuth.authenticate(
        account,
        methodId,
      ),
    };
    return _demoAcpReply(operationId, snapshot);
  }

  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) async {
    _ensureDemoRunning();
    final account = _demoAcpAccount(accountId);
    final snapshot = _demoAcpAuth.cancel(account, targetOperationId.value);
    return _demoAcpReply(operationId, snapshot);
  }

  // -------------------------------------------------------------------------
  // `acpInstall` demo：只模拟后端发布的阶段与真实形状的进度，不联网、不写盘。
  // -------------------------------------------------------------------------

  AcpInstallSnapshotView _demoInstallSnapshot() => AcpInstallSnapshotView(
    revision: _acpInstallRevision,
    updatedAt: _fixtureTime.millisecondsSinceEpoch ~/ 1000,
    installations: [
      for (final entry in _acpInstalls.entries)
        AcpInstallEntryView(provider: entry.key, state: entry.value),
    ],
  );

  void _publishInstall(AcpProviderView provider, AcpInstallStateView state) {
    _acpInstalls[provider] = state;
    _acpInstallRevision += 1;
    _publishProductPayload(
      AcpInstallStateChangedPayload(_demoInstallSnapshot()),
    );
  }

  AcpInstallCommandReply _demoInstallReply(
    OperationId operationId,
    AcpProviderView provider,
  ) => AcpInstallCommandReply(
    receipt: _demoReceipt(
      operationId,
      changed: true,
      targets: [_demoStamp('acp-install', _acpInstallRevision)],
      effect: EffectPoint.immediate,
    ),
    snapshot: _demoInstallSnapshot(),
  );

  AcpInstallReleaseView _demoInstallRelease() => const AcpInstallReleaseView(
    version: '1.4.1',
    target: 'linux-x86_64',
    archiveUrl: 'https://dl.google.com/agy-extensions/releases/antigravity-acp-linux-x86_64.zip',
  );

  static const int _demoInstallTotalBytes = 12582912;
  static const int _demoInstallStepBytes = 1572864;

  @override
  Future<AcpInstallCommandReply> startAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
  }) async {
    _ensureDemoRunning();
    final current = _acpInstalls[provider] ?? const AcpInstallIdleState();
    if (current.isBusy) {
      throw StudioFailure(
        code: StudioFailureCode.busy,
        message: 'An ACP server preparation is already active',
        retryable: false,
        correlationId: 'demo-acp-install',
      );
    }
    final release = _demoInstallRelease();
    final op = operationId.value;
    _publishInstall(provider, AcpResolvingState(operationId: op));
    var step = 0;
    var completed = 0;
    _acpInstallTimers[provider]?.cancel();
    _acpInstallTimers[provider] = Timer.periodic(
      const Duration(milliseconds: 260),
      (timer) {
        if (_runtimeExiting) {
          timer.cancel();
          return;
        }
        step += 1;
        if (step == 1) {
          _publishInstall(
            provider,
            AcpWaitingForAssetState(operationId: op, release: release),
          );
          return;
        }
        if (step <= 8) {
          completed += _demoInstallStepBytes;
          if (completed > _demoInstallTotalBytes) {
            completed = _demoInstallTotalBytes;
          }
          _publishInstall(
            provider,
            AcpDownloadingState(
              operationId: op,
              release: release,
              progress: AcpInstallProgressView(
                completedBytes: completed,
                totalBytes: _demoInstallTotalBytes,
                bytesPerSecond: _demoInstallStepBytes * 4,
              ),
              retryCount: step == 4 ? 1 : 0,
            ),
          );
          return;
        }
        switch (step) {
          case 9:
            _publishInstall(
              provider,
              AcpInstallVerifyingState(
                operationId: op,
                release: release,
                progress: const AcpInstallProgressView(
                  completedBytes: _demoInstallTotalBytes,
                  totalBytes: _demoInstallTotalBytes,
                ),
              ),
            );
          case 10:
            _publishInstall(
              provider,
              AcpExtractingState(
                operationId: op,
                release: release,
                progress: const AcpInstallProgressView(
                  completedBytes: _demoInstallTotalBytes,
                  totalBytes: _demoInstallTotalBytes,
                ),
              ),
            );
          case 11:
            _publishInstall(
              provider,
              AcpPublishingState(operationId: op, release: release),
            );
          default:
            timer.cancel();
            _acpInstallTimers.remove(provider);
            _publishInstall(
              provider,
              AcpInstallReadyState(
                operationId: op,
                server: AcpInstalledServerView(
                  installationId: 'demo-installation-$op',
                  release: release,
                  program: '/home/studio/acp-servers/antigravity/1.4.1/program',
                  readyAt: _fixtureTime.millisecondsSinceEpoch ~/ 1000,
                ),
              ),
            );
        }
      },
    );
    return _demoInstallReply(operationId, provider);
  }

  @override
  Future<AcpInstallCommandReply> cancelAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
    required OperationId targetOperationId,
  }) async {
    _ensureDemoRunning();
    final current = _acpInstalls[provider] ?? const AcpInstallIdleState();
    if (current.operationId != targetOperationId.value) {
      throw StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'ACP server preparation identity changed',
        retryable: false,
        correlationId: 'demo-acp-install',
      );
    }
    _acpInstallTimers.remove(provider)?.cancel();
    _publishInstall(
      provider,
      AcpInstallCancellingState(operationId: targetOperationId.value),
    );
    _publishInstall(
      provider,
      AcpInstallCancelledState(operationId: targetOperationId.value),
    );
    return _demoInstallReply(operationId, provider);
  }

  @override
  Future<AgentProfilesStateView> readAgentProfilesState() async =>
      readAgentProfilesStateSync();

  @override
  Future<List<AgentProfileView>> readAgentProfiles() async =>
      _demoAgentProfilesSync();

  @override
  Future<SettingsCommandReply> setSystemAgentEnabled({
    required OperationId operationId,
    required int expectedSettingsRevision,
    required String profileId,
    required bool enabled,
  }) async {
    if (![
      'explorer',
      'executor',
      'worktree_executor',
      'reviewer',
    ].contains(profileId)) {
      throw ArgumentError.value(
        profileId,
        'profileId',
        'not a system subagent',
      );
    }
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final changed = _disabledSystemAgents.contains(profileId) == enabled;
    if (enabled) {
      _disabledSystemAgents.remove(profileId);
    } else {
      _disabledSystemAgents.add(profileId);
    }
    _settingsRevision += 1;
    _emitAgentProfilesUpdate();
    return _demoSettingsReply(operationId, before, changed: changed);
  }

  @override
  Future<SettingsCommandReply> saveUserAgentProfile(
    int expectedSettingsRevision,
    AgentProfileDraft draft, {
    required OperationId operationId,
  }) async {
    if ([
      'planner',
      'explorer',
      'executor',
      'worktree_executor',
      'reviewer',
    ].contains(draft.id)) {
      throw ArgumentError.value(draft.id, 'id', 'reserved agent identifier');
    }
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final previous = _userAgentProfiles[draft.id];
    _userAgentProfiles[draft.id] = AgentProfileView(
      id: draft.id,
      displayName: draft.displayName,
      description: draft.description,
      whenToUse: draft.whenToUse,
      systemInstructions: draft.systemInstructions,
      accountId: draft.accountId,
      modelId: draft.modelId,
      effort: draft.effort,
      source: '~/.anywork/agents/${draft.id}.toml',
      revision: 'demo-user-${draft.id}',
      contentHash: 'demo-user-${draft.id}',
      system: false,
      enabled: draft.enabled,
      workspaceMode: draft.workspaceMode,
    );
    _settingsRevision += 1;
    _emitAgentProfilesUpdate();
    return _demoSettingsReply(
      operationId,
      before,
      changed: previous != _userAgentProfiles[draft.id],
    );
  }

  @override
  Future<void> cleanupPreservedWorktree({
    required String ownerKind,
    required String ownerThreadId,
    required int expectedLeaseRevision,
  }) async {
    if (ownerKind != WorktreeOwnerKind.session.id &&
        ownerKind != WorktreeOwnerKind.child.id) {
      throw ArgumentError.value(
        ownerKind,
        'ownerKind',
        'must be session or child',
      );
    }
  }

  @override
  Future<StudioProject> renameProject(String projectId, String name) async {
    final project = _demoProjectDirectory().values.firstWhere(
      (project) => project.id == projectId,
    );
    _projectNames[projectId] = name;
    _projectDirectoryRevision++;
    _publishProductPayload(
      ProjectDirectoryChangedPayload(_demoProjectDirectory()),
    );
    return StudioProject(
      id: project.id,
      name: name,
      path: project.path,
      kind: project.kind,
      sshAlias: project.sshAlias,
    );
  }

  @override
  Future<StudioProject> openProject(String path) async {
    if (_archivedProjectIds.remove('project-local')) {
      _projectDirectoryRevision += 1;
      _publishProductPayload(
        ProjectDirectoryChangedPayload(_demoProjectDirectory()),
      );
    }
    return _demoProjectDirectory().values.first;
  }

  @override
  Future<ProjectDirectoryState> prepareStandaloneWorkspace() async {
    _ensureDemoRunning();
    final existing = _standaloneProject;
    if (existing != null) return _demoProjectDirectory();
    const project = StudioProject(
      id: 'project-standalone',
      name: 'Standalone workspace',
      path: 'Documents/anywork',
      kind: WorkspaceKind.standalone,
    );
    _standaloneProject = project;
    _projectDirectoryRevision++;
    _publishProductPayload(
      ProjectDirectoryChangedPayload(_demoProjectDirectory()),
    );
    return _demoProjectDirectory();
  }

  @override
  Future<List<SshServer>> listSshServers() async => List.of(_sshServers);

  @override
  Future<SshServer> saveSshServer(SaveSshServerCommand command) async {
    final existing = _sshServers
        .where((item) => item.alias == command.alias)
        .firstOrNull;
    final hasPassword = switch (command.password.action) {
      SshPasswordAction.preserve => existing?.hasPassword ?? false,
      SshPasswordAction.replace => true,
      SshPasswordAction.clear => false,
    };
    final server = SshServer(
      alias: command.alias,
      hostName: command.hostName,
      port: command.port,
      username: command.username,
      identityFile: command.identityFile,
      managed: true,
      hasPassword: hasPassword,
    );
    _sshServers.removeWhere((item) => item.alias == server.alias);
    _sshServers.add(server);
    return server;
  }

  @override
  Future<void> deleteSshServer(String alias) async {
    _sshServers.removeWhere((server) => server.alias == alias);
  }

  @override
  Future<SshConnectionView> authenticateSshServer(
    AuthenticateSshServerCommand command,
  ) async {
    final index = _sshServers.indexWhere((item) => item.alias == command.alias);
    if (index != -1 && command.rememberPassword) {
      final current = _sshServers[index];
      _sshServers[index] = SshServer(
        alias: current.alias,
        hostName: current.hostName,
        port: current.port,
        username: current.username,
        identityFile: current.identityFile,
        managed: current.managed,
        hasPassword: true,
      );
    }
    return testSshConnection(command.alias);
  }

  @override
  Future<SshConnectionView> testSshConnection(String alias) async {
    return SshConnectionView(
      alias: alias,
      state: 'ready',
      helperVersion: '0.1.0',
      architecture: 'aarch64',
    );
  }

  @override
  Future<SshConnectionView> reconnectSshServer(String alias) =>
      testSshConnection(alias);

  @override
  Future<RemoteDirectoryListing> browseRemoteDirectories(
    String alias, {
    String? path,
    String? cursor,
  }) async {
    final current = path ?? '/home';
    return RemoteDirectoryListing(
      path: current,
      parent: current == '/' ? null : '/',
      entries: const [
        RemoteDirectoryEntry(name: 'projects', path: '/home/projects'),
        RemoteDirectoryEntry(name: 'workspace', path: '/workspace'),
      ],
    );
  }

  @override
  Future<void> closeRemoteDirectory(String alias, String cursor) async {}

  @override
  Future<StudioProject> openRemoteProject(String alias, String path) async {
    final project = StudioProject(
      id: 'project-remote',
      name: path.split('/').last,
      path: path,
      sshAlias: alias,
    );
    final existingIndex = _openedRemoteProjects.indexWhere(
      (candidate) => candidate.id == project.id,
    );
    if (existingIndex < 0) {
      _openedRemoteProjects.add(project);
      _projectDirectoryRevision += 1;
    } else {
      final existing = _openedRemoteProjects[existingIndex];
      if (existing.name != project.name ||
          existing.path != project.path ||
          existing.sshAlias != project.sshAlias) {
        _openedRemoteProjects[existingIndex] = project;
        _projectDirectoryRevision += 1;
      }
    }
    _publishProductPayload(
      ProjectDirectoryChangedPayload(_demoProjectDirectory()),
    );
    return project;
  }

  @override
  Future<void> activateProject(String projectId) async {
    if (!_demoProjectDirectory().values.any(
      (project) => project.id == projectId,
    )) {
      throw StateError('unknown demo project $projectId');
    }
    _selectedProjectId = projectId;
  }

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String projectId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  }) async* {
    try {
      final projects = _demoProjectDirectory().values;
      final project = projects
          .where((candidate) => candidate.id == projectId)
          .firstOrNull;
      if (project == null) {
        throw StateError('unknown demo project $projectId');
      }
      if (input.text.trim().isEmpty && input.attachmentDraftIds.isEmpty) {
        throw ArgumentError.value(input.text, 'text', 'empty');
      }
      final requestedWorkspaceMode = switch (workspaceMode?.trim()) {
        null || '' || 'local' => ThreadWorkspaceMode.local,
        'worktree' => ThreadWorkspaceMode.worktree,
        final other => throw ArgumentError.value(
          other,
          'workspaceMode',
          'must be local or worktree',
        ),
      };
      if (project.isStandalone && requestedWorkspaceMode.isWorktree) {
        throw ArgumentError.value(
          workspaceMode,
          'workspaceMode',
          'standalone workspaces only support local mode',
        );
      }
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.checkingProject,
        ),
      );
      final now = DateTime.now();
      final provisionalTitle = _demoProvisionalThreadTitle(input.text);
      final threadId = 'thread-created-${++_threadSequence}';
      final projectPath = projects
          .firstWhere((project) => project.id == projectId)
          .path;
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.preparingWorkspace,
        ),
      );
      final thread = StudioThread(
        id: threadId,
        projectId: projectId,
        title: provisionalTitle,
        mode: mode,
        delegationMode: delegationMode,
        delegationPreference: delegationPreference,
        role: 'planner',
        createdAt: now,
        updatedAt: now,
        workspaceMode: requestedWorkspaceMode,
        workspacePath: requestedWorkspaceMode == ThreadWorkspaceMode.worktree
            ? _demoWorktreePath(projectPath, threadId)
            : projectPath,
      );
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.initializingSession,
          workspacePath: thread.workspacePath,
        ),
      );
      _createdRootThreads.add(thread);
      _ensureWorkspaceFixture();
      _selectedThreadId = thread.id;
      final workspace = _workspaces[thread.id]!;
      _workspaces[thread.id] = workspace.copyWith(
        runtime: workspace.runtime.copyWith(
          modelId: route.modelId,
          modelRoute: ThreadModelRouteView(
            accountId: route.accountId,
            modelId: route.modelId,
            effort: route.effort,
            revision: 1,
            available: true,
          ),
        ),
      );
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.submittingPrompt,
          workspacePath: thread.workspacePath,
        ),
      );
      final receipt = await _submitPrompt(thread.id, input);
      if (input.text.trim().isNotEmpty) {
        unawaited(_completeDemoThreadTitle(thread.id, provisionalTitle));
      }
      yield NewThreadStartSucceeded(
        StartNewThreadResult(thread: thread, receipt: receipt),
      );
    } catch (error) {
      yield NewThreadStartFailed(
        StudioFailure(
          code: error is ArgumentError
              ? StudioFailureCode.invalidArgument
              : StudioFailureCode.internal,
          message: error.toString(),
          retryable: false,
          correlationId: newStudioCorrelationId(),
        ),
      );
    }
  }

  @override
  Future<RenameThreadCommandReply> renameThread(
    String threadId,
    String title, {
    required OperationId operationId,
  }) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.runes.length > 80) {
      throw ArgumentError.value(title, 'title', 'must be 1–80 characters');
    }
    final index = _createdRootThreads.indexWhere(
      (thread) => thread.id == threadId,
    );
    if (index < 0) throw StateError('unknown demo root Thread $threadId');
    final changed = _createdRootThreads[index].title != normalized;
    final renamed = _createdRootThreads[index].copyWith(
      title: normalized,
      updatedAt: DateTime.now(),
    );
    _createdRootThreads[index] = renamed;
    if (_workspaces[threadId] case final workspace?) {
      _workspaces[threadId] = workspace.copyWith(thread: renamed);
    }
    _emitThreadDirectoryUpdate(renamed);
    return RenameThreadCommandReply(
      thread: renamed,
      receipt: _demoReceipt(
        operationId,
        changed: changed,
        targets: [_demoStamp('thread-directory', _threadDirectoryRevision)],
        effect: EffectPoint.immediate,
      ),
    );
  }

  Future<void> _completeDemoThreadTitle(
    String threadId,
    String provisionalTitle,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final index = _createdRootThreads.indexWhere(
      (thread) => thread.id == threadId,
    );
    if (index < 0 || _archivedThreadIds.contains(threadId)) return;
    final current = _createdRootThreads[index];
    if (current.title != provisionalTitle) return;
    final renamed = current.copyWith(
      title: 'Demo generated session',
      updatedAt: DateTime.now(),
    );
    _createdRootThreads[index] = renamed;
    if (_workspaces[threadId] case final workspace?) {
      _workspaces[threadId] = workspace.copyWith(thread: renamed);
    }
    _emitThreadDirectoryUpdate(renamed);
  }

  /// 记录一次已受理的模拟用户消息：推进目录的最近用户消息时间并广播增量。
  void _advanceDemoLastUserMessage(String threadId, DateTime acceptedAt) {
    StudioThread? updated;
    for (var index = 0; index < _createdRootThreads.length; index++) {
      if (_createdRootThreads[index].id == threadId) {
        updated = _createdRootThreads[index] = _createdRootThreads[index]
            .copyWith(lastUserMessageAt: acceptedAt, updatedAt: acceptedAt);
      }
    }
    for (var index = 0; index < _pageFillThreads.length; index++) {
      if (_pageFillThreads[index].id == threadId) {
        updated = _pageFillThreads[index] = _pageFillThreads[index].copyWith(
          lastUserMessageAt: acceptedAt,
          updatedAt: acceptedAt,
        );
      }
    }
    final workspace = _workspaces[threadId];
    if (workspace != null && workspace.thread.id == threadId) {
      final thread = workspace.thread.copyWith(
        lastUserMessageAt: acceptedAt,
        updatedAt: acceptedAt,
      );
      _workspaces[threadId] = workspace.copyWith(thread: thread);
      updated = thread;
    }
    if (updated != null) {
      _emitThreadDirectoryUpdate(updated);
    }
  }

  /// settings 写入的 canonical 事实同时经 topic 交付。
  ///
  /// 真实侧每次 `publish_settings_state` 都发布 `SettingsConfigStateChanged` 与
  /// `ModelCatalogStateChanged`，只让命令返回快照会让仅依赖 topic 的观察者停在旧值，
  /// demo 因此与真实 bridge 语义分叉（design/25 §25.10）。
  SettingsStateSnapshot _settingsWriteResult() {
    final state = _demoSettingsState();
    _publishProductPayload(SettingsConfigStateChangedPayload(state));
    _publishProductPayload(ModelCatalogStateChangedPayload(state));
    return state;
  }

  ResourceStamp _demoStamp(String key, int revision) => ResourceStamp(
    resourceKey: key,
    ownerEpoch: _ownerEpoch,
    revision: revision,
  );

  StudioCommandReceipt _demoReceipt(
    OperationId operationId, {
    required bool changed,
    required List<ResourceStamp> targets,
    required EffectPoint effect,
    bool? effective,
    bool requiresIdentityObservation = false,
  }) => StudioCommandReceipt(
    operationId: operationId,
    disposition: changed
        ? CommitDisposition.applied
        : CommitDisposition.noChange,
    targets: targets,
    effect: effect,
    effective: effective ?? effect == EffectPoint.immediate,
    requiresIdentityObservation: requiresIdentityObservation,
    // Demo has no native persistence and cannot acknowledge durability.
    durable: false,
  );

  SettingsCommandReply _demoSettingsReply(
    OperationId operationId,
    SettingsStateSnapshot before, {
    bool? changed,
    EffectPoint effect = EffectPoint.futureSession,
  }) {
    final next = _demoSettingsState();
    List<Object?> catalogs(SettingsStateSnapshot snapshot) => [
      for (final account in snapshot.accounts)
        [
          account.id,
          for (final model in account.models)
            [
              model.modelId,
              model.enabled,
              model.connectionMode,
              model.context.autoCompactLimit,
            ],
          for (final entry in account.autoCompactLimits.entries)
            [entry.key, entry.value.overrideLimit],
        ],
    ];
    if (!_sameDemoFacts(catalogs(before), catalogs(next))) {
      _modelCatalogRevision++;
    }
    final snapshot = _settingsWriteResult();
    return SettingsCommandReply(
      snapshot: snapshot,
      accountFrames: [
        for (final account in snapshot.accounts)
          _readAccountDomain(
            AccountDetailTarget(NativeAccountIdentity(account.id)),
          ),
        for (final account in snapshot.acpAccounts)
          _readAccountDomain(
            AccountDetailTarget(AcpAccountIdentity(account.accountId)),
          ),
        for (final account in before.accounts)
          if (!snapshot.accounts.any((next) => next.id == account.id))
            AccountDetailFrame(
              _demoStamp('settings', snapshot.revision),
              NativeAccountIdentity(account.id),
              null,
            ),
        for (final account in before.acpAccounts)
          if (!snapshot.acpAccounts.any(
            (next) => next.accountId == account.accountId,
          ))
            AccountDetailFrame(
              _demoStamp('settings', snapshot.revision),
              AcpAccountIdentity(account.accountId),
              null,
            ),
        for (final account in snapshot.accounts)
          _readAccountDomain(
            AccountModelsTarget(NativeAccountIdentity(account.id)),
          ),
        for (final account in before.accounts)
          if (!snapshot.accounts.any((next) => next.id == account.id))
            AccountModelsFrame(
              _demoStamp('model-catalog', _modelCatalogRevision),
              NativeAccountIdentity(account.id),
              null,
            ),
      ],
      receipt: _demoReceipt(
        operationId,
        changed:
            changed ??
            !_sameDemoFacts(
              _demoSettingsFacts(before),
              _demoSettingsFacts(snapshot),
            ),
        targets: [_demoStamp('settings', snapshot.revision)],
        effect: effect,
      ),
    );
  }

  EffectPoint _demoFieldEffect(SettingsFieldCommand command) =>
      switch (command) {
        GeneralFollowActiveTurnCommand() ||
        GeneralCompactTimelineCommand() ||
        GeneralLanguageCommand() ||
        GeneralSidebarWidthCommand() ||
        GeneralPinnedThreadIdsCommand() ||
        GeneralPinnedProjectIdsCommand() => EffectPoint.immediate,
        _ => EffectPoint.futureSession,
      };

  // Compare canonical business values, excluding resource clocks and diagnostics.
  // This is a value comparison of the one demo owner, not a second state store.
  List<Object?> _demoSettingsFacts(SettingsStateSnapshot s) => [
    s.defaultAccountId,
    s.delegation.mode,
    s.delegation.preference,
    s.permissionMode,
    {
      for (final account in s.acpAccounts)
        account.accountId: [
          account.name,
          account.provider.wire,
          account.connectionRevision,
        ],
    },
    {
      for (final p in s.accounts)
        p.id: [
          p.name,
          p.templateId,
          p.protocol,
          p.baseUrl,
          p.bearerToken,
          p.hasBearerToken,
          p.defaultModelId,
          p.billingKind,
          p.billingKindOverride,
          p.modelEnabledOverrides,
          [
            for (final m in p.customModels)
              [
                m.modelId,
                m.displayName,
                m.wireApi,
                m.contextWindow,
                m.maxOutputTokens,
              ],
          ],
          p.modelConnectionModes,
          {
            for (final e in p.autoCompactLimits.entries)
              e.key: e.value.overrideLimit,
          },
        ],
    },
    {
      for (final route in s.modeModelRoutes)
        route.modeId.id: [route.accountId, route.modelId, route.effort],
    },
    {
      for (final role in s.roles)
        role.key: [role.accountId, role.modelId, role.effort],
    },
    {
      for (final server in s.mcpServers)
        server.id: [server.transport, server.endpoint],
    },
    [
      s.instructions.baseOverride,
      s.instructions.developer,
      s.instructions.user,
      s.instructions.projectDocMaxBytes,
      s.instructions.projectDocFallbackFilenames,
    ],
    [
      s.skills.enabled,
      s.skills.autoLearn,
      s.skills.systemEnabled,
      s.skills.projectDir,
      s.skills.userDir,
      s.skills.externalDirs,
      s.skills.disabled,
      s.skills.autoLearnMinToolCalls,
    ],
    [
      s.general.language,
      s.general.followActiveTurn,
      s.general.compactTimeline,
      s.general.sidebarWidth,
      s.general.pinnedThreadIds,
      s.general.pinnedProjectIds,
    ],
    [
      s.webSearch.configuredMode,
      s.webSearch.contextSize,
      s.webSearch.allowedDomains,
      s.webSearch.country,
      s.webSearch.region,
      s.webSearch.city,
      s.webSearch.timezone,
    ],
    [
      s.deepSeekWebSearch.configuredEnabled,
      s.deepSeekWebSearch.configuredFetchEnabled,
    ],
  ];

  bool _sameDemoFacts(Object? left, Object? right) {
    if (left is List && right is List) {
      return left.length == right.length &&
          [
            for (var i = 0; i < left.length; i++)
              _sameDemoFacts(left[i], right[i]),
          ].every((value) => value);
    }
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) =>
                right.containsKey(key) && _sameDemoFacts(left[key], right[key]),
          );
    }
    return left == right;
  }

  void _emitThreadDirectoryUpdate(StudioThread thread) {
    _threadDirectoryRevision += 1;
    _publishProductPayload(
      ThreadDirectoryChangedPayload(
        revision: _threadDirectoryRevision,
        upserted: [thread],
        removed: const [],
      ),
    );
  }

  /// 配置级 Profiles 变化同样发布 typed topic 事实（保存命令返回 Settings snapshot，
  /// 但 Profiles 目录自身是独立资源；订阅者按 revision 前进）。
  void _emitAgentProfilesUpdate() {
    _agentProfilesRevision += 1;
    _publishProductPayload(
      AgentProfilesStateChangedPayload(readAgentProfilesStateSync()),
    );
  }

  AgentProfilesStateView readAgentProfilesStateSync() {
    return AgentProfilesStateView(
      state: ReadyObservedResource(
        revision: _agentProfilesRevision,
        updatedAt: 0,
        lastCheckedAt: null,
        value: AgentProfilesDataView(
          profiles: _demoAgentProfilesSync(),
          diagnostics: const [],
        ),
      ),
    );
  }

  List<AgentProfileView> _demoAgentProfilesSync() {
    return [
      AgentProfileView(
        id: 'explorer',
        displayName: 'Explorer',
        description: '只读探索代码、文档和现场事实。',
        whenToUse: '需要定位边界、依赖或验证事实时。',
        systemInstructions: '优先收集事实并引用文件与命令。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v1',
        contentHash: 'demo-explorer',
        system: true,
        enabled: !_disabledSystemAgents.contains('explorer'),
        workspaceMode: AgentWorkspaceMode.unrestricted,
      ),
      AgentProfileView(
        id: 'executor',
        displayName: 'Executor',
        description: '在项目目录内实施边界明确的修改。',
        whenToUse: '需要限制 糊来帮内置文件写工具的修改目录时。',
        systemInstructions: '遵守冻结的 writablePaths。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v2',
        contentHash: 'demo-executor',
        system: true,
        enabled: !_disabledSystemAgents.contains('executor'),
        workspaceMode: AgentWorkspaceMode.directory,
      ),
      AgentProfileView(
        id: 'worktree_executor',
        displayName: 'Worktree Executor',
        description: '在独立 Git worktree 内实施修改。',
        whenToUse: '需要物理隔离并显式整合 commit 时。',
        systemInstructions: '只修改分配的 worktree，不自动整合。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v2',
        contentHash: 'demo-worktree-executor',
        system: true,
        enabled: !_disabledSystemAgents.contains('worktree_executor'),
        workspaceMode: AgentWorkspaceMode.worktree,
      ),
      AgentProfileView(
        id: 'reviewer',
        displayName: 'Reviewer',
        description: '独立审查实现和验证证据。',
        whenToUse: '需要复核实现质量时。',
        systemInstructions: '只读审查并报告具体证据。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v2',
        contentHash: 'demo-reviewer',
        system: true,
        enabled: !_disabledSystemAgents.contains('reviewer'),
        workspaceMode: AgentWorkspaceMode.unrestricted,
      ),
      ..._userAgentProfiles.values,
    ];
  }

  @override
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    final thread = _sortedDirectoryThreads()
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread == null || !thread.isRoot) {
      throw StateError('only a root Thread can be archived');
    }
    // 归档前先结束会话树的活动工作：中断正在运行的 Turn，再归档。
    final activeTurn = _workspaces[threadId]?.activeTurn;
    if (activeTurn != null && activeTurn.state.isBusy) {
      _interruptDemoTurn(threadId, activeTurn.turnId);
    }
    final roots = _sortedDirectoryThreads()
        .where((candidate) => candidate.isRoot)
        .toList();
    final index = roots.indexWhere((candidate) => candidate.id == threadId);
    if (index < 0) throw StateError('unknown demo root Thread $threadId');
    final nextRoot = index + 1 < roots.length
        ? roots[index + 1]
        : index > 0
        ? roots[index - 1]
        : null;
    final removedThreadIds = <String>{
      threadId,
      for (final candidate in _ensureWorkspaceFixture().threads)
        if (candidate.effectiveRootThreadId == threadId) candidate.id,
    }.toList();
    _archivedThreadIds.add(threadId);
    if (_selectedThreadId == threadId) _selectedThreadId = nextRoot?.id;
    _threadDirectoryRevision += 1;
    _publishProductPayload(
      ThreadDirectoryChangedPayload(
        revision: _threadDirectoryRevision,
        upserted: const [],
        removed: removedThreadIds,
      ),
    );
    return ArchiveThreadCommandReply(
      result: ArchiveThreadResult(
        archivedRootId: threadId,
        removedThreadIds: removedThreadIds,
        nextRoot: nextRoot,
      ),
      receipt: _demoReceipt(
        operationId,
        changed: true,
        targets: [_demoStamp('thread-directory', _threadDirectoryRevision)],
        effect: EffectPoint.immediate,
      ),
    );
  }

  @override
  Future<void> archiveProject(String projectId) async {
    if (projectId == 'project-local' && _archivedProjectIds.add(projectId)) {
      _projectDirectoryRevision += 1;
      final removed = _workspaces.values
          .where((workspace) => workspace.thread.projectId == projectId)
          .map((workspace) => workspace.thread.id)
          .toList();
      _threadDirectoryRevision += 1;
      _publishProductPayload(
        ProjectDirectoryChangedPayload(_demoProjectDirectory()),
      );
      _publishProductPayload(
        ThreadDirectoryChangedPayload(
          revision: _threadDirectoryRevision,
          upserted: const [],
          removed: removed,
        ),
      );
    }
  }

  @override
  Future<PersistenceStateSnapshot> retryPersistence() async =>
      const PersistenceStateSnapshot.ready();

  @override
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  ) async => const PersistenceQueueSnapshot.empty();

  /// demo 是纯内存实现，没有存储故障闩：显式继续同样是空的 canonical 观测。
  @override
  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  ) async => const PersistenceQueueSnapshot.empty();

  /// demo 是纯内存实现，没有异步持久化队列，因此队列压力恒为空的 canonical 观测。
  @override
  Future<PersistenceQueueStateView> readPersistenceQueueState() async =>
      const PersistenceQueueStateView(
        revision: 0,
        queue: PersistenceQueueSnapshot.empty(),
      );

  @override
  Future<PersistenceQueueSnapshot> readPersistenceQueue() async =>
      const PersistenceQueueSnapshot.empty();

  /// Demo counterpart of the production field mutation endpoint.
  ///
  /// The demo must obey the same contract as the Bridge: one command changes
  /// one canonical field/resource and never reconstructs a sibling settings
  /// object from a stale page snapshot.
  @override
  Future<SettingsCommandReply> applySettingsField(
    int expectedSettingsRevision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final settings = before;
    switch (command) {
      case InstructionBaseOverrideCommand(:final value):
        _instructions = _instructions.copyWith(baseOverride: value);
      case DelegationModeCommand(:final value):
        _delegation = DelegationSettingsView(
          mode: value,
          preference: _delegation.preference,
        );
      case DelegationPreferenceCommand(:final value):
        _delegation = DelegationSettingsView(
          mode: _delegation.mode,
          preference: value,
        );
      case InstructionDeveloperCommand(:final value):
        _instructions = _instructions.copyWith(developer: value);
      case InstructionUserCommand(:final value):
        _instructions = _instructions.copyWith(user: value);
      case ProjectDocMaxBytesCommand(:final value):
        _instructions = _instructions.copyWith(projectDocMaxBytes: value);
      case ProjectDocFallbackFilenamesCommand(:final value):
        _instructions = _instructions.copyWith(
          projectDocFallbackFilenames: value,
        );
      case SkillsEnabledCommand(:final value):
        _skills = _skills.copyWith(enabled: value);
      case SkillsAutoLearnCommand(:final value):
        _skills = _skills.copyWith(autoLearn: value);
      case SkillsSystemEnabledCommand(:final value):
        _skills = _skills.copyWith(systemEnabled: value);
      case SkillsProjectDirCommand(:final value):
        _skills = _skills.copyWith(projectDir: value);
      case SkillsUserDirCommand(:final value):
        _skills = _skills.copyWith(userDir: value);
      case SkillsExternalDirsCommand(:final value):
        _skills = _skills.copyWith(externalDirs: value);
      case SkillsDisabledCommand(:final value):
        _skills = _skills.copyWith(disabled: value);
      case SkillsAutoLearnMinToolCallsCommand(:final value):
        _skills = _skills.copyWith(autoLearnMinToolCalls: value);
      case McpServerEnabledCommand():
      case McpServerTransportCommand():
      case McpServerEndpointCommand():
        // The demo fixture has no configurable MCP entries. Keep the command
        // observable through the same revision/resource boundary as Bridge.
        _mcpRevision += 1;
        _publishProductPayload(McpStateChangedPayload(_demoMcpState()));
      case GeneralFollowActiveTurnCommand(:final value):
        _general = _general.copyWith(followActiveTurn: value);
      case GeneralCompactTimelineCommand(:final value):
        _general = _general.copyWith(compactTimeline: value);
      case GeneralLanguageCommand(:final value):
        _general = _general.copyWith(language: value);
      case GeneralSidebarWidthCommand(:final value):
        _general = _general.copyWith(sidebarWidth: value ?? 336);
      case GeneralPinnedThreadIdsCommand(:final value):
        _general = _general.copyWith(pinnedThreadIds: value);
      case GeneralPinnedProjectIdsCommand(:final value):
        _general = _general.copyWith(pinnedProjectIds: value);
      case WebSearchModeCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: value,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchContextSizeCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: value,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchAllowedDomainsCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: value,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchCountryCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: value,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchRegionCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: value,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchCityCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: value,
          timezone: _webSearch.timezone,
        );
      case WebSearchTimezoneCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: value,
        );
      case DeepSeekWebSearchEnabledCommand(:final value):
        _deepSeekWebSearch = _deepSeekWebSearch.withConfiguredEnabled(value);
      case DeepSeekWebFetchEnabledCommand(:final value):
        _deepSeekWebSearch = _deepSeekWebSearch.withConfiguredFetchEnabled(
          value,
        );
      case ModeModelCommand(:final modeId, :final accountId, :final modelId):
        final mode = ThreadModeId.fromId(modeId);
        final selected = _findDemoModel(settings.accounts, accountId, modelId);
        final previous = settings.modeModelRoutes
            .where((route) => route.modeId == mode)
            .firstOrNull;
        final effort =
            previous != null &&
                previous.accountId == accountId &&
                previous.modelId == modelId
            ? previous.effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        _modeRoutes = [
          for (final route in settings.modeModelRoutes)
            if (route.modeId != mode) route,
          ModeModelRouteView(
            modeId: mode,
            accountId: accountId,
            modelId: modelId,
            effort: effort,
          ),
        ];
      case ModeReasoningEffortCommand(:final modeId, :final effort):
        final mode = ThreadModeId.fromId(modeId);
        final previous = settings.modeModelRoutes
            .where((route) => route.modeId == mode)
            .firstOrNull;
        final route = previous ?? _demoModeRoute(mode);
        final selected = _findDemoModel(
          settings.accounts,
          route.accountId,
          route.modelId,
        );
        final resolvedEffort =
            effort != null && selected.reasoningEfforts.contains(effort)
            ? effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        _modeRoutes = [
          for (final candidate in settings.modeModelRoutes)
            if (candidate.modeId != mode) candidate,
          ModeModelRouteView(
            modeId: mode,
            accountId: route.accountId,
            modelId: route.modelId,
            effort: resolvedEffort,
          ),
        ];
      case RoleModelCommand(:final role, :final accountId, :final modelId):
        final selected = _findDemoModel(settings.accounts, accountId, modelId);
        final previous = settings.roles
            .where((candidate) => candidate.key == role)
            .firstOrNull;
        final effort =
            previous != null &&
                previous.accountId == accountId &&
                previous.modelId == modelId
            ? previous.effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        final next = RoleSettingsView(
          key: role,
          accountId: accountId,
          modelId: modelId,
          effort: effort,
        );
        _roles = [
          for (final candidate in settings.roles)
            if (candidate.key != role) candidate,
          next,
        ];
      case RoleReasoningEffortCommand(:final role, :final effort):
        final previous = settings.roles
            .where((candidate) => candidate.key == role)
            .firstOrNull;
        if (previous == null) {
          throw StateError('unknown demo Agent role: $role');
        }
        final selected = _findDemoModel(
          settings.accounts,
          previous.accountId,
          previous.modelId,
        );
        final resolvedEffort =
            effort != null && selected.reasoningEfforts.contains(effort)
            ? effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        _roles = [
          for (final candidate in settings.roles)
            candidate.key == role
                ? RoleSettingsView(
                    key: candidate.key,
                    accountId: candidate.accountId,
                    modelId: candidate.modelId,
                    effort: resolvedEffort,
                  )
                : candidate,
        ];
    }
    _settingsRevision += 1;
    return _demoSettingsReply(
      operationId,
      before,
      effect: _demoFieldEffect(command),
    );
  }

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute({
    required OperationId operationId,
    required String threadId,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
    required String accountId,
    required String modelId,
    String? effort,
  }) async {
    final current = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final thread = _sortedDirectoryThreads()
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    final workspace = _workspaces[threadId];
    if (thread == null || !thread.isRoot || workspace == null) {
      throw StateError('unknown root demo thread $threadId');
    }
    final previousRoute = workspace.runtime.modelRoute;
    if (previousRoute == null) {
      throw StateError('demo thread has no saved model route');
    }
    if (previousRoute.revision != expectedModelRouteRevision) {
      throw StateError('model route revision conflict');
    }
    final selected = current.accounts
        .firstWhere((account) => account.id == accountId)
        .models
        .firstWhere((candidate) => candidate.modelId == modelId);
    final selectedEffort = selected.reasoningEfforts.contains(effort)
        ? effort
        : selected.reasoningEfforts.firstOrNull ?? '';
    _modeRoutes = [
      for (final route in current.modeModelRoutes)
        if (route.modeId != thread.mode) route,
      ModeModelRouteView(
        modeId: thread.mode,
        accountId: accountId,
        modelId: modelId,
        effort: selectedEffort ?? '',
      ),
    ];
    _settingsRevision += 1;
    final runtime = workspace.runtime.copyWith(
      modelRoute: ThreadModelRouteView(
        accountId: accountId,
        modelId: modelId,
        effort: selectedEffort,
        revision: previousRoute.revision + 1,
        available: true,
      ),
    );
    _workspaces[threadId] = workspace.copyWith(runtime: runtime);
    // 与生产一致：route 变更作为 Thread 运行时状态流事实交付（revision 单调）。
    // 只写内存 workspace 会让选择器在乐观值被清除后回落到旧 canonical route。
    _emitThreadUpdate(
      threadId,
      ThreadRuntimeUpdate(runtime: runtime, todo: workspace.todo),
    );
    final settings = _settingsWriteResult();
    return ThreadModelRouteCommandReply(
      receipt: _demoReceipt(
        operationId,
        changed:
            previousRoute.accountId != accountId ||
            previousRoute.modelId != modelId ||
            previousRoute.effort != selectedEffort ||
            !_sameDemoFacts(
              _demoSettingsFacts(current),
              _demoSettingsFacts(settings),
            ),
        targets: [
          _demoStamp('thread-route:$threadId', runtime.modelRoute!.revision),
          _demoStamp('settings', settings.revision),
        ],
        effect: EffectPoint.nextTurn,
      ),
      runtime: runtime,
      settings: settings,
      modeDefaultSaved: true,
      warning: null,
    );
  }

  @override
  Future<void> compactThread(String threadId) async {
    throw UnsupportedError('Manual compaction requires the native runtime');
  }

  @override
  Future<ThreadModeCommandReply> setThreadMode({
    required OperationId operationId,
    required String threadId,
    required ThreadModeId mode,
  }) async {
    final thread = _sortedDirectoryThreads()
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread == null) {
      throw StateError('unknown demo thread $threadId');
    }
    if (!thread.isRoot) {
      throw StateError('only a root Thread can change mode');
    }
    if (thread.status != ThreadStatusView.idle) {
      throw StateError(
        'thread mode cannot change while the Thread is running or has pending input',
      );
    }
    final workflow = _workspaces[threadId]?.runtime.workflow;
    if (workflow?.isActive ?? false) {
      throw StateError('thread mode cannot change while a workflow is active');
    }
    _threadModes[threadId] = mode;
    final workspace = _workspaces[threadId];
    if (workspace != null) {
      final settings = _demoSettingsState();
      final route =
          settings.modeModelRoutes
              .where((candidate) => candidate.modeId == mode)
              .firstOrNull ??
          settings.modeModelRoutes
              .where((candidate) => candidate.modeId == ThreadModeId.simple)
              .firstOrNull;
      final thread = workspace.thread;
      final updatedThread = thread.copyWith(
        mode: mode,
        role: thread.isRoot ? 'planner' : thread.role,
      );
      // 与生产一致：mode 变更同时交付两条 canonical 事实。
      //
      // 其一，运行时事实：native `set_thread_mode` 经 reconfigure 改写 mode 默认
      // route 扩展并发布 Thread 帧。demo 若只改内存 workspace 而不出这一帧，客户端
      // 的 threadSession 就只能在显式重读下看到新 route，验收无法发现帧丢失。
      _emitThreadUpdate(
        threadId,
        ThreadRuntimeUpdate(
          runtime: route == null
              ? workspace.runtime
              : workspace.runtime.copyWith(
                  modelRoute: ThreadModelRouteView(
                    accountId: route.accountId,
                    modelId: route.modelId,
                    effort: route.effort,
                    revision: (workspace.runtime.modelRoute?.revision ?? 0) + 1,
                    available: true,
                  ),
                ),
          todo: workspace.todo,
        ),
      );
      _workspaces[threadId] = _workspaces[threadId]!.copyWith(
        thread: updatedThread,
      );
      // 其二，目录事实：mode 由目录增量交付（目录 revision 前进）。不推进目录水位
      // 会让客户端的目录基线门与目录事件都看不到这次变更。
      _emitThreadDirectoryUpdate(updatedThread);
    }
    return ThreadModeCommandReply(
      receipt: _demoReceipt(
        operationId,
        changed: true,
        targets: [
          _demoStamp('thread-state:$threadId', _workspaces[threadId]!.revision),
          _demoStamp('thread-directory', _threadDirectoryRevision),
        ],
        effect: EffectPoint.immediate,
      ),
    );
  }

  @override
  Future<ModeDefinitionSnapshot> readThreadModeDefinition(String modeId) async {
    final document = _modeDocuments[modeId];
    if (document == null) {
      throw _demoModeFailure(
        StudioFailureCode.notFound,
        'Unknown demo mode $modeId',
        retryable: false,
      );
    }
    return ModeDefinitionSnapshot(
      revision: _threadModeCatalogRevision,
      document: document,
      readOnly: _readOnlyModeIds.contains(modeId),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> saveThreadModeDefinition(
    ModeDocument document, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    final modeId = document.definition.id;
    if (_readOnlyModeIds.contains(modeId)) {
      throw _demoModeFailure(
        StudioFailureCode.permissionDenied,
        'Built-in mode $modeId is read-only',
        retryable: false,
      );
    }
    if (expectedRevision != _threadModeCatalogRevision) {
      throw _demoModeFailure(
        StudioFailureCode.staleRevision,
        'Mode catalog revision changed',
        retryable: true,
      );
    }
    _modeDocuments[modeId] = document;
    _emitModeCatalogUpdate();
    return _demoModeCommandReply(
      operationId,
      definition: ModeDefinitionSnapshot(
        revision: _threadModeCatalogRevision,
        document: document,
        readOnly: false,
      ),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> deleteThreadModeDefinition(
    String modeId, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    if (_readOnlyModeIds.contains(modeId)) {
      throw _demoModeFailure(
        StudioFailureCode.permissionDenied,
        'Built-in mode $modeId is read-only',
        retryable: false,
      );
    }
    if (expectedRevision != _threadModeCatalogRevision) {
      throw _demoModeFailure(
        StudioFailureCode.staleRevision,
        'Mode catalog revision changed',
        retryable: true,
      );
    }
    if (_modeDocuments.remove(modeId) == null) {
      throw _demoModeFailure(
        StudioFailureCode.notFound,
        'Unknown demo mode $modeId',
        retryable: false,
      );
    }
    _emitModeCatalogUpdate();
    return _demoModeCommandReply(operationId);
  }

  @override
  Future<ModeDefinitionCommandReply> reloadThreadModeDefinitions({
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    if (expectedRevision != _threadModeCatalogRevision) {
      throw _demoModeFailure(
        StudioFailureCode.staleRevision,
        'Mode catalog revision changed',
        retryable: true,
      );
    }
    _emitModeCatalogUpdate();
    return _demoModeCommandReply(operationId);
  }

  @override
  Future<ModeValidationResult> validateThreadModeDefinition(String json) async {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      return ModeValidationResult(
        issues: [
          ModeValidationIssue(
            code: 'json.invalid',
            path: r'$',
            message: error.message,
          ),
        ],
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      return const ModeValidationResult(
        issues: [
          ModeValidationIssue(
            code: 'json.invalid',
            path: r'$',
            message: 'The Mode document must be a JSON object',
          ),
        ],
      );
    }
    final ModeDocument document;
    try {
      document = ModeDocument.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      return ModeValidationResult(
        issues: [
          ModeValidationIssue(
            code: 'json.invalid',
            path: r'$',
            message: error.toString(),
          ),
        ],
      );
    }
    final issues = <ModeValidationIssue>[];
    final workflow = document.definition.workflow;
    if (workflow != null) {
      final ids = <String>{};
      for (final state in workflow.states) {
        if (!ids.add(state.id)) {
          issues.add(
            ModeValidationIssue(
              code: 'workflow.duplicateState',
              path: 'workflow.states.${state.id}',
              message: 'Workflow state ${state.id} is duplicated',
            ),
          );
        }
      }
      if (!ids.contains(workflow.initialStateId)) {
        issues.add(
          ModeValidationIssue(
            code: 'workflow.unknownInitialState',
            path: 'workflow.initialStateId',
            message: 'Initial state ${workflow.initialStateId} does not exist',
          ),
        );
      }
      for (final transition in workflow.transitions) {
        if (!ids.contains(transition.sourceStateId) ||
            !ids.contains(transition.targetStateId)) {
          issues.add(
            ModeValidationIssue(
              code: 'workflow.unknownTransitionState',
              path: 'workflow.transitions',
              message:
                  'Transition ${transition.sourceStateId} -> '
                  '${transition.targetStateId} references an unknown state',
            ),
          );
        }
      }
    }
    return ModeValidationResult(
      document: issues.isEmpty ? document : null,
      issues: issues,
    );
  }

  @override
  Future<String> threadModeDefinitionSchema() async => jsonEncode({
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'title': 'Anywork Thread Mode',
    'type': 'object',
    'required': ['id', 'displayName', 'description', 'order', 'prompt'],
    'properties': {
      'id': {'type': 'string', 'pattern': r'^mode\.[a-z0-9_-]+$'},
      'displayName': {'type': 'string'},
      'description': {'type': 'string'},
      'order': {'type': 'integer', 'minimum': 0},
      'prompt': {'type': 'string'},
      'workflow': {
        'type': ['object', 'null'],
      },
      'editor': {'type': 'object'},
    },
  });

  @override
  Future<WorkflowPreviewSnapshot> previewThreadModeWorkflow(
    WorkflowPreviewRequest request,
  ) async => _demoWorkflowPreview(request);

  void _emitModeCatalogUpdate() {
    _threadModeCatalogRevision += 1;
    _publishProductPayload(
      ThreadModeCatalogChangedPayload(_demoThreadModeCatalog()),
    );
  }

  ModeDefinitionCommandReply _demoModeCommandReply(
    OperationId operationId, {
    ModeDefinitionSnapshot? definition,
  }) => ModeDefinitionCommandReply(
    catalog: _demoThreadModeCatalog(),
    definition: definition,
    receipt: _demoReceipt(
      operationId,
      changed: true,
      targets: [_demoStamp('thread-mode-catalog', _threadModeCatalogRevision)],
      effect: EffectPoint.nextTurn,
    ),
  );

  StudioFailure _demoModeFailure(
    StudioFailureCode code,
    String message, {
    required bool retryable,
  }) => StudioFailure(
    code: code,
    message: message,
    retryable: retryable,
    correlationId: 'demo-mode-${newStudioCorrelationId()}',
  );

  WorkflowPreviewSnapshot _demoWorkflowPreview(WorkflowPreviewRequest request) {
    final workflow = request.document.definition.workflow;
    if (workflow == null) {
      return WorkflowPreviewSnapshot(
        accepted: false,
        message: 'This Mode has no workflow',
        path: request.path,
        terminal: false,
      );
    }
    final states = {for (final state in workflow.states) state.id: state};
    if (!states.containsKey(workflow.initialStateId)) {
      return WorkflowPreviewSnapshot(
        accepted: false,
        message: 'Initial state ${workflow.initialStateId} does not exist',
        path: request.path,
        terminal: false,
      );
    }
    final path = request.path.isEmpty
        ? <String>[workflow.initialStateId]
        : List<String>.of(request.path);
    for (final stateId in path) {
      if (!states.containsKey(stateId)) {
        return WorkflowPreviewSnapshot(
          accepted: false,
          message: 'Unknown state $stateId',
          path: path,
          terminal: false,
        );
      }
    }
    final target = request.targetStateId;
    if (target != null && target != path.last) {
      final planned = _demoTransitionPath(
        workflow,
        from: path.last,
        to: target,
      );
      if (planned == null) {
        return WorkflowPreviewSnapshot(
          accepted: false,
          message: 'No transition path reaches $target',
          currentState: states[path.last],
          path: path,
          terminal: states[path.last]!.kind == WorkflowStateKind.finalState,
        );
      }
      path.addAll(planned);
    }
    final current = states[path.last]!;
    return WorkflowPreviewSnapshot(
      accepted: true,
      message: 'Workflow preview reached ${current.title}',
      currentState: current,
      transitions: [
        for (final transition in workflow.transitions)
          if (transition.sourceStateId == current.id) transition,
      ],
      path: path,
      terminal: current.kind == WorkflowStateKind.finalState,
    );
  }

  List<String>? _demoTransitionPath(
    WorkflowDefinition workflow, {
    required String from,
    required String to,
  }) {
    final queue = <List<String>>[
      [from],
    ];
    final visited = <String>{from};
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = path.last;
      for (final transition in workflow.transitions) {
        if (transition.sourceStateId != current) continue;
        final next = transition.targetStateId;
        if (!visited.add(next)) continue;
        final candidate = [...path, next];
        if (next == to) return candidate.skip(1).toList();
        queue.add(candidate);
      }
    }
    return null;
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    if (lspActivityLoop && topic == const LspTopic()) {
      _startLspActivityLoop();
    }
    var detached = false;
    var baselineEmitted = false;
    final pending = <ProductTopicEventPayload>[];
    late final StreamController<ProductTopicFrame> controller;
    late final void Function(ProductTopicEventPayload) sink;

    void detach() {
      if (detached) return;
      detached = true;
      final sinks = _topicSinks[topic];
      if (sinks != null) {
        sinks.remove(sink);
        if (sinks.isEmpty) _topicSinks.remove(topic);
      }
    }

    void receive(ProductTopicEventPayload payload) {
      if (detached) return;
      if (!baselineEmitted) {
        // 基线尚未交付：本 topic 事件先缓冲，保证先基线后增量（无关领域不进入本 receiver）。
        pending.add(payload);
        return;
      }
      _emitProductFrame(controller, topic, payload);
    }

    sink = receive;

    controller = StreamController<ProductTopicFrame>(
      onListen: () async {
        // receiver 先登记，再取得 canonical 基线：期间本 topic 的事件不丢。
        (_topicSinks[topic] ??= <void Function(ProductTopicEventPayload)>{})
            .add(receive);
        try {
          final baseline = await _demoTopicBaseline(topic);
          if (detached) return;
          baselineEmitted = true;
          controller.add(baseline);
          for (final payload in pending) {
            _emitProductFrame(controller, topic, payload);
          }
          pending.clear();
        } catch (error, stackTrace) {
          if (!detached) {
            controller.addError(error, stackTrace);
          }
        }
      },
      onCancel: () async {
        detach();
      },
    );
    return controller.stream;
  }

  /// 把一个 owner 事实发布给该 topic 的已登记 receiver；无接收者时不缓冲。
  void _publishProductPayload(ProductTopicEventPayload payload) {
    if (_runtimeExiting) return;
    for (final entry in _accountObservations.entries.toList()) {
      final source = switch (entry.value) {
        AccountSummariesTarget() ||
        AccountDetailTarget() => const SettingsConfigTopic(),
        AccountModelsTarget() => const ModelCatalogTopic(),
        AccountUsageTarget() => const AccountUsageTopic(),
        AcpAuthTarget() => const AcpAuthTopic(),
        AcpInstallTarget() => const AcpInstallTopic(),
      };
      if (source == payload.topic) entry.key.notify();
    }
    final sinks = _topicSinks[payload.topic];
    if (sinks == null || sinks.isEmpty) return;
    for (final sink in List.of(sinks)) {
      sink(payload);
    }
  }

  /// 把 payload 包装成 typed Data 帧交付给 receiver。
  void _emitProductFrame(
    StreamController<ProductTopicFrame> controller,
    ProductTopic topic,
    ProductTopicEventPayload payload,
  ) {
    _productEventSequence += 1;
    controller.add(
      ProductTopicDataFrame(
        topic: topic,
        event: ProductTopicEventEnvelope(
          eventId: 'demo-${_productEventSequence.toString().padLeft(6, '0')}',
          sequence: BigInt.from(_productEventSequence),
          createdAt: DateTime.now(),
          payload: payload,
        ),
      ),
    );
  }

  /// Demo 基线从当前内存事实派生；与生产路径一致按领域 revision 表达。
  Future<ProductTopicBaselineFrame> _demoTopicBaseline(
    ProductTopic topic,
  ) async {
    final ProductTopicBaselineState baseline = switch (topic) {
      ProjectDirectoryTopic() => ProjectDirectoryBaseline(
        _demoProjectDirectory(),
      ),
      ThreadDirectoryTopic() => ThreadDirectoryBaseline(_demoDirectoryPage()),
      AgentDirectoryTopic() => AgentDirectoryBaseline(_demoAgentDirectory()),
      SettingsConfigTopic() => SettingsConfigBaseline(_demoSettingsState()),
      ModelCatalogTopic() => ModelCatalogBaseline(_demoSettingsState()),
      RecoveryTopic() => RecoveryBaseline(_demoRecoveryState()),
      McpTopic() => McpBaseline(_demoMcpState()),
      LspTopic() => LspBaseline(_demoLspState()),
      SkillsTopic(:final projectId) => SkillsBaseline(
        _demoSkillsState(projectId, _skillsRevision),
      ),
      ThreadModeCatalogTopic() => ThreadModeCatalogBaseline(
        _demoThreadModeCatalog(),
      ),
      AccountUsageTopic() => AccountUsageBaseline(_demoAccountUsageState()),
      SessionCostsTopic(:final rootThreadId) => SessionCostsBaseline(
        _demoSessionCosts(rootThreadId),
      ),
      UpdaterTopic() => UpdaterBaseline(_demoUpdaterState()),
      PersistenceTopic() => PersistenceBaseline(_demoPersistenceState()),
      PersistenceQueueTopic() => PersistenceQueueBaseline(
        _demoPersistenceQueueState(),
      ),
      AgentProfilesTopic() => AgentProfilesBaseline(
        readAgentProfilesStateSync(),
      ),
      AcpAuthTopic() => AcpAuthBaseline(_demoAcpAuth.snapshot),
      AcpInstallTopic() => AcpInstallBaseline(_demoInstallSnapshot()),
      BotsTopic() => BotsBaseline(_demoBotsState()),
    };
    final revision = switch (baseline) {
      ProjectDirectoryBaseline(:final state) => state.revision,
      ThreadDirectoryBaseline(:final page) => page.revision,
      AgentDirectoryBaseline(:final state) => state.revision,
      SettingsConfigBaseline(:final state) => state.revision,
      ModelCatalogBaseline(:final state) => state.modelCatalogRevision,
      RecoveryBaseline(:final state) => state.revision,
      McpBaseline(:final state) => state.revision,
      LspBaseline(:final state) => state.revision,
      SkillsBaseline(:final state) => state.revision,
      ThreadModeCatalogBaseline(:final state) => state.revision,
      AccountUsageBaseline(:final state) => state.revision,
      SessionCostsBaseline(:final state) => state.revision,
      UpdaterBaseline(:final state) => state.revision,
      PersistenceBaseline(:final state) => state.revision,
      PersistenceQueueBaseline(:final state) => state.revision,
      AgentProfilesBaseline(:final state) => state.revision,
      AcpAuthBaseline(:final state) => state.revision,
      AcpInstallBaseline(:final state) => state.revision,
      BotsBaseline(:final state) => state.revision,
    };
    return ProductTopicBaselineFrame(
      topic: topic,
      revision: revision,
      state: baseline,
    );
  }

  /// 周期发布 LSP 索引活动状态：40→55→70→85→100 后回到 idle，再循环。
  /// 每步递增 revision，保证 reducer 的 meta.isNewerThan 校验通过。
  void _startLspActivityLoop() {
    if (_runtimeExiting || _lspActivityTimer != null) return;
    const cycle = [40, 55, 70, 85, 100, null];
    var index = 0;
    _lspActivityTimer = Timer.periodic(lspActivityStepDelay, (_) {
      _lspRevision += 1;
      final percentage = cycle[index];
      _lspActivityPercentage = percentage;
      _publishProductPayload(LspStateChangedPayload(_demoLspState()));
      index = (index + 1) % cycle.length;
    });
  }

  @override
  Future<StudioThread> readThread(String threadId) async =>
      _demoWorkspace(threadId).thread;

  /// Thread 首帧只暴露当前状态：正文由内容连接的分页/尾部交付。
  ThreadWorkspace _snapshotOf(ThreadWorkspace workspace) {
    return workspace.copyWith(latestTurn: null);
  }

  /// 内容连接：正文（含流式）只经它交给 UI，与状态流相互独立。
  @override
  Future<ConversationFeed> openConversationFeed(String threadId) async {
    _ensureDemoRunning();
    if (!_workspaces.containsKey(threadId)) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Unknown Demo conversation',
        retryable: false,
        correlationId: 'demo-conversation-not-found',
      );
    }
    final connection = _DemoConversationFeed(this, threadId);
    _ownedConversationFeeds.add(connection);
    final factory = _conversationFeedFactory;
    // 工厂拿到的是真实连接：注入者只包装故障点，不会再次回到 openConversationFeed。
    if (factory == null) return connection;
    final opening = Completer<void>();
    _openingConversationFeeds.add(opening.future);
    try {
      final feed = await factory(threadId, connection);
      _ownedConversationFeeds.add(feed);
      if (_runtimeExiting) {
        await _closeDemoConversation(feed);
        await connection.close();
        throw _conversationClosedFailure;
      }
      return feed;
    } catch (_) {
      await connection.close();
      rethrow;
    } finally {
      opening.complete();
      _openingConversationFeeds.remove(opening.future);
    }
  }

  /// 测试专用：包装内容连接，用于故障注入（首帧失败、增量失败、EOF、慢打开）。
  ///
  /// 收到的是 demo 的真实连接，只替换故障点；状态流、目录与正文事实仍是 demo 的实现，
  /// 因此注入的是生命周期交错而不是另一套业务状态。
  Future<ConversationFeed> Function(
    String threadId,
    ConversationFeed connection,
  )?
  _conversationFeedFactory;

  @visibleForTesting
  set conversationFeedFactory(
    Future<ConversationFeed> Function(
      String threadId,
      ConversationFeed connection,
    )?
    factory,
  ) {
    _conversationFeedFactory = factory;
  }

  /// 测试夹具：把 demo 的 canonical 内存条目写成给定内容。
  ///
  /// 真实运行时这些条目由脚本化的 prompt 流程写入；这里只准备内存条目，内容仍然只经
  /// [openConversationFeed] 的连接（有界尾部 + 页 + 详情）交付，不绕过内容契约。
  @visibleForTesting
  void seedConversationItems(
    String threadId,
    Iterable<ConversationItem> items,
  ) {
    for (final item in items) {
      _upsertChatItem(threadId, item);
    }
  }

  /// 通过 Demo 自身权威发布点准备状态事实；没有 GUI demand 时也继续更新业务。
  @visibleForTesting
  ThreadWorkspace seedConversationState(
    String threadId,
    ThreadWorkspaceUpdate update,
  ) {
    _ensureDemoRunning();
    _demoWorkspace(threadId);
    _emitThreadUpdate(threadId, update);
    return _demoWorkspace(threadId);
  }

  /// 测试夹具：撤下一条 demo canonical 条目（真实 `Remove` 的环境准备）。
  ///
  /// 与 [seedConversationItems] 同一环境准备 seam：只改 demo 的 canonical 内存条目与通知，
  /// 发布仍只经 [openConversationFeed] 的连接，不新增业务删除 API。
  @visibleForTesting
  void retractConversationItem(String threadId, String itemId) {
    final items = [...?_threadItems[threadId]];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    items.removeAt(index);
    _threadItems[threadId] = items;
    _notifyItemsChanged(threadId);
    _publishContent(
      threadId,
      _DemoItemChange(
        version: _contentVersionOf(threadId),
        itemId: itemId,
        removed: true,
      ),
    );
  }

  /// 按活动身份读取完整详情。demo 没有独立的正文投影，活动本身即为可用事实。
  @override
  Future<ThreadActivityDetail> readThreadActivityDetail(
    String threadId,
    String activityId,
  ) async {
    final workspace = _workspaces[threadId];
    if (workspace == null) {
      throw StateError('unknown demo thread $threadId');
    }
    final activity = workspace.activity;
    if (activity == null) {
      return EndedThreadActivityDetail(
        threadId: threadId,
        activityId: activityId,
      );
    }
    if (activity.identity != activityId) {
      return SupersededThreadActivityDetail(
        activity: activity,
        requestedActivityId: activityId,
      );
    }
    return CurrentThreadActivityDetail(activity: activity);
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) => _submitPrompt(
    threadId,
    input,
    expectedModelRouteRevision: expectedModelRouteRevision,
  );

  @override
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) async {
    return [
      for (final source in sources)
        _demoAttachmentDraft(source, ++_attachmentSequence),
    ].map((draft) {
      _attachmentDrafts[draft.id] = draft;
      return draft;
    }).toList();
  }

  @override
  Future<bool> removeAttachmentDraft(String draftId) async =>
      _attachmentDrafts.remove(draftId) != null;

  @override
  Future<Uint8List> readAttachmentDraft(String draftId) async {
    if (!_attachmentDrafts.containsKey(draftId)) {
      throw StateError('unknown demo attachment draft');
    }
    return Uint8List(0);
  }

  @override
  Future<Uint8List> readThreadAttachment(
    String threadId,
    String attachmentId,
  ) async => Uint8List(0);

  Future<SubmitPromptReceipt> _submitPrompt(
    String threadId,
    StudioPromptInput input, {
    int? expectedModelRouteRevision,
  }) async {
    _ensureDemoRunning();
    final trimmed = input.text.trim();
    if (trimmed.isEmpty && input.attachmentDraftIds.isEmpty) {
      throw ArgumentError.value(input.text, 'text', 'empty');
    }
    final workspace = _workspaces[threadId];
    if (workspace == null) throw StateError('unknown demo thread $threadId');
    final route = workspace.runtime.modelRoute;
    if (expectedModelRouteRevision != null &&
        route?.revision != expectedModelRouteRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'The Thread model route changed before input admission',
        retryable: false,
        correlationId: 'demo-prompt-route-conflict',
      );
    }
    if (route == null || !route.available) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The Thread model route is unavailable',
        retryable: false,
        correlationId: 'demo-prompt-route-unavailable',
      );
    }
    final activeTurn = workspace.activeTurn;
    if (activeTurn != null && activeTurn.state.isBusy) {
      _interruptDemoTurn(threadId, activeTurn.turnId);
    }
    // No await separates the route CAS and admission. Demo follows the Thread
    // route, rather than re-reading role defaults after the user's intent.
    _emitThreadUpdate(
      threadId,
      ThreadRuntimeUpdate(
        runtime: workspace.runtime.copyWith(modelId: route.modelId),
        todo: null,
      ),
    );
    final generation = _promptGenerations.update(
      threadId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final turnId = 'demo-turn-${++_turnSequence}';
    final now = DateTime.now();
    final receipt = SubmitPromptReceipt(
      threadId: threadId,
      inputId: input.inputId,
      cursor: workspace.revision + 1,
    );
    // New content claims the pending continuation point instead of adding a
    // second control input (§4.2 replacement authorization).
    _demoContinuationPoints.remove(threadId);
    // 模拟服务同样只在成功受理后推进最近用户消息时间；拒绝路径在上方抛出、不推进。
    _advanceDemoLastUserMessage(threadId, now);
    _upsertChatItem(
      threadId,
      _messageItem(
        id: input.inputId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        channel: ThreadTextChannel.user,
        text: trimmed,
        createdAt: now,
        attachments: [
          for (final id in input.attachmentDraftIds)
            if (_attachmentDrafts[id] case final draft?)
              ThreadAttachmentView(
                id: draft.id,
                modality: draft.modality,
                mediaType: draft.mediaType,
                filename: draft.filename,
                width: draft.width,
                height: draft.height,
                byteSize: draft.byteSize,
              ),
        ],
      ),
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          inputId: input.inputId,
          threadId: threadId,
          revision: 0,
          state: RunningStudioTurnState(
            startedAt: now.millisecondsSinceEpoch ~/ 1000,
            activity: StudioTurnActivity.thinking,
          ),
          updatedAt: now,
        ),
      ),
    );
    // 脚本化活动：提交后进入“思考中”（等待 API / 开始 reasoning）。
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: input.inputId,
      kind: ThreadActivityKind.thinking,
    );
    _runDemoJob(
      () => _completePrompt(
        threadId: threadId,
        turnId: turnId,
        trimmedPrompt: trimmed,
        generation: generation,
        startedAt: now,
      ),
    );
    return receipt;
  }

  Future<void> _completePrompt({
    required String threadId,
    required String turnId,
    required String trimmedPrompt,
    required int generation,
    required DateTime startedAt,
    void Function()? onAdmitted,
  }) async {
    await _waitDemo(promptStartDelay);
    if (_promptGenerations[threadId] != generation) return;
    // 到这里模型请求才真正准入：控制输入在这一刻被消费，之后停止不会改写它。
    onAdmitted?.call();
    final reasoningId = '$turnId:reasoning';
    const reasoningSummary =
        '## Inspecting the request\n\nChecking the live ThreadItem projection.';
    const reasoningContent =
        'The account is folding summary and raw reasoning independently.';
    _upsertChatItem(
      threadId,
      _demoItem(
        id: reasoningId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        content: _demoThinking(
          summary: [],
          content: [],
          lifecycle: StreamingThreadContentView(),
        ),
      ),
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      revision: 1,
      field: const ThreadThinkingSummaryFieldView(0),
      text: '## Inspecting',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      revision: 2,
      field: const ThreadThinkingSummaryFieldView(0),
      text: ' the request\n\nChecking the live ThreadItem projection.',
    );
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      revision: 3,
      field: const ThreadThinkingContentFieldView(0),
      text: reasoningContent,
    );
    // 脚本化活动：reasoning 已有内容时显示“思考中”+最新非空逻辑行。
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: null,
      kind: ThreadActivityKind.thinking,
      summary: 'Checking the live ThreadItem projection.',
    );
    final liveReasoning = _itemsOf(threadId)
        .firstWhere((item) => item.id == reasoningId);
    final reasoningCompletedAt = DateTime.now();
    _upsertChatItem(
      threadId,
      _demoRevise(
        liveReasoning,
        revision: 4,
        updatedAt: reasoningCompletedAt,
        content: _demoThinking(
          summary: const [reasoningSummary],
          content: const [reasoningContent],
          lifecycle: CompletedThreadContentView(reasoningCompletedAt),
        ),
      ),
    );
    final commentaryId = '$turnId:commentary';
    _upsertChatItem(
      threadId,
      _demoItem(
        id: commentaryId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        content: _demoText(
          channel: ThreadTextChannel.commentary,
          text: '',
          attachments: [],
          lifecycle: StreamingThreadContentView(),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: commentaryId,
      revision: 1,
      field: const ThreadTextFieldView(),
      text: '正在逐段核对 Timeline',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: commentaryId,
      revision: 2,
      field: const ThreadTextFieldView(),
      text: ' 的 typed delta。',
    );
    final commentaryCompletedAt = DateTime.now();
    final liveCommentary = _itemsOf(threadId)
        .firstWhere((item) => item.id == commentaryId);
    _upsertChatItem(
      threadId,
      _demoRevise(
        liveCommentary,
        revision: 3,
        updatedAt: commentaryCompletedAt,
        content: _demoText(
          channel: ThreadTextChannel.commentary,
          text: '正在逐段核对 Timeline 的 typed delta。',
          attachments: const [],
          lifecycle: CompletedThreadContentView(commentaryCompletedAt),
        ),
      ),
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 1,
          state: RunningStudioTurnState(
            startedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            activity: StudioTurnActivity.runningTool,
          ),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    // 脚本化活动：工具前台显示“执行中”+完整命令行预览。
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: null,
      kind: ThreadActivityKind.runningTool,
      summary: 'cargo test -p pl-model --test provider_wire',
    );
    final toolId = '$turnId:tool';
    _upsertChatItem(
      threadId,
      _demoItem(
        id: toolId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        content: _demoTool(
          invocation: ConversationToolInvocation(
            toolCallId: '$turnId:tool-call',
            name: 'exec',
          ),
          lifecycle: const ConversationToolStarted(),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 1,
      field: const ThreadToolArgumentsFieldView(),
      text: '{"command":"cargo test -p pl-model ',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 2,
      field: const ThreadToolArgumentsFieldView(),
      text: '--test provider_wire"}',
    );
    final streamedTool = _itemsOf(threadId)
        .firstWhere((item) => item.id == toolId);
    final streamedToolState =
        streamedTool.descriptor as ConversationToolDescriptor;
    _upsertChatItem(
      threadId,
      _demoRevise(
        streamedTool,
        revision: 3,
        updatedAt: DateTime.now(),
        content: _demoTool(
          invocation: streamedToolState.invocation,
          arguments: streamedTool
              .fieldFor(const ThreadToolArgumentsFieldView())!
              .text,
          lifecycle: const ConversationToolRunning(),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 4,
      field: const ThreadToolResultFieldView(),
      text: 'running widget tests...\n',
    );
    await _waitDemo(promptToolDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 5,
      field: const ThreadToolResultFieldView(),
      text: '[stderr] analyzer warnings: 0\n',
    );
    final runningTool = _itemsOf(threadId)
        .firstWhere((item) => item.id == toolId);
    final runningToolState =
        runningTool.descriptor as ConversationToolDescriptor;
    final toolCompletedAt = DateTime.now();
    _upsertChatItem(
      threadId,
      _demoRevise(
        runningTool,
        revision: 6,
        updatedAt: toolCompletedAt,
        content: _demoTool(
          invocation: runningToolState.invocation,
          lifecycle: ConversationToolSucceeded(
            completedAt: toolCompletedAt,
            output: const ConversationToolOutputDescriptor(attachments: []),
          ),
          arguments: runningTool
              .fieldFor(const ThreadToolArgumentsFieldView())!
              .text,
          result: 'running widget tests...\n[stderr] analyzer warnings: 0\nAll widget tests passed.',
        ),
      ),
    );
    final finalId = '$turnId:final';
    _upsertChatItem(
      threadId,
      _demoItem(
        id: finalId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        content: _demoText(
          channel: ThreadTextChannel.finalAnswer,
          text: '',
          attachments: [],
          lifecycle: StreamingThreadContentView(),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: finalId,
      revision: 1,
      field: const ThreadTextFieldView(),
      text: 'Demo response for: **$trimmedPrompt**',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    const finalSuffix = '\n\n- reasoning、tool output 与 Plan 都直接来自 typed delta';
    _appendChatContent(
      threadId,
      itemId: finalId,
      revision: 2,
      field: const ThreadTextFieldView(),
      text: finalSuffix,
    );
    final finalCompletedAt = DateTime.now();
    final liveFinal = _itemsOf(threadId)
        .firstWhere((item) => item.id == finalId);
    _upsertChatItem(
      threadId,
      _demoRevise(
        liveFinal,
        revision: 3,
        updatedAt: finalCompletedAt,
        content: _demoText(
          channel: ThreadTextChannel.finalAnswer,
          text: 'Demo response for: **$trimmedPrompt**$finalSuffix',
          attachments: const [],
          lifecycle: CompletedThreadContentView(finalCompletedAt),
        ),
      ),
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 2,
          state: CompletedStudioTurnState(
            startedAt: null,
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            completion: StudioTurnCompletion.normal,
          ),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    // Turn 结束：清空当前活动。
    _clearActivity(threadId);
  }

  @override
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) async {
    final execution = _demoExecutionOf(threadId);
    if (execution == null || execution.id != executionId) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The observed execution is no longer current',
        retryable: false,
        correlationId: 'demo-stop-stale-execution',
        reason: StudioFailureReason.staleExecution,
      );
    }
    final turnId = execution.turnId;
    final stopped = turnId != null && _interruptDemoTurn(threadId, turnId);
    return StopThreadCommandReply(
      threadId: threadId,
      executionId: executionId,
      stopped: stopped,
      receipt: _demoReceipt(
        operationId,
        changed: stopped,
        targets: const [],
        effect: EffectPoint.immediate,
        effective: false,
        requiresIdentityObservation: true,
      ),
    );
  }

  /// demo 的当前执行身份：与生产一样由状态里的执行记录给出，而不是轮次投影。
  AgentExecutionView? _demoExecutionOf(String threadId) {
    final active = _workspaces[threadId]?.activeTurn;
    if (active == null || !active.state.isBusy) return null;
    return AgentExecutionView(
      id: _demoExecutionId(active.turnId),
      phase: AgentExecutionPhase.running,
      turnId: active.turnId,
    );
  }

  static String _demoExecutionId(String turnId) => 'demo-exec:$turnId';

  @override
  Future<ContinueThreadCommandReply> continueThread(
    String threadId,
    String continuationId, {
    required int expectedModelRouteRevision,
    required OperationId operationId,
  }) async {
    _ensureDemoRunning();
    final workspace = _workspaces[threadId];
    if (workspace == null) throw StateError('unknown demo thread $threadId');
    final thread = _sortedDirectoryThreads()
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread != null && !thread.isRoot) {
      throw const StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message:
            'A child agent is continued and instructed by the main session',
        retryable: false,
        correlationId: 'demo-child-requires-parent-scheduling',
        reason: StudioFailureReason.childThreadRequiresParentScheduling,
      );
    }
    final existing = _demoContinuations[operationId.value];
    if (existing != null) {
      // Same operation identity answers the original admission, but only for the very same
      // request facts: a different target, continuation or route revision is a conflict and
      // must never inherit another request's receipt.
      if (!existing.matches(
        threadId,
        continuationId,
        expectedModelRouteRevision,
      )) {
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'This operation identity already accepted a different continuation request',
          retryable: false,
          correlationId: 'demo-continuation-identity-conflict',
          reason: StudioFailureReason.continuationUnavailable,
        );
      }
      return ContinueThreadCommandReply(
        threadId: existing.threadId,
        inputId: existing.inputId,
        continuationId: existing.continuationId,
        cursor: existing.acceptedSequence,
        receipt: existing.receipt,
      );
    }
    if (_demoExecutionOf(threadId) != null) {
      throw const StudioFailure(
        code: StudioFailureCode.busy,
        message: 'The Thread is still executing or settling',
        retryable: true,
        correlationId: 'demo-continue-execution-in-progress',
        reason: StudioFailureReason.executionInProgress,
      );
    }
    final point = _demoContinuationPoints[threadId];
    if (continuationId.isEmpty || point == null) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'This Thread has no continuation to claim',
        retryable: false,
        correlationId: 'demo-continue-unavailable',
        reason: StudioFailureReason.continuationUnavailable,
      );
    }
    if (point.claimed) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The continuation point is already claimed',
        retryable: false,
        correlationId: 'demo-continue-claimed',
        reason: StudioFailureReason.continuationClaimed,
      );
    }
    if (point.id != continuationId) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The observed continuation point is no longer current',
        retryable: false,
        correlationId: 'demo-continue-stale',
        reason: StudioFailureReason.staleContinuation,
      );
    }
    if (workspace.runtime.modelRoute?.revision != expectedModelRouteRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'The Thread model route changed before continuation admission',
        retryable: false,
        correlationId: 'demo-continue-route-conflict',
        reason: StudioFailureReason.staleContinuation,
      );
    }
    // The claim is published as a canonical fact before the Turn exists.
    _demoContinuationPoints[threadId] = ContinuationView(
      id: point.id,
      sourceTurnId: point.sourceTurnId,
      reason: point.reason,
      createdAt: point.createdAt,
      claimed: true,
    );
    final generation = _promptGenerations.update(
      threadId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final turnId = 'demo-turn-${++_turnSequence}';
    final now = DateTime.now();
    final receipt = _demoReceipt(
      operationId,
      changed: true,
      targets: const [],
      effect: EffectPoint.immediate,
      effective: false,
      requiresIdentityObservation: true,
    );
    final accepted = _DemoContinuation(
      threadId: threadId,
      inputId: operationId.value,
      continuationId: continuationId,
      expectedModelRouteRevision: expectedModelRouteRevision,
      acceptedSequence: workspace.revision + 1,
      receipt: receipt,
    );
    _demoContinuations[operationId.value] = accepted;
    while (_demoContinuations.length > 64) {
      _demoContinuations.remove(_demoContinuations.keys.first);
    }
    // Admitted, not started: the canonical Turn is what proves effect.
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          inputId: operationId.value,
          threadId: threadId,
          revision: 0,
          state: RunningStudioTurnState(
            startedAt: now.millisecondsSinceEpoch ~/ 1000,
            activity: StudioTurnActivity.thinking,
          ),
          updatedAt: now,
        ),
      ),
    );
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: operationId.value,
      kind: ThreadActivityKind.thinking,
    );
    // Consumed at the model-request admission inside the prompt runner, not at publication
    // and not at completion: a stop before admission leaves the operation pending.
    _runDemoJob(
      () => _completePrompt(
        threadId: threadId,
        turnId: turnId,
        trimmedPrompt: '继续未完成的任务',
        generation: generation,
        startedAt: now,
        onAdmitted: () => accepted.turnId = turnId,
      ),
    );
    // The control input was consumed by the new Turn, so the point is gone.
    _demoContinuationPoints.remove(threadId);
    final current = _workspaces[threadId];
    if (current != null && current.runtime.continuation != null) {
      _emitThreadUpdate(
        threadId,
        ThreadRuntimeUpdate(
          runtime: current.runtime.copyWith(continuation: null),
          todo: current.todo,
        ),
      );
    }
    return ContinueThreadCommandReply(
      threadId: threadId,
      inputId: operationId.value,
      continuationId: accepted.continuationId,
      cursor: accepted.acceptedSequence,
      receipt: receipt,
    );
  }

  @override
  Future<ContinuationOperationView> readContinuationOperation(
    String threadId,
    String operationId,
  ) async {
    final accepted = _demoContinuations[operationId];
    if (accepted == null || accepted.threadId != threadId) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'No accepted continuation operation carries this identity',
        retryable: false,
        correlationId: 'demo-continuation-not-found',
      );
    }
    return ContinuationOperationView(
      threadId: accepted.threadId,
      operationId: operationId,
      inputId: accepted.inputId,
      continuationId: accepted.continuationId,
      acceptedSequence: accepted.acceptedSequence,
      state: accepted.turnId == null
          ? const PendingContinuation()
          : ConsumedContinuation(accepted.turnId!),
      durable: false,
      receipt: accepted.receipt,
    );
  }

  @override
  Future<List<ChildInteractionSummary>> readChildInteractions(
    String hostThreadId,
  ) async {
    final summaries = <ChildInteractionSummary>[];
    for (final workspace in _workspaces.values) {
      if (workspace.thread.parentThreadId != hostThreadId) continue;
      for (final interaction in workspace.interactions) {
        // 子会话的计划请求是诊断事实：生产侧的目录与决议入口都按计划确认问题身份排除它，
        // 演示数据据同一判据不把它提供给主会话决议。
        if (interaction.isPlanConfirmation) continue;
        summaries.add(
          ChildInteractionSummary(
            childThreadId: workspace.thread.id,
            interactionId: interaction.id,
            kind: interaction.kind,
            revision: interaction.revision,
            interaction: interaction,
          ),
        );
      }
    }
    return summaries;
  }

  bool _interruptDemoTurn(String threadId, String turnId) {
    final active = _workspaces[threadId]?.activeTurn;
    if (active == null || !active.state.isBusy) return false;
    if (active.turnId != turnId) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Expected Turn does not match the active Turn',
        retryable: false,
        correlationId: 'demo-interrupt-turn-identity',
      );
    }
    // A user stop leaves a continuation point behind; the next explicit
    // continuation (or new content) claims it.
    _demoContinuationPoints[threadId] = ContinuationView(
      id: 'demo-continuation:${++_continuationSequence}',
      sourceTurnId: turnId,
      reason: ContinuationReason.userStop,
      createdAt: DateTime.now(),
      claimed: false,
    );
    _promptGenerations.update(
      threadId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 2,
          state: CancelledStudioTurnState(
            startedAt: null,
            requestedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            cause: const UserRequestedTurnCancellation(),
          ),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    // 打断结束 Turn：清空当前活动。
    _clearActivity(threadId);
    return true;
  }

  @override
  Future<InteractionCommandReply> respondInteraction(
    String hostThreadId,
    String interactionId,
    int expectedRevision,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  }) async {
    _ensureWorkspaceFixture();
    final facts = switch (resolution) {
      UserInputResolutionCommand(:final answers) => <Object?>[
        'user-input',
        {
          for (final answer in answers)
            answer.questionId: List<String>.of(answer.answers),
        },
      ],
      ToolApprovalResolutionCommand(:final decision, :final reason) =>
        <Object?>['tool-approval', decision, reason],
    };
    final previous = _resolvedInteractions[interactionId];
    final interaction = [
      for (final workspace in _workspaces.values) ...workspace.interactions,
    ].where((item) => item.id == interactionId).firstOrNull;
    // A terminal replay is still decided from its original interaction identity, so
    // hosting and identity are validated before any idempotent reply is returned.
    final decided = interaction ?? previous?.interaction;
    if (decided == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Interaction is unavailable',
        retryable: false,
        correlationId: 'demo-interaction-not-found',
      );
    }
    // The decision is submitted under the hosting main session: a root session may
    // decide its own questions and its direct child's handed-over ones. A child is
    // never a host for its own interaction.
    final host = _workspaces[hostThreadId]?.thread;
    if (host == null || host.parentThreadId != null) {
      throw const StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message: 'Only a main session can decide an interaction',
        retryable: false,
        correlationId: 'demo-interaction-not-hosted',
        reason: StudioFailureReason.interactionNotHosted,
      );
    }
    // A child Plan request stays a diagnostic: it is not offered in the main session
    // projection and its decision entry rejects it too, exactly like the production
    // handover filter.
    if (decided.threadId != hostThreadId && decided.isPlanConfirmation) {
      throw const StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message:
            'A child plan confirmation cannot be decided from the main session',
        retryable: false,
        correlationId: 'demo-child-plan-diagnostic',
        reason: StudioFailureReason.interactionNotHosted,
      );
    }
    final owner = _workspaces[decided.threadId]?.thread;
    final hosted =
        decided.threadId == hostThreadId ||
        owner?.parentThreadId == hostThreadId;
    if (!hosted) {
      throw const StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message: 'The interaction is not hosted by this session; decide it from its main session',
        retryable: false,
        correlationId: 'demo-interaction-not-hosted',
        reason: StudioFailureReason.interactionNotHosted,
      );
    }
    // Only the current revision may be decided: an older card must not overwrite a newer
    // decision, and a newer expectation proves this client is behind. A terminal replay
    // must satisfy the same check against the revision it was decided at.
    if (expectedRevision != decided.revision) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The interaction revision is no longer current',
        retryable: false,
        correlationId: 'demo-interaction-stale',
        reason: StudioFailureReason.staleInteraction,
      );
    }
    if (previous != null) {
      if (!_sameDemoFacts(previous.resolution, facts) ||
          previous.interaction.threadId != decided.threadId) {
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'Interaction already has a different terminal resolution',
          retryable: false,
          correlationId: 'demo-interaction-conflict',
        );
      }
      return InteractionCommandReply(
        interaction: previous.interaction,
        receipt: previous.receipt,
      );
    }
    if (interaction == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Interaction is unavailable',
        retryable: false,
        correlationId: 'demo-interaction-not-found',
      );
    }
    final receipt = _demoReceipt(
      operationId,
      changed: true,
      targets: const [],
      effect: EffectPoint.immediate,
      requiresIdentityObservation: true,
    );
    _resolvedInteractions[interactionId] = (
      interaction: interaction,
      resolution: facts,
      receipt: receipt,
    );
    // Bound terminal receipts without inventing a new active interaction owner.
    while (_resolvedInteractions.length > 128) {
      _resolvedInteractions.remove(_resolvedInteractions.keys.first);
    }
    _emitThreadUpdate(
      interaction.threadId,
      ThreadInteractionUpdate(interaction: interaction, pending: false),
    );
    if (interaction.kind == InteractionKind.userInput) {
      _advanceDemoLastUserMessage(interaction.threadId, DateTime.now());
    }
    return InteractionCommandReply(interaction: interaction, receipt: receipt);
  }

  @override
  Future<SettingsCommandReply> saveRuntimePermissionMode(
    int expectedSettingsRevision,
    PermissionMode mode, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    _permissionMode = mode;
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> createAccount(
    int expectedSettingsRevision,
    CreateAccountCommand command, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final current = before;
    if (current.accounts.any(
      (account) => account.id == command.identity.accountId,
    )) {
      throw ArgumentError('Account already exists');
    }
    final converted = _accountsFromCreateCommands([
      command,
    ], catalog: _accountCatalog);
    _accounts = [
      for (final account in current.accounts) account,
      for (final account in converted)
        account.copyWith(usageQueryRevision: ++_usageIdentitySequence),
    ];
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> setDefaultAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    if (!before.accounts.any((account) => account.id == accountId)) {
      throw StateError('Account is unavailable: $accountId');
    }
    _defaultAccountId = accountId;
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> removeAccountModel(
    int expectedSettingsRevision,
    String accountId,
    String modelId, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    if (modelId.trim().isEmpty) {
      throw StateError('Account modelId must not be empty');
    }
    final accounts = [
      for (final account in before.accounts)
        if (account.id == accountId)
          _demoRemoveManualModel(account, modelId)
        else
          account,
    ];
    if (!accounts.any((account) => account.id == accountId)) {
      throw StateError('unknown demo account: $accountId');
    }
    _accounts = accounts;
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> setAccountModelEnabled(
    int expectedSettingsRevision,
    String accountId,
    String modelId,
    bool enabled, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final account = before.accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null || !account.models.any((m) => m.modelId == modelId)) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Account model not found',
        retryable: false,
        correlationId: 'demo-model-enabled',
      );
    }
    _accounts = [
      for (final a in before.accounts)
        if (a.id != accountId)
          a
        else
          a.copyWith(
            modelEnabledOverrides: {
              ...a.modelEnabledOverrides,
              modelId: enabled,
            },
            models: [
              for (final m in a.models)
                if (m.modelId == modelId) m.copyWith(enabled: enabled) else m,
            ],
          ),
    ];
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> setAccountBillingKind(
    int expectedSettingsRevision,
    String accountId,
    BillingKind? billingKind, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final account = before.accounts.firstWhere((a) => a.id == accountId);
    _accounts = [
      for (final a in before.accounts)
        if (a.id != account.id)
          a
        else
          a.copyWith(
            billingKindOverride: billingKind,
            billingKind: billingKind ?? BillingKind.unknown,
          ),
    ];
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<DelegationModelList> listDelegationModels(
    ListDelegationModelsRequest request,
  ) => Future.error(
    UnsupportedError('Qualified delegation lists require the native Runtime'),
  );

  @override
  Future<DelegationModelDetail> getDelegationModel(
    DelegationModelKey key,
  ) async {
    final account = _demoSettingsState().accounts.firstWhere(
      (a) => a.id == key.accountId,
    );
    final model = account.models.firstWhere((m) => m.modelId == key.modelId);
    return DelegationModelDetail(
      key: key,
      accountName: account.name,
      descriptor: model,
      available: model.enabled && model.matchesType(ModelType.text),
      billingKind: account.billingKind,
      performance: const LocalModelPerformanceSummary(
        sampleCount: 0,
        ttftSampleCount: 0,
      ),
      evaluations: const AgentEvaluationSummary(
        window: 10,
        ratedSamples: 0,
        passed: 0,
        failed: 0,
        notRated: 0,
      ),
      recentEvaluations: const [],
    );
  }

  @override
  Future<SettingsCommandReply> removeAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
    String? replacementAccountId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final current = before;
    if (current.accounts.length <= 1) {
      throw StateError('At least one account is required');
    }
    final replacement =
        replacementAccountId ??
        current.accounts.firstWhere((account) => account.id != accountId).id;
    if (!current.accounts.any((account) => account.id == replacement)) {
      throw StateError('Replacement account is unavailable: $replacement');
    }
    _accounts = [
      for (final account in current.accounts)
        if (account.id != accountId) account,
    ];
    _defaultAccountId = _defaultAccountId == accountId
        ? replacement
        : _defaultAccountId;
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsStateSnapshot> readSettingsState() async =>
      _demoSettingsState();

  @override
  Future<SkillsStateSnapshot> readSkillsState(String projectId) async {
    return _archivedProjectIds.contains(projectId)
        ? _demoSkillsState(projectId, 0, skills: const [])
        : _demoSkillsState(projectId, _skillsRevision);
  }

  @override
  Future<SkillsStateSnapshot> discoverSkills(String projectId) async {
    _skillsRevision += 1;
    final state = await readSkillsState(projectId);
    _publishProductPayload(SkillsStateChangedPayload(state));
    return state;
  }

  @override
  Future<SkillSearchResultView> searchSkills(
    String projectId,
    String query, {
    int limit = 50,
  }) async {
    final snapshot = await readSkillsState(projectId);
    final normalizedQuery = query.trim().toLowerCase();
    final allMatches = snapshot.summaries
        .where(
          (skill) =>
              skill.name.toLowerCase().contains(normalizedQuery) ||
              skill.description.toLowerCase().contains(normalizedQuery),
        )
        .toList();
    return SkillSearchResultView(
      projectId: projectId,
      catalogRevision: snapshot.catalogRevision,
      matches: allMatches.take(limit).toList(),
      truncated: allMatches.length > limit,
    );
  }

  @override
  Future<McpStateSnapshot> readMcpState() async => _demoMcpState();

  @override
  Future<McpStateSnapshot> resetMcpServer(String serverId) async {
    _mcpRevision += 1;
    return _mcpWriteResult();
  }

  @override
  Future<McpStateSnapshot> resetAllMcp() async {
    _mcpRevision += 1;
    return _mcpWriteResult();
  }

  @override
  Future<LspStateSnapshot> readLspState() async => _demoLspState();

  @override
  Future<LspStateSnapshot> probeLspServer(String projectId) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> repairLspServer(
    String projectId,
    String serverId,
  ) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> resetLspServer(
    String projectId,
    String serverId,
  ) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> resetLspWorkspace(String projectId) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  BotsStateSnapshot _demoBotsState() {
    return BotsStateSnapshot(
      revision: _botsRevision,
      updatedAt: 0,
      bots: List<BotSnapshot>.unmodifiable(_bots),
      registration: _registration,
      pendingCredentialOperations:
          List<BotPendingCredentialOperation>.unmodifiable(
            _pendingCredentialOps,
          ),
    );
  }

  BotsStateSnapshot _botsWriteResult() {
    _botsRevision += 1;
    final state = _demoBotsState();
    _publishProductPayload(BotsStateChangedPayload(state));
    return state;
  }

  BotsCommandReply _botsReply(
    OperationId operationId, {
    required bool changed,
  }) {
    final snapshot = _botsWriteResult();
    return BotsCommandReply(
      snapshot: snapshot,
      receipt: _demoReceipt(
        operationId,
        changed: changed,
        targets: [_demoStamp('bots', snapshot.revision)],
        effect: EffectPoint.immediate,
      ),
      stamp: _demoStamp('bots', snapshot.revision),
    );
  }

  BotSnapshot? _findBot(String id) {
    for (final bot in _bots) {
      if (bot.id == id) return bot;
    }
    return null;
  }

  void _replaceBot(BotSnapshot next) {
    final index = _bots.indexWhere((bot) => bot.id == next.id);
    if (index < 0) {
      _bots.add(next);
    } else {
      _bots[index] = next;
    }
  }

  @override
  Future<BotsStateSnapshot> readBots() async => _demoBotsState();

  @override
  Future<BotsCommandReply> saveBot(SaveBotRequest request) async {
    final existing = request.botId == null ? null : _findBot(request.botId!);
    if (existing != null &&
        existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final id = request.botId ?? 'bot-${_bots.length + 1}';
    final credential = switch (request.secret) {
      BotSecretReplace() => BotCredentialAvailability.stored,
      BotSecretClear() => BotCredentialAvailability.missing,
      BotSecretPreserve() =>
        existing?.credential ?? BotCredentialAvailability.missing,
    };
    _replaceBot(
      BotSnapshot(
        id: id,
        name: request.name,
        projectId: request.projectId,
        appId: request.appId,
        platform: BotPlatform.feishuChina,
        enabled: request.enabled,
        toolsEnabled: request.toolsEnabled,
        configRevision: (existing?.configRevision ?? 0) + 1,
        trustedOpenIds: existing?.trustedOpenIds ?? const [],
        trustedChatIds: existing?.trustedChatIds ?? const [],
        connection: existing?.connection ?? const BotConnectionDisabled(),
        credential: credential,
        pairing: existing?.pairing ?? const [],
        canChangeProject: existing?.canChangeProject ?? true,
        canChangeAppId: existing?.canChangeAppId ?? true,
        createdAt: existing?.createdAt ?? 0,
        updatedAt: 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  ) async {
    final attemptId = 'attempt-${request.operationId}';
    _registration = BotRegistrationAttempt(
      attemptId: attemptId,
      name: request.name,
      projectId: request.projectId,
      status: BotRegistrationWaiting(
        attemptId: attemptId,
        verificationUrl: 'https://accounts.feishu.cn/demo-registration',
        expiresAt: 1,
        intervalSeconds: 5,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  ) async {
    final current = _registration;
    if (current != null && current.status is BotRegistrationCommitting) {
      throw StudioFailure(
        code: StudioFailureCode.busy,
        message: 'Registration is committing',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (current != null && current.attemptId == request.attemptId) {
      _registration = BotRegistrationAttempt(
        attemptId: current.attemptId,
        name: current.name,
        projectId: current.projectId,
        status: BotRegistrationCancelled(attemptId: current.attemptId),
        completedBotId: current.completedBotId,
      );
    }
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: request.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision + 1,
        trustedOpenIds: existing.trustedOpenIds,
        trustedChatIds: existing.trustedChatIds,
        connection: request.enabled
            ? const BotConnectionConnected()
            : const BotConnectionDisabled(),
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: existing.pairing,
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> retryBotConnection(
    RetryBotConnectionRequest request,
  ) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: existing.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision,
        trustedOpenIds: existing.trustedOpenIds,
        trustedChatIds: existing.trustedChatIds,
        connection: existing.enabled
            ? const BotConnectionConnected()
            : const BotConnectionDisabled(),
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: existing.pairing,
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> setBotTrustedUser(
    SetBotTrustedUserRequest request,
  ) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final trusted = [...existing.trustedOpenIds];
    if (request.trusted) {
      if (!trusted.contains(request.openId)) trusted.add(request.openId);
    } else {
      trusted.remove(request.openId);
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: existing.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision + 1,
        trustedOpenIds: List<String>.unmodifiable(trusted),
        trustedChatIds: existing.trustedChatIds,
        connection: existing.connection,
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: [
          for (final item in existing.pairing)
            if (item.openId != request.openId) item,
        ],
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> setBotTrustedChat(
    SetBotTrustedChatRequest request,
  ) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final trusted = [...existing.trustedChatIds];
    if (request.trusted) {
      if (!trusted.contains(request.chatId)) trusted.add(request.chatId);
    } else {
      trusted.remove(request.chatId);
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: existing.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision + 1,
        trustedOpenIds: existing.trustedOpenIds,
        trustedChatIds: List<String>.unmodifiable(trusted),
        connection: existing.connection,
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: existing.pairing,
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotConversationPage> listBotConversations(
    ListBotConversationsRequest request,
  ) async {
    final conversations = _botConversations[request.botId] ?? const [];
    return BotConversationPage(
      botId: request.botId,
      conversations: conversations,
    );
  }

  @override
  Future<BotMessagePage> readBotMessages(ReadBotMessagesRequest request) async {
    final key = '${request.botId}/${request.chatId}';
    return BotMessagePage(
      botId: request.botId,
      chatId: request.chatId,
      messages: _botMessages[key] ?? const [],
    );
  }

  @override
  Future<BotSendResult> sendBotMessage(SendBotMessageRequest request) async {
    return BotSendResult(
      operationId: request.operationId,
      botId: request.botId,
      chatId: request.chatId,
      status: BotSendStatus.succeeded,
      segments: [BotSendSegment(index: 0, status: BotSendStatus.succeeded)],
      receipt: _demoReceipt(
        OperationId(request.operationId),
        changed: true,
        targets: const [],
        effect: EffectPoint.immediate,
      ),
    );
  }

  @override
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  ) async {
    final key = '${request.botId}/${request.chatId}';
    final existing = _botBindings[key];
    if (existing != null &&
        existing.revision != request.expectedBindingRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot binding revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final binding = BotConversationThreadBinding(
      botId: request.botId,
      chatId: request.chatId,
      projectId: _findBot(request.botId)?.projectId ?? '',
      threadId: existing?.threadId ?? 'thread-bot-${request.chatId}',
      revision: (existing?.revision ?? 0) + 1,
      state: BotConversationThreadState.bound,
    );
    _botBindings[key] = binding;
    return BotConversationThreadReply(
      binding: binding,
      receipt: _demoReceipt(
        OperationId(request.operationId),
        changed: true,
        targets: const [],
        effect: EffectPoint.immediate,
      ),
    );
  }

  McpStateSnapshot _mcpWriteResult() {
    final state = _demoMcpState();
    _publishProductPayload(McpStateChangedPayload(state));
    return state;
  }

  LspStateSnapshot _lspWriteResult() {
    _lspActivityPercentage = 40;
    final state = _demoLspState();
    _publishProductPayload(LspStateChangedPayload(state));
    return state;
  }

  McpStateSnapshot _demoMcpState() {
    return McpStateSnapshot.fromState(
      state: _demoReadyResource(_mcpRevision, const McpStateData()),
    );
  }

  LspStateSnapshot _demoLspState() {
    final percentage = _lspActivityPercentage;
    if (percentage == null) {
      return LspStateSnapshot.fromState(
        state: _demoReadyResource(_lspRevision, const LspStateData()),
      );
    }
    return LspStateSnapshot.fromState(
      state: _demoReadyResource(
        _lspRevision,
        LspStateData(
          activeServers: const ['rust-analyzer'],
          servers: [
            LspServerStateView(
              id: 'rust-analyzer',
              displayName: 'rust-analyzer',
              state: LspAvailableState(
                checkedAt: 0,
                diagnosticCount: 0,
                activity: LspIndexingActivity(
                  title: 'Roots Scanned',
                  message: '${(408 * percentage / 100).round()}/408',
                  percentage: percentage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _checkSettingsRevision(int expected) {
    _ensureDemoRunning();
    if (expected != _settingsRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Settings revision conflict',
        retryable: true,
        correlationId: 'demo-settings-cas',
      );
    }
  }

  AccountSettingsView _demoRemoveManualModel(
    AccountSettingsView account,
    String modelId,
  ) {
    final target = account.models
        .where((model) => model.modelId == modelId)
        .firstOrNull;
    if (target == null || target.origin != ModelOrigin.manual) {
      throw StateError('unknown demo manual modelId: ${account.id} / $modelId');
    }
    final models = [
      for (final model in account.models)
        if (model.modelId != modelId) model,
    ];
    final connections = {...account.modelConnectionModes}..remove(modelId);
    final limits = {...account.autoCompactLimits}..remove(modelId);
    return account.copyWith(
      models: models,
      modelConnectionModes: connections,
      autoCompactLimits: limits,
      modelCount: '${models.length}',
      usageLabel: models.isEmpty
          ? account.defaultModelId
          : '${models.length} models',
    );
  }

  AccountModelView _findDemoModel(
    List<AccountSettingsView> accounts,
    String accountId,
    String modelId,
  ) {
    final account = accounts.where((item) => item.id == accountId).firstOrNull;
    if (account == null) {
      throw StateError('unknown demo account: $accountId');
    }
    final selected = account.models
        .where((candidate) => candidate.modelId == modelId)
        .firstOrNull;
    if (selected == null) {
      throw StateError('unknown demo modelId: $accountId / $modelId');
    }
    return selected;
  }

  void _notifyItemsChanged(String threadId) {
    _contentVersions[threadId] = _contentVersionOf(threadId) + 1;
  }

  void _publishContent(String threadId, _DemoItemChange change) {
    for (final feed in [...?_conversationFeeds[threadId]]) {
      feed._contentChanged(change);
    }
  }

  /// demo 模拟一次 Thread 状态更新。
  ///
  /// 状态流只承载 Turn / 活动 / 交互 / 运行时——与生产投影同一契约；**条目与正文不在
  /// 这里**，它们写进内存条目，并由 Timeline 内容连接（`openConversationFeed` →
  /// `_DemoConversationFeed`）按同一有界尾部契约交付。
  void _emitThreadUpdate(String threadId, ThreadWorkspaceUpdate update) {
    if (_runtimeExiting) return;
    final workspace = _workspaces[threadId];
    if (workspace == null) return;
    final revision = workspace.revision + 1;
    // Turn revisions share the Thread event sequence, just like the native projector.
    if (update case ThreadTurnUpdate(:final turn)) {
      update = ThreadTurnUpdate(
        StudioTurnView(
          turnId: turn.turnId,
          inputId: turn.inputId ?? workspace.activeTurn?.inputId,
          threadId: threadId,
          revision: revision,
          state: turn.state,
          updatedAt: turn.updatedAt,
        ),
      );
    }
    final ThreadWorkspace updated = switch (update) {
      ThreadTurnUpdate(:final turn) => workspace.copyWith(
        revision: revision,
        activeTurn: turn.state.isBusy ? turn : null,
      ),
      // 活动与生产一样只从 typed 活动事实进入状态。
      ThreadActivityUpdate(:final activity) => workspace.copyWith(
        revision: revision,
        activity: activity,
      ),
      ThreadRuntimeUpdate(:final runtime, :final todo) => workspace.copyWith(
        revision: revision,
        runtime: runtime,
        todo: todo,
      ),
      // 存储状态与生产一样只从 typed 事实进入状态。
      ThreadStorageUpdate(:final storage) => workspace.copyWith(
        revision: revision,
        storage: storage,
      ),
      ThreadInteractionUpdate(:final interaction, :final pending) =>
        _demoUpdateInteraction(workspace, revision, interaction, pending),
    };
    _workspaces[threadId] = updated;
    final receivers = _conversationFeeds[threadId];
    if (receivers != null && receivers.isNotEmpty) {
      final frame = ThreadNotificationFrame(
        threadId: threadId,
        revision: revision,
        update: update,
      );
      for (final feed in receivers.toList()) {
        feed._stateChanged(frame);
      }
    }
    // The stop target is an execution identity and the continue target is a
    // continuation point, so the runtime projection carries both: derive them
    // from the canonical facts and publish them as their own facts.
    final execution = _demoExecutionOf(threadId);
    final continuation = _demoContinuationPoints[threadId];
    if (execution != updated.runtime.execution ||
        continuation != updated.runtime.continuation) {
      _emitThreadUpdate(
        threadId,
        ThreadRuntimeUpdate(
          runtime: updated.runtime.copyWith(
            execution: execution,
            continuation: continuation,
          ),
          todo: updated.todo,
        ),
      );
    }
    if (update case ThreadTurnUpdate(:final turn)) {
      final id = 'turn:${turn.turnId.length}:${turn.turnId}';
      final previous = _threadItems[threadId]
          ?.where((item) => item.id == id)
          .firstOrNull;
      _upsertChatItem(
        threadId,
        _demoItem(
          id: id,
          threadId: threadId,
          turnId: turn.turnId,
          ordinal: previous?.header.ordinal ?? _nextOrdinal(threadId),
          revision: turn.revision,
          createdAt: previous?.header.createdAt ?? turn.updatedAt,
          updatedAt: turn.updatedAt,
          content: _demoTurn(turn.state, inputId: turn.inputId),
        ),
      );
    }
  }

  /// 把一条条目写入内存内容：条目只属于内容连接，不推进线程状态水位。
  void _upsertChatItem(String threadId, ConversationItem item) {
    if (!_workspaces.containsKey(threadId)) return;
    // demo 的内存条目没有独立的执行终态事件：状态进入终态即视为内容终态。
    final entry = item;
    final items = [...?_threadItems[threadId]];
    final index = items.indexWhere((existing) => existing.id == entry.id);
    if (index < 0) {
      items.add(entry);
    } else {
      items[index] = entry;
    }
    items.sort(
      (a, b) => _DemoConversationFeed._compareKeys(
        _DemoConversationFeed._keyOf(a),
        _DemoConversationFeed._keyOf(b),
      ),
    );
    _threadItems[threadId] = items;
    _notifyItemsChanged(threadId);
    // 通知携带本次 typed 变更的身份与预览值：内容连接无需扫描全历史就能表达差量。
    _publishContent(
      threadId,
      _DemoItemChange(
        version: _contentVersionOf(threadId),
        itemId: entry.id,
        item: entry,
      ),
    );
  }

  List<ConversationItem> _itemsOf(String threadId) =>
      _threadItems[threadId] ?? const <ConversationItem>[];

  int _contentVersionOf(String threadId) => _contentVersions[threadId] ?? 0;

  /// 应用一帧 typed `UpdateItem` 字段变化，与 `BridgeViewChange::UpdateItem` 同形状：
  /// 按字段身份落到条目的 domain 字段，本地基线必须等于当前 revision；条目缺失、
  /// revision 不连续或已终态接受流式变化时丢弃（真实链路会重建权威窗口）。
  void _applyChatFieldUpdates(
    String threadId, {
    required String itemId,
    required int revision,
    required List<ConversationFieldUpdate> fields,
  }) {
    if (!_workspaces.containsKey(threadId)) return;
    final items = [...?_threadItems[threadId]];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    final current = items[index];
    final values = {
      for (final field in current.fields) field.field: field.text,
    };
    for (final field in fields) {
      switch (field.change) {
        case UnchangedThreadFieldChangeView():
          break;
        case AppendThreadFieldChangeView(:final text):
          values[field.field] = (values[field.field] ?? '') + text;
        case ReplaceThreadFieldChangeView(:final text):
          values[field.field] = text;
        case RemoveThreadFieldChangeView():
          values.remove(field.field);
      }
    }
    final next = _demoRevise(current, revision: revision, fields: values);
    items[index] = next;
    _threadItems[threadId] = items;
    _notifyItemsChanged(threadId);
    _publishContent(
      threadId,
      _DemoItemChange(
        version: _contentVersionOf(threadId),
        itemId: next.id,
        item: next,
      ),
    );
  }

  /// 单字段 append 的便捷入口（demo 脚本只追加正文）。
  void _appendChatContent(
    String threadId, {
    required String itemId,
    required int revision,
    required ThreadContentFieldView field,
    required String text,
  }) {
    final previous = _itemsOf(threadId)
        .where((item) => item.id == itemId)
        .firstOrNull
        ?.fieldFor(field)
        ?.text;
    final bytes = utf8.encode('${previous ?? ''}$text').length;
    _applyChatFieldUpdates(
      threadId,
      itemId: itemId,
      revision: revision,
      fields: [
        ConversationFieldUpdate(
          field: field,
          change: AppendThreadFieldChangeView(text),
          totalBytes: bytes,
          previewBytes: bytes,
        ),
      ],
    );
  }

  /// demo 脚本化的当前活动：作为 typed `ActivityChanged` 状态走状态流。
  void _emitActivity(
    String threadId, {
    required String turnId,
    required String? inputId,
    required ThreadActivityKind kind,
    String summary = '',
  }) {
    _emitThreadUpdate(
      threadId,
      ThreadActivityUpdate(
        activity: ThreadActivityView(
          threadId: threadId,
          identity: 'activity:$turnId:${kind.name}',
          revision: 0,
          turnId: turnId,
          inputId: inputId,
          kind: kind,
          summary: summary,
        ),
      ),
    );
  }

  /// Turn 结束或打断：清空当前活动（`activity == null`）。
  void _clearActivity(String threadId) {
    _emitThreadUpdate(threadId, const ThreadActivityUpdate(activity: null));
  }

  int _nextOrdinal(String threadId) {
    final items = _itemsOf(threadId);
    return items.isEmpty
        ? 0
        : items
                  .map((item) => item.header.ordinal)
                  .reduce((left, right) => left > right ? left : right) +
              1;
  }
}

/// 一次内容变更的 typed 事实：推送它的身份、新预览值或“已删除”。
///
/// 这就是 demo 的“producer 通知”：内容连接不需要为每次交付重建全历史版本表。
/// demo 已受理的一次无内容继续；同一个操作身份只回答同一份事实。
final class _DemoDelay {
  _DemoDelay(Duration duration) {
    _timer = Timer(duration, _finish);
  }
  late final Timer _timer;
  final Completer<void> done = Completer<void>();
  void _finish() {
    if (!done.isCompleted) done.complete();
  }

  void cancel() {
    _timer.cancel();
    _finish();
  }
}

final class _DemoContinuation {
  _DemoContinuation({
    required this.threadId,
    required this.inputId,
    required this.continuationId,
    required this.expectedModelRouteRevision,
    required this.acceptedSequence,
    required this.receipt,
  });

  final String threadId;
  final String inputId;
  final String continuationId;

  /// 受理时冻结的路由版本：同身份重试必须与它一致。
  final int expectedModelRouteRevision;
  final int acceptedSequence;
  final StudioCommandReceipt receipt;

  /// 控制输入被实际轮次消费后的接续轮次；准入即确定，不等待整轮完成。
  String? turnId;

  /// 同一个操作身份是否描述同一份请求事实。
  bool matches(String thread, String continuation, int routeRevision) =>
      threadId == thread &&
      continuationId == continuation &&
      expectedModelRouteRevision == routeRevision;
}

final class _DemoItemChange {
  const _DemoItemChange({
    required this.version,
    required this.itemId,
    this.item,
    this.removed = false,
  });

  final int version;
  final String itemId;
  final ConversationItem? item;
  final bool removed;
}

ConversationItem _messageItem({
  required String id,
  required String threadId,
  required String turnId,
  required int ordinal,
  required ThreadTextChannel channel,
  required String text,
  required DateTime createdAt,
  List<ThreadAttachmentView> attachments = const [],
}) => _demoItem(
  id: id,
  threadId: threadId,
  turnId: turnId,
  ordinal: ordinal,
  revision: 0,
  createdAt: createdAt,
  updatedAt: createdAt,
  content: _demoText(
    channel: channel,
    text: text,
    attachments: attachments,
    lifecycle: CompletedThreadContentView(createdAt),
  ),
);

AttachmentDraftView _demoAttachmentDraft(
  AttachmentDraftSource source,
  int sequence,
) {
  final filename = switch (source) {
    LocalFileAttachmentDraftSource(:final path) =>
      path.replaceAll('\\', '/').split('/').last,
    RemoteUrlAttachmentDraftSource(:final url, :final filename) =>
      filename ?? Uri.parse(url).pathSegments.last,
  };
  final extension = filename.split('.').last.toLowerCase();
  final modality = switch (extension) {
    'png' || 'jpg' || 'jpeg' || 'webp' => AttachmentModalityView.image,
    'mp4' || 'mov' || 'webm' || 'mkv' => AttachmentModalityView.video,
    _ => AttachmentModalityView.file,
  };
  return AttachmentDraftView(
    id: 'demo-attachment-$sequence',
    modality: modality,
    mediaType: switch (modality) {
      AttachmentModalityView.image => 'image/png',
      AttachmentModalityView.video => 'video/mp4',
      AttachmentModalityView.file => 'application/octet-stream',
    },
    filename: filename,
    byteSize: 0,
  );
}

ThreadWorkspace _demoUpdateInteraction(
  ThreadWorkspace workspace,
  int revision,
  PendingInteraction interaction,
  bool pending,
) {
  final interactions = [...workspace.interactions];
  final index = interactions.indexWhere((item) => item.id == interaction.id);
  if (!pending) {
    if (index >= 0) interactions.removeAt(index);
  } else if (index < 0) {
    interactions.add(interaction);
  } else {
    interactions[index] = interaction;
  }
  return workspace.copyWith(revision: revision, interactions: interactions);
}

/// Deterministic demo fixture exposed only by the dedicated Driver build.
class DriverDemoStudioTransport extends DemoStudioTransport {
  DriverDemoStudioTransport({super.lspActivityLoop});

  bool _retiredPlannerScenario = false;
  int _fixtureScenarioRevision = 0;
  int _appliedFixtureScenarioRevision = -1;

  void prepareRetiredPlannerScenario() {
    prepareSessionLifecycleScenario();
    _retiredPlannerScenario = true;
    _selectedThreadId = 'thread-main';
  }

  @override
  ({StudioProject project, List<StudioThread> threads})
  _ensureWorkspaceFixture() {
    final fixture = super._ensureWorkspaceFixture();
    if (_appliedFixtureScenarioRevision != _fixtureScenarioRevision) {
      _workspaces.update('thread-main', _driverWorkspaceFixture);
      _resolvedInteractions.clear();
      _appliedFixtureScenarioRevision = _fixtureScenarioRevision;
    }
    if (!_retiredPlannerScenario) return fixture;
    final threads = [
      for (final thread in fixture.threads)
        if (thread.id == 'thread-reviewer')
          thread.copyWith(role: 'planner', status: ThreadStatusView.idle)
        else
          thread,
    ];
    final retired = threads.singleWhere(
      (thread) => thread.id == 'thread-reviewer',
    );
    _workspaces[retired.id] = _workspaces[retired.id]!.copyWith(
      thread: retired,
      interactions: const [],
    );
    return (project: fixture.project, threads: threads);
  }

  bool _themeScenario = false;
  bool _themePlanScenario = false;

  /// Resets the dedicated Driver fixture without introducing product settings.
  void prepareThemeScenario({bool plan = false}) {
    _fixtureScenarioRevision += 1;
    _themeScenario = true;
    _themePlanScenario = plan;
    _sessionLifecycleScenario = false;
    _fallbackInputScenario = false;
    _persistenceFailureScenario = false;
    _failNextTurn = false;
    _retryNextTurn = false;
    _selectedThreadId = 'thread-main';
  }

  bool _sessionLifecycleScenario = false;
  bool _persistenceFailureScenario = false;
  bool _failNextTurn = false;
  bool _retryNextTurn = false;

  void prepareConnectionRetryScenario() {
    _retryNextTurn = true;
  }

  void preparePersistenceFailureScenario() {
    prepareSessionLifecycleScenario();
    _persistenceFailureScenario = true;
    _failNextTurn = true;
    _selectedThreadId = 'thread-main';
  }

  @override
  Future<void> _completePrompt({
    required String threadId,
    required String turnId,
    required String trimmedPrompt,
    required int generation,
    required DateTime startedAt,
    void Function()? onAdmitted,
  }) async {
    onAdmitted?.call();
    if (_retryNextTurn) {
      _retryNextTurn = false;
      for (var attempt = 1; attempt <= 5; attempt++) {
        await _waitDemo(promptActivityDelay);
        if (_promptGenerations[threadId] != generation) return;
        final now = DateTime.now();
        _upsertChatItem(
          threadId,
          _demoItem(
            id: '$turnId:connection-retry-$attempt',
            threadId: threadId,
            turnId: turnId,
            ordinal: _nextOrdinal(threadId),
            revision: 0,
            createdAt: now,
            updatedAt: now,
            content: _demoText(
              channel: ThreadTextChannel.commentary,
              text: '连接中断，正在重试（$attempt/5）。',
              attachments: const [],
              lifecycle: CompletedThreadContentView(now),
            ),
          ),
        );
      }
    }
    if (!_failNextTurn) {
      return super._completePrompt(
        threadId: threadId,
        turnId: turnId,
        trimmedPrompt: trimmedPrompt,
        generation: generation,
        startedAt: startedAt,
      );
    }
    _failNextTurn = false;
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 1,
          updatedAt: DateTime.now(),
          state: FailedStudioTurnState(
            startedAt: startedAt.millisecondsSinceEpoch ~/ 1000,
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            failure: const StudioTurnFailureView(
              category: 'protocol',
              providerKind: null,
              code: 'turnProtocolProjectionFailed',
              httpStatus: null,
              message: 'Injected turn protocol failure',
              retryable: false,
              retryAfterMs: null,
            ),
          ),
        ),
      ),
    );
    // 注入的 Turn 失败也是终态：清空当前活动。
    _clearActivity(threadId);
  }

  @override
  Future<PersistenceStateSnapshot> retryPersistence() async {
    _persistenceFailureScenario = false;
    return const PersistenceStateSnapshot(
      revision: 2,
      state: ReadyPersistenceState(pendingCommits: 0),
    );
  }

  bool _fallbackInputScenario = false;
  int _pagingFixtureCount = 42;

  void preparePagingScenario(int count) {
    _fixtureScenarioRevision += 1;
    _sessionLifecycleScenario = false;
    _fallbackInputScenario = false;
    _pagingFixtureCount = count;
    _pageFillThreads.clear();
    _selectedThreadId = null;
  }

  void prepareSessionLifecycleScenario() {
    _fixtureScenarioRevision += 1;
    _themeScenario = false;
    _themePlanScenario = false;
    _sessionLifecycleScenario = true;
    _fallbackInputScenario = false;
    _pageFillThreads.clear();
    _selectedThreadId = null;
  }

  void prepareFallbackInputScenario() {
    _fixtureScenarioRevision += 1;
    _sessionLifecycleScenario = false;
    _fallbackInputScenario = true;
    _pageFillThreads.clear();
    _selectedThreadId = 'thread-main';
  }

  static const _themePlanMarkdown = '''
# Siamese workspace palette

Keep the existing workspace and use cream surfaces with seal-brown actions.

## Implementation

1. Archive the approved concept and document semantic colors.
2. Apply the shared Material theme to all pages and dialogs.
3. Keep blue limited to selected markers and active status icons.

> Normal text stays warm brown and remains readable on every surface.

```dart
final theme = pureStudioTheme();
```

## Acceptance

- [x] Preserve the layout and all existing actions.
- [ ] Verify narrow windows and keyboard focus.
- [ ] Inspect [the design reference](https://example.com/design).
''';

  @override
  Duration get promptActivityDelay => const Duration(seconds: 3);

  @override
  Duration get promptToolDelay => const Duration(seconds: 3);

  @override
  Duration get shutdownPhaseDelay => const Duration(milliseconds: 400);

  @override
  Duration get lspActivityStepDelay => const Duration(seconds: 3);

  /// Driver 目录分页验收需要大量历史会话。
  @override
  int get directoryPageFillCount =>
      _sessionLifecycleScenario ? 0 : _pagingFixtureCount;

  @override
  PersistenceStateSnapshot _demoPersistenceState() =>
      _persistenceFailureScenario
      ? const PersistenceStateSnapshot(
          revision: 1,
          state: DegradedPersistenceState(
            pendingCommits: 3,
            oldestPendingRevision: 8,
            firstFailedAt: 1,
            error: ObservedResourceError(
              code: 'storageUnavailable',
              message: 'Injected save failure',
              retryable: true,
            ),
          ),
        )
      : super._demoPersistenceState();

  ThreadWorkspace _driverWorkspaceFixture(ThreadWorkspace workspace) {
    if (_sessionLifecycleScenario) {
      return workspace.copyWith(interactions: const [], todo: null);
    }
    const threadId = 'thread-main';
    return workspace.copyWith(
      todo: _themeScenario
          ? const TimelineTodoListUpdate(
              callId: 'driver-theme-todo',
              explanation: 'Palette acceptance',
              items: [
                TimelineTodoItem(
                  step: 'Archive the approved concept',
                  status: 'completed',
                ),
                TimelineTodoItem(
                  step: 'Apply the shared theme',
                  status: 'inProgress',
                ),
                TimelineTodoItem(
                  step: 'Inspect all interface states',
                  status: 'pending',
                ),
              ],
            )
          : workspace.todo,
      interactions: _themePlanScenario
          ? const [
              PendingInteraction(
                id: 'driver-theme-plan',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.userInput,
                title: 'Theme implementation plan',
                body: _themePlanMarkdown,
                payload: UserInputInteractionPayload(
                  questions: [
                    UserQuestionView(
                      id: agentSessionPlanConfirmationQuestionId,
                      header: 'Plan',
                      question: _themePlanMarkdown,
                      isOther: true,
                      isSecret: false,
                      options: [
                        UserQuestionOptionView(
                          label: agentSessionPlanApproveAnswer,
                          description: 'Approve this plan.',
                        ),
                        UserQuestionOptionView(
                          label: agentSessionPlanReviseAnswer,
                          description: 'Revise this plan.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]
          : _fallbackInputScenario
          ? const [
              PendingInteraction(
                id: 'driver-fallback-input',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.userInput,
                title: 'Continue task',
                body: '请输入“继续”以创建新的任务轮次。',
                payload: UserInputInteractionPayload(questions: []),
              ),
            ]
          : const [
              PendingInteraction(
                id: 'driver-tool',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.toolApproval,
                title: 'Approve demo tool',
                body: 'Run a deterministic demo command.',
                payload: ToolApprovalInteractionPayload(
                  toolName: 'demo_tool',
                  workingDirectory: r'C:\demo',
                ),
              ),
              PendingInteraction(
                id: 'driver-input',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.userInput,
                title: 'Demo question',
                body: 'Choose a deterministic answer.',
                payload: UserInputInteractionPayload(
                  questions: [
                    UserQuestionView(
                      id: 'driver-question',
                      header: 'Driver',
                      question: 'Continue?',
                      isOther: false,
                      isSecret: false,
                      options: [],
                    ),
                  ],
                ),
              ),
            ],
    );
  }
}

String _demoProvisionalThreadTitle(String prompt) {
  final normalized = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return 'New Session';
  return normalized.runes.take(80).map(String.fromCharCode).join();
}

/// demo `worktree` 会话地址：与项目目录同级的 `worktrees` 目录，仅供 GUI 验收展示。
String _demoWorktreePath(String projectPath, String threadId) =>
    '${projectPath.replaceAll('\\', '/')}-worktrees/$threadId';

ObservedResource<T> _demoReadyResource<T>(int revision, T value) {
  return ReadyObservedResource(
    revision: revision,
    updatedAt: revision,
    lastCheckedAt: null,
    value: value,
  );
}

ObservedResource<T> _demoInitialResource<T>() =>
    UninitializedObservedResource(updatedAt: 0);

SkillsStateSnapshot _demoSkillsState(
  String projectId,
  int revision, {
  List<String> skills = const [
    'flutter-ui-polish',
    'runtime-review',
    'studio-settings',
  ],
}) {
  return SkillsStateSnapshot.fromState(
    projectId: projectId,
    state: _demoReadyResource(
      revision,
      SkillsStateData(
        configFingerprint: 'demo',
        catalogRevision: revision,
        skills: skills,
        summaries: [
          for (final skill in skills)
            SkillSummaryView(
              name: skill,
              description: switch (skill) {
                'flutter-ui-polish' =>
                  'Polish Flutter layouts, interactions, and visual details.',
                'runtime-review' =>
                  'Review runtime behavior, lifecycle, and concurrency.',
                'studio-settings' =>
                  'Manage Studio accounts, skills, and application settings.',
                _ => 'Installed Studio skill.',
              },
              source: 'demo',
              providerId: 'demo',
              modelInvocable: true,
              userInvocable: true,
              resourceBase: const SkillResourceBaseView(
                SkillResourceBaseKind.opaque,
                'demo',
              ),
            ),
        ],
        warnings: const [],
      ),
    ),
  );
}

/// demo 内的 argv 值比较：顺序与内容都要一致，才可沿用旧连接身份。
