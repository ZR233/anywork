import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:anywork_client/conversation.dart' show DisplayMembers;
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_ports.dart';
import 'package:flutter/foundation.dart'
    show visibleForTesting, listEquals, mapEquals;

import '../../domain/models/studio_models.dart';
import '../../platform/error_log.dart';
import 'accounts/demo_account_observation.dart';

part 'studio_demo_conversation.dart';
part 'studio_demo_settings.dart';
part 'studio_demo_timeline.dart';

const _conversationClosedFailure = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The conversation feed is closed',
  retryable: false,
  correlationId: 'client-conversation-closed',
);
const _conversationQueryFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The conversation query is invalid',
  retryable: false,
  correlationId: 'client-conversation-query',
);

ThreadRuntimeView _emptyRuntimeView() {
  return const ThreadRuntimeView(
    modelId: '',
    contextTokens: 0,
    contextWindow: 0,
    totalTokens: 0,
    costLabel: '',
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
  );
}

Object _studioFailure(Object error) {
  return switch (error) {
    final StudioFailure failure => failure,
    _ => StudioFailure(
      code: StudioFailureCode.internal,
      message: error.toString(),
      retryable: false,
      correlationId: newStudioCorrelationId(),
    ),
  };
}

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

final class _DemoDirectoryChangeSignal {
  _DemoDirectoryChangeSignal(
    DemoStudioTransport transport, {
    bool Function(ProductTopicFrame frame)? isRelevant,
  }) : _isRelevant = isRelevant ?? _allDirectoryChanges {
    _subscription = transport
        .subscribeProductTopic(const ThreadDirectoryTopic())
        .listen(
          (frame) {
            if (_baselinePending) {
              _baselinePending = false;
              if (!_ready.isCompleted) _ready.complete();
              return;
            }
            if (!_isRelevant(frame)) return;
            _dirty = true;
            if (_wake case final wake? when !wake.isCompleted) wake.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            _failure ??= error;
            _failureStack ??= stackTrace;
            if (!_ready.isCompleted) _ready.complete();
            if (_wake case final wake? when !wake.isCompleted) wake.complete();
          },
        );
  }

  static bool _allDirectoryChanges(ProductTopicFrame _) => true;

  late final StreamSubscription<ProductTopicFrame> _subscription;
  final bool Function(ProductTopicFrame frame) _isRelevant;
  final Completer<void> _ready = Completer<void>();
  Completer<void>? _wake;
  bool _baselinePending = true;
  bool _initial = true;
  bool _dirty = false;
  bool _closed = false;
  Object? _failure;
  StackTrace? _failureStack;

  Future<bool> next() async {
    await _ready.future;
    while (!_initial && !_dirty && !_closed && _failure == null) {
      final wake = _wake ??= Completer<void>();
      await wake.future;
    }
    if (_closed) return false;
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure, _failureStack!);
    }
    _initial = false;
    _dirty = false;
    _wake = null;
    return true;
  }

  void requestClose() {
    _closed = true;
    if (!_ready.isCompleted) _ready.complete();
    if (_wake case final wake? when !wake.isCompleted) wake.complete();
  }

  Future<void> close() async {
    requestClose();
    await _subscription.cancel();
  }
}

final class _DemoThreadsObservation implements ThreadsObservationHandle {
  _DemoThreadsObservation(this.transport, this.query, this.window)
    : _changes = _DemoDirectoryChangeSignal(transport);

  final DemoStudioTransport transport;
  final DirectoryQuery query;
  final DirectoryWindow window;
  final _DemoDirectoryChangeSignal _changes;
  Future<ThreadDirectoryFrame?>? _next;
  ThreadDirectoryFrame? _lastFrame;
  bool _closed = false;

  @override
  Future<ThreadDirectoryFrame?> next() {
    if (_closed) return Future.value(null);
    if (_next != null) {
      return Future.error(StateError('Directory next is already in flight'));
    }
    final work = () async {
      while (!_closed) {
        if (!await _changes.next()) return null;
        final frame = transport._readDirectoryFrame(query, window);
        if (_closed) return null;
        final previous = _lastFrame;
        if (previous == null ||
            previous.nextCursor != frame.nextCursor ||
            !_sameThreadIds(previous.threadIds, frame.threadIds)) {
          _lastFrame = frame;
          return frame;
        }
      }
      return null;
    }();
    _next = work;
    unawaited(
      work.then<void>(
        (_) => _next = null,
        onError: (Object _, StackTrace _) => _next = null,
      ),
    );
    return work;
  }

  @override
  void requestClose() {
    _closed = true;
    _changes.requestClose();
  }

  @override
  Future<void> close() async {
    requestClose();
    await _changes.close();
    final pending = _next;
    if (pending != null) {
      await pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    }
  }
}

bool _sameThreadIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _DemoThreadObservation implements ThreadObservationHandle {
  _DemoThreadObservation(this.transport, this.threadId)
    : _changes = _DemoDirectoryChangeSignal(
        transport,
        isRelevant: (frame) => switch (frame) {
          ProductTopicDataFrame(:final event) => switch (event.payload) {
            ThreadDirectoryChangedPayload(:final upserted, :final removed) =>
              upserted.any((row) => row.threadId == threadId) ||
                  removed.contains(threadId),
            _ => false,
          },
          _ => true,
        },
      );

  final DemoStudioTransport transport;
  final String threadId;
  final _DemoDirectoryChangeSignal _changes;
  Future<ThreadMetadataFrame?>? _next;
  bool _closed = false;

  @override
  Future<ThreadMetadataFrame?> next() {
    if (_closed) return Future.value(null);
    if (_next != null) {
      return Future.error(
        StateError('Thread metadata next is already in flight'),
      );
    }
    final work = () async {
      if (!await _changes.next()) return null;
      return transport._readMetadataFrame(threadId);
    }();
    _next = work;
    unawaited(
      work.then<void>(
        (_) => _next = null,
        onError: (Object _, StackTrace _) => _next = null,
      ),
    );
    return work;
  }

  @override
  void requestClose() {
    _closed = true;
    _changes.requestClose();
  }

  @override
  Future<void> close() async {
    requestClose();
    await _changes.close();
    final pending = _next;
    if (pending != null) {
      await pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    }
  }
}

class DemoStudioTransport extends StudioTransport
    implements
        PersistenceQueueReader,
        AccountFeedPort,
        AccountConfigurationPort,
        AccountModelsPort,
        AccountUsagePort,
        TimelineTransport,
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
    for (final feed in _ownedConversationStateFeeds.toList()) {
      feed.requestClose();
    }
    for (final reader in _ownedHistoryReaders.toList()) {
      reader.requestClose();
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
      case ChatGptLoginTarget():
        throw UnsupportedError('ChatGPT login is unavailable in demo mode');
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
                brandKey: account.template?.wire ?? '',
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
      case AcpLocalDetectionTarget():
        return AcpLocalDetectionFrame(
          _demoStamp('acp-local-detection', 0),
          const AcpLocalDetectionSnapshotView.idle(),
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
  final Map<String, Set<_DemoConversationStateFeed>> _conversationStateFeeds =
      {};
  final Set<_DemoReader> _ownedHistoryReaders = {};
  // 受管句柄不等于 GUI demand：未监听句柄和迟到 factory 也有真实关闭责任。
  final Set<ConversationFeed> _ownedConversationFeeds =
      Set<ConversationFeed>.identity();
  final Set<ConversationStateFeed> _ownedConversationStateFeeds =
      Set<ConversationStateFeed>.identity();
  final Set<Future<void>> _openingConversationFeeds = {};
  final Map<ConversationFeed, Future<void>> _conversationCloses =
      Map<ConversationFeed, Future<void>>.identity();
  final Map<ConversationStateFeed, Future<void>> _conversationStateCloses =
      Map<ConversationStateFeed, Future<void>>.identity();

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
      for (final feed in _ownedConversationStateFeeds.toList())
        _closeDemoStateFeed(feed),
      for (final reader in _ownedHistoryReaders.toList()) reader.close(),
      ..._openingConversationFeeds,
    ]);
    // 迟到 factory 自己汇合其返回的 owner。失败 owner 留在集合供下次 cleanup。
    if (_ownedConversationFeeds.isNotEmpty ||
        _ownedConversationStateFeeds.isNotEmpty) {
      throw StateError('Demo conversation close still has unresolved owners');
    }
  }

  Future<void> _closeDemoStateFeed(ConversationStateFeed feed) {
    final existing = _conversationStateCloses[feed];
    if (existing != null) return existing;
    final joined = Completer<void>();
    _conversationStateCloses[feed] = joined.future;
    Future<void> closeOwned() async {
      try {
        feed.requestClose();
        await feed.close();
        _ownedConversationStateFeeds.remove(feed);
        joined.complete();
      } catch (error, stack) {
        // 失败 owner 仍留在 owned；只清本轮 in-flight，允许下次真实重试。
        joined.completeError(error, stack);
      } finally {
        _conversationStateCloses.remove(feed);
      }
    }

    unawaited(closeOwned());
    return joined.future;
  }

  final _shutdownEvents = StreamController<StudioShutdownProgress>.broadcast();

  final Map<String, _DemoHistory> _histories = {};
  final Map<String, Map<String, _DemoItem>> _pendingItems = {};

  _DemoHistory _historyOf(String threadId) =>
      _histories.putIfAbsent(threadId, _DemoHistory.new);
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
  final Map<String, _DemoPlanRequest> _demoPlanRequests = {};
  final Map<String, (PendingInteraction, _DemoInvocation)>
  _demoUserInputInvocations = {};

  void _freezeDemoPlanRequest(
    PendingInteraction interaction, {
    PlanDocumentView? document,
    int? planRevision,
  }) {
    final question = _demoPlanQuestion(interaction);
    if (question == null) {
      _demoPlanRequests.remove(interaction.id);
      return;
    }
    if (document != null && document.markdown != question.question) {
      throw _conversationQueryFailure;
    }
    final existing = _demoPlanRequests[interaction.id];
    if (document == null &&
        existing != null &&
        existing.interaction.threadId == interaction.threadId &&
        existing.interaction.turnId == interaction.turnId &&
        existing.interaction.revision == interaction.revision &&
        existing.markdown == question.question) {
      return;
    }
    _demoPlanRequests[interaction.id] = (
      interaction: interaction,
      markdown: question.question,
      document: document,
      planRevision: planRevision,
    );
  }

  void _validateDemoPlanRequest(
    _DemoPlanRequest request,
    PendingInteraction interaction,
  ) {
    final question = _demoPlanQuestion(interaction);
    if (request.interaction.threadId != interaction.threadId ||
        request.interaction.turnId != interaction.turnId ||
        request.interaction.revision != interaction.revision ||
        question?.question != request.markdown) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'Plan confirmation no longer matches its frozen request',
        retryable: false,
        correlationId: 'demo-plan-confirmation-identity',
      );
    }
    if (request.document != null) {
      final plan = _workspaces[interaction.threadId]?.runtime.plan;
      if (plan == null ||
          plan.state != PlanRuntimePhase.awaitingConfirmation ||
          plan.revision != request.planRevision ||
          plan.document != request.document) {
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'Plan confirmation no longer matches the pending Plan',
          retryable: false,
          correlationId: 'demo-plan-confirmation-state',
        );
      }
    }
  }

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
  final Map<McpScope, int> _mcpCatalogRevisions = {};
  final Map<McpDocumentRef, ({String id, int revision, String rawToml})>
  _mcpDocuments = {
    const McpDocumentRef(
      scope: HostMcpScope(),
      relativePath: 'mcp/dart.toml',
    ): (
      id: 'dart',
      revision: 1,
      rawToml:
          'id = "dart"\nkind = "builtin"\nbuiltin = "dart"\nenabled = true\n',
    ),
  };
  final Map<String, int> _threadMcpGenerations = {};
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
    final selectedThreadId = _sortedDirectoryRows()
        .where(
          (row) =>
              row.threadId == _selectedThreadId &&
              row.workspaceId == selectedProjectId,
        )
        .firstOrNull
        ?.threadId;
    return StudioBootstrap(
      ownerEpoch: _ownerEpoch,
      projectDirectory: projects,
      threadDirectory: threads,
      agentDirectory: _demoAgentDirectory(),
      settingsState: _demoSettingsState(),
      recoveryState: _demoRecoveryState(),
      mcpCatalog: _demoMcpCatalog(const HostMcpScope()),
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
        for (final root in _sortedDirectoryRows().where((row) => row.isRootRow))
          root.sessionId: _demoSessionCosts(root.sessionId),
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

  ThreadDirectoryPage _demoThreadDirectory() {
    final directory = _sortedDirectoryRows();
    return ThreadDirectoryPage(
      rows: directory.take(directoryPageSize).toList(),
      nextCursor: directory.length > directoryPageSize
          ? _demoDirectoryCursor(directoryPageSize - 1)
          : null,
      revision: _threadDirectoryRevision,
    );
  }

  ThreadDirectoryPage _demoDirectoryPage() {
    final window = _demoThreadDirectory();
    return ThreadDirectoryPage(
      rows: window.rows,
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
      workspaceId: project.id,
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
      workspaceId: project.id,
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
      workspaceId: project.id,
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
              !_archivedThreadIds.contains(_demoSessionIdOf(thread)),
        )
        .toList();
    for (final thread in _createdRootThreads) {
      _workspaces.putIfAbsent(
        thread.id,
        () => ThreadWorkspace(
          businessRefs: const ThreadBusinessRefs(
            plan: null,
            interactions: null,
          ),
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
    String workspaceId,
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
        workspaceId: workspaceId,
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
          businessRefs: const ThreadBusinessRefs(
            plan: null,
            interactions: null,
          ),
          thread: thread,
          revision: 0,
          interactions: const [],
          runtime: _emptyRuntimeView(),
        ),
      );
    }
  }

  /// 目录完整排序视图（最近用户消息时间倒序、threadId 倒序），分页窗口的数据源。
  List<SessionDirectoryRow> _sortedDirectoryRows() {
    final fixture = _ensureWorkspaceFixture();
    return [
      for (final thread in [
        ...fixture.threads,
        ..._pageFillThreads.where(
          (thread) => !_archivedThreadIds.contains(thread.id),
        ),
      ])
        if (!_archivedProjectIds.contains(thread.workspaceId))
          _directoryRowOf(
            thread,
            archived: _archivedThreadIds.contains(_demoSessionIdOf(thread)),
          ),
    ]..sort(SessionDirectoryRow.compareDirectoryOrder);
  }

  @override
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window,
  ) async {
    _ensureDemoRunning();
    return _DemoThreadsObservation(this, query, window);
  }

  @override
  Future<ThreadObservationHandle> openThreadObservation(String threadId) async {
    _ensureDemoRunning();
    return _DemoThreadObservation(this, threadId);
  }

  ThreadDirectoryFrame _readDirectoryFrame(
    DirectoryQuery query,
    DirectoryWindow window,
  ) {
    final projects = _demoProjectDirectory().values;
    final matching =
        _demoAllRows()
            .where((row) => _matchesDirectoryQuery(query, row, projects))
            .toList()
          ..sort(SessionDirectoryRow.compareDirectoryOrder);
    final offset = window.before == null
        ? 0
        : int.tryParse(window.before!) ??
              (throw ArgumentError.value(window.before, 'before'));
    if (offset < 0) throw ArgumentError.value(window.before, 'before');
    final threadIds = matching
        .skip(offset)
        .take(window.limit)
        .map((row) => row.threadId)
        .toList();
    final nextOffset = offset + threadIds.length;
    final stamp = _demoStamp('thread-directory', _threadDirectoryRevision);
    _checkDemoFrameSize({
      'query': {
        'workspaceId': query.workspaceId,
        'search': query.search,
        'archived': query.archived,
        'filter': query.filter.name,
        'threadIds': query.threadIds,
        'excludedThreadIds': query.excludedThreadIds,
      },
      'window': {'before': window.before, 'limit': window.limit},
      'stamp': _demoStampWireFields(stamp),
      'threadIds': threadIds,
      'nextCursor': nextOffset < matching.length ? '$nextOffset' : null,
    });
    return ThreadDirectoryFrame(
      query: query,
      window: window,
      stamp: stamp,
      threadIds: threadIds,
      nextCursor: nextOffset < matching.length ? '$nextOffset' : null,
    );
  }

  Map<String, Object?> _demoStampWireFields(ResourceStamp stamp) => {
    'resourceKey': stamp.resourceKey,
    'ownerEpoch': stamp.ownerEpoch,
    'revision': stamp.revision,
  };

  Map<String, Object?> _demoRowWireFields(SessionDirectoryRow row) => {
    'sessionId': row.sessionId,
    'agentId': row.agentId,
    'parentAgentId': row.parentAgentId,
    'threadId': row.threadId,
    'workspaceId': row.workspaceId,
    'title': row.title,
    'mode': row.mode?.id,
    'delegationMode': row.delegationMode.name,
    'delegationPreference': row.delegationPreference.name,
    'workspaceMode': row.workspaceMode.id,
    'workspacePath': row.workspacePath,
    'role': row.role,
    'backend': switch (row.backend) {
      NativeAgentBackendView(:final config, :final status) => {
        'kind': 'native',
        'config': {
          'route': config.route == null
              ? null
              : {
                  'accountId': config.route!.accountId,
                  'modelId': config.route!.modelId,
                  'effort': config.route!.effort,
                },
          'systemInstructions': config.systemInstructions,
        },
        'status': status.name,
      },
      AcpAgentBackendView(:final reference) => {
        'kind': 'acp',
        'reference': {
          'accountId': reference.accountId,
          'acpSessionId': reference.acpSessionId,
          'cwd': reference.cwd,
        },
      },
    },
    'createdAt': row.effectiveCreatedAt.millisecondsSinceEpoch,
    'updatedAt': row.updatedAt.millisecondsSinceEpoch,
    'lastUserMessageAt': row.lastUserMessageAt?.millisecondsSinceEpoch,
    'archived': row.archived,
  };

  void _checkDemoFrameSize(Map<String, Object?> frame) {
    // This mirrors the Rust serialized-frame budget; Demo still returns typed frames directly.
    if (utf8.encode(jsonEncode(frame)).length <=
        DirectoryWindow.maxFrameBytes) {
      return;
    }
    throw StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Directory frame exceeds the 256 KiB delivery limit',
      retryable: false,
      correlationId: 'demo-thread-directory-$_threadDirectoryRevision',
    );
  }

  bool _matchesDirectoryQuery(
    DirectoryQuery query,
    SessionDirectoryRow row,
    Iterable<StudioProject> projects,
  ) {
    if (!row.isRootRow ||
        row.archived != query.archived ||
        (query.workspaceId != null && row.workspaceId != query.workspaceId) ||
        (query.threadIds != null && !query.threadIds!.contains(row.threadId)) ||
        query.excludedThreadIds.contains(row.threadId)) {
      return false;
    }
    if (query.filter == DirectoryFilter.running &&
        (!(row.backend is NativeAgentBackendView &&
                (row.backend as NativeAgentBackendView).status.isActive) ||
            (row.backend is NativeAgentBackendView &&
                (row.backend as NativeAgentBackendView).status ==
                    ThreadStatusView.waitingInteraction))) {
      return false;
    }
    if (query.filter == DirectoryFilter.attention &&
        (row.backend is! NativeAgentBackendView ||
            (row.backend as NativeAgentBackendView).status !=
                ThreadStatusView.waitingInteraction) &&
        (row.backend is! NativeAgentBackendView ||
            (row.backend as NativeAgentBackendView).status !=
                ThreadStatusView.faulted)) {
      return false;
    }
    final term = query.search?.trim().toLowerCase() ?? '';
    String projectText = '';
    for (final project in projects) {
      if (project.id == row.workspaceId) {
        projectText = '${project.name} ${project.path}'.toLowerCase();
        break;
      }
    }
    return term.isEmpty ||
        row.title.toLowerCase().contains(term) ||
        projectText.contains(term);
  }

  ThreadMetadataFrame _readMetadataFrame(String threadId) {
    final row = _demoAllRows()
        .where((row) => row.threadId == threadId)
        .firstOrNull;
    final stamp = _demoStamp('thread-directory', _threadDirectoryRevision);
    _checkDemoFrameSize({
      'threadId': threadId,
      'stamp': _demoStampWireFields(stamp),
      'row': row == null ? null : _demoRowWireFields(row),
    });
    return ThreadMetadataFrame(threadId: threadId, stamp: stamp, row: row);
  }

  @override
  Future<SessionDirectoryRow> restoreThread(String threadId) async {
    _archivedThreadIds.remove(threadId);
    final restored = _demoDirectoryThreads()[threadId];
    if (restored == null) {
      throw StateError('unknown demo Thread $threadId');
    }
    _emitThreadDirectoryUpdate(restored);
    return _directoryRowOf(restored);
  }

  String _demoDirectoryCursor(int lastIndex) => 'demo:$lastIndex';

  /// Demo fixture 的会话身份：root Thread 自持会话，child 显式携带 root 链接。
  ///
  /// 这是数据制造侧的显式字段读取，不是运行期从 ID 形状推断身份。
  String _demoSessionIdOf(StudioThread thread) =>
      thread.rootThreadId.isEmpty ? thread.id : thread.rootThreadId;

  /// 目录行的 demo 投影：身份四元组来自 fixture 的显式父子/根链接字段。
  SessionDirectoryRow _directoryRowOf(
    StudioThread thread, {
    bool archived = false,
  }) => SessionDirectoryRow(
    sessionId: _demoSessionIdOf(thread),
    agentId: thread.id,
    parentAgentId: thread.parentThreadId,
    threadId: thread.id,
    workspaceId: thread.workspaceId,
    title: thread.title,
    mode: thread.isRoot ? thread.mode : null,
    delegationMode: thread.delegationMode,
    delegationPreference: thread.delegationPreference,
    workspaceMode: thread.workspaceMode,
    workspacePath: thread.workspacePath,
    role: thread.role,
    backend: NativeAgentBackendView(
      config: NativeAgentConfigView(route: thread.frozenModel),
      status: thread.status,
    ),
    createdAt: thread.effectiveCreatedAt,
    updatedAt: thread.updatedAt,
    lastUserMessageAt: thread.lastUserMessageAt,
    archived: archived,
  );

  /// 目录可见的全部 fixture Thread（工作区、已创建 root 与分页填充）。
  Map<String, StudioThread> _demoDirectoryThreads() => {
    for (final thread in [
      ..._workspaces.values.map((workspace) => workspace.thread),
      ..._createdRootThreads,
      ..._pageFillThreads,
    ])
      thread.id: thread,
  };

  List<SessionDirectoryRow> _demoAllRows() => [
    for (final thread in _demoDirectoryThreads().values)
      _directoryRowOf(
        thread,
        archived: _archivedThreadIds.contains(_demoSessionIdOf(thread)),
      ),
  ];

  NewThreadModelRoute _demoNativeRoute(StudioThread thread) {
    if (thread.frozenModel case final route?) return route;
    final mode = thread.isRoot
        ? thread.mode
        : _workspaces[thread.rootThreadId]?.thread.mode;
    if (mode == null) {
      throw StateError(
        'Native demo route requires a root mode or frozen model',
      );
    }
    final route = _demoModeRoute(mode);
    return NewThreadModelRoute(
      accountId: route.accountId,
      modelId: route.modelId,
      effort: route.effort,
    );
  }

  ThreadWorkspace _rootWorkspace(StudioThread thread, DateTime now) {
    final route = _demoNativeRoute(thread);
    final userCreatedAt = now.subtract(const Duration(minutes: 9));
    final agentCreatedAt = now.subtract(const Duration(minutes: 8));
    final display = _historyOf(thread.id);
    display.declareDisplay('turn-demo:user', ['turn-demo:user'], work: false);
    display.declareDisplay('turn-demo:work', [
      'turn-demo:reasoning',
      'turn-demo:tool',
    ], work: true);
    display.declareDisplay('turn-demo:final', ['turn-demo:final'], work: false);
    _installDemoHistory(thread.id, [
      _messageItem(
        id: 'turn-demo:user',
        threadId: thread.id,
        turnId: 'turn-demo',
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
        updatedAt: agentCreatedAt,
        content: _demoTool(
          invocation: const _DemoInvocation(
            toolCallId: 'turn-demo:tool-call',
            name: 'exec',
            presentationContract: 'builtin.exec@2',
          ),
          arguments: '{"command":"cargo test -p pl-studio-bridge"}',
          outcome: _demoToolSucceeded(agentCreatedAt),
          result: '1 passed; bridge envelope uses typed payload.',
        ),
      ),
      _messageItem(
        id: 'turn-demo:final',
        threadId: thread.id,
        turnId: 'turn-demo',
        channel: ThreadTextChannel.finalAnswer,
        text:
            '### Streaming Markdown preview\n\n'
            '正文、**加粗**、`inline code` 和链接都按 GFM 渲染。',
        createdAt: agentCreatedAt,
      ),
    ]);
    display.sealDisplay('turn-demo:user');
    display.sealDisplay('turn-demo:work');
    display.sealDisplay('turn-demo:final');
    return ThreadWorkspace(
      businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
      thread: thread,
      revision: 1,
      interactions: const [],
      modelRoute: ThreadModelRouteView(
        accountId: route.accountId,
        modelId: route.modelId,
        effort: route.effort,
        revision: 1,
        available: true,
      ),
      runtime: ThreadRuntimeView(
        modelId: 'planner/local-responses',
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
    final display = _historyOf(thread.id);
    display.declareDisplay('${thread.id}:final', [
      '${thread.id}:final',
    ], work: false);
    _installDemoHistory(thread.id, [
      _messageItem(
        id: '${thread.id}:final',
        threadId: thread.id,
        turnId: '${thread.id}:turn',
        channel: ThreadTextChannel.finalAnswer,
        text: text,
        createdAt: createdAt,
      ),
    ]);
    display.sealDisplay('${thread.id}:final');
    return ThreadWorkspace(
      businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
      thread: thread,
      revision: 1,
      interactions: const [],
      modelRoute: ThreadModelRouteView(
        accountId: _demoNativeRoute(thread).accountId,
        modelId: modelId,
        effort: null,
        revision: 1,
        available: true,
      ),
      runtime: ThreadRuntimeView(
        modelId: modelId,
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
  Future<ChatGptLoginCommandReply> startChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) => Future.error(
    UnsupportedError('ChatGPT login is unavailable in demo mode'),
  );

  @override
  Future<ChatGptLoginCommandReply> cancelChatGptLogin({
    required String loginId,
    required String editorId,
    required String accountId,
  }) => Future.error(
    UnsupportedError('ChatGPT login is unavailable in demo mode'),
  );

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
  Future<AcpLocalDetectionCommandReply> startAcpLocalDetection({
    required OperationId operationId,
  }) => Future.error(
    UnsupportedError('Local executable detection requires the production Host'),
  );
  @override
  Future<AcpLocalDetectionCommandReply> cancelAcpLocalDetection({
    required OperationId operationId,
    required OperationId targetOperationId,
  }) => Future.error(
    UnsupportedError('Local executable detection requires the production Host'),
  );

  @override
  Future<SettingsCommandReply> saveAcpAccount(
    int expectedSettingsRevision,
    AcpAccountUpdateView account, {
    required OperationId operationId,
    required BigInt? expectedDocumentRevision,
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
    if (previous?.documentRevision != expectedDocumentRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'ACP definition changed; reload before saving',
        retryable: false,
        correlationId: 'demo-acp-document',
      );
    }
    final identityChanged =
        previous == null ||
        previous.template != account.template ||
        previous.command != account.command ||
        !listEquals(previous.args, account.args ?? const []) ||
        !mapEquals(previous.env, account.env) ||
        previous.enabled != account.enabled;
    final saved = AcpAccountSettingsView(
      accountId: account.accountId,
      name: account.name,
      template: account.template,
      command: account.command,
      args: account.args ?? const [],
      env: account.env,
      enabled: account.enabled,
      documentRevision:
          (previous?.documentRevision ?? BigInt.zero) + BigInt.one,
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
    required BigInt expectedDocumentRevision,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    if (_demoAcpAccount(accountId).documentRevision !=
        expectedDocumentRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'ACP definition changed; reload before removing',
        retryable: false,
        correlationId: 'demo-acp-document',
      );
    }
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
      AcpCheckActionView() => _demoAcpAuth.check(account, operationId.value),
      AcpQueryUsageActionView() => _demoAcpAuth.queryUsage(
        account,
        operationId.value,
      ),
    };
    return _demoAcpReply(operationId, snapshot);
  }

  @override
  Future<AcpAuthCommandReply> continueAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required OperationId targetOperationId,
    required String methodId,
  }) async {
    _ensureDemoRunning();
    final account = _demoAcpAccount(accountId);
    if (account.connectionRevision != expectedConnectionRevision) {
      throw StateError('ACP connection identity changed');
    }
    return _demoAcpReply(
      operationId,
      _demoAcpAuth.authenticate(account, methodId, targetOperationId.value),
    );
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
    version: '1.4.5',
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
                  program: '/home/studio/acp-servers/antigravity/1.4.5/program',
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
      definition: AgentDefinitionView(
        definitionId: draft.id,
        displayName: draft.definition.displayName,
        description: draft.definition.description,
        whenToUse: draft.definition.whenToUse,
        source: '~/.anywork/agents/${draft.id}.toml',
        revision: 'demo-user-${draft.id}',
        contentHash: 'demo-user-${draft.id}',
      ),
      binding: draft.binding,
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
  Future<StudioProject> renameProject(String workspaceId, String name) async {
    final project = _demoProjectDirectory().values.firstWhere(
      (project) => project.id == workspaceId,
    );
    _projectNames[workspaceId] = name;
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
  Future<void> activateProject(String workspaceId) async {
    if (!_demoProjectDirectory().values.any(
      (project) => project.id == workspaceId,
    )) {
      throw StateError('unknown demo project $workspaceId');
    }
    _selectedProjectId = workspaceId;
  }

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String workspaceId,
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
          .where((candidate) => candidate.id == workspaceId)
          .firstOrNull;
      if (project == null) {
        throw StateError('unknown demo project $workspaceId');
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
          workspaceId: workspaceId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.checkingProject,
        ),
      );
      final now = DateTime.now();
      final provisionalTitle = _demoProvisionalThreadTitle(input.text);
      final threadId = 'thread-created-${++_threadSequence}';
      final projectPath = projects
          .firstWhere((project) => project.id == workspaceId)
          .path;
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          workspaceId: workspaceId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.preparingWorkspace,
        ),
      );
      final thread = StudioThread(
        id: threadId,
        workspaceId: workspaceId,
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
          workspaceId: workspaceId,
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
        runtime: workspace.runtime.copyWith(modelId: route.modelId),
        modelRoute: ThreadModelRouteView(
          accountId: route.accountId,
          modelId: route.modelId,
          effort: route.effort,
          revision: 1,
          available: true,
        ),
      );
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          workspaceId: workspaceId,
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
      thread: _directoryRowOf(renamed),
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
          account.template?.wire ?? '',
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
        upserted: [
          _directoryRowOf(
            thread,
            archived: _archivedThreadIds.contains(_demoSessionIdOf(thread)),
          ),
        ],
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
        definition: const AgentDefinitionView(
          definitionId: 'explorer',
          displayName: 'Explorer',
          description: '只读探索代码、文档和现场事实。',
          whenToUse: '需要定位边界、依赖或验证事实时。',
          source: 'studio-builtin',
          revision: 'studio-system-agent-v1',
          contentHash: 'demo-explorer',
        ),
        binding: const NativeAgentBindingView(
          route: NewThreadModelRoute(
            accountId: 'demo',
            modelId: 'demo',
            effort: 'medium',
          ),
          systemInstructions: '优先收集事实并引用文件与命令。',
        ),
        system: true,
        enabled: !_disabledSystemAgents.contains('explorer'),
        workspaceMode: AgentWorkspaceMode.unrestricted,
      ),
      AgentProfileView(
        definition: const AgentDefinitionView(
          definitionId: 'executor',
          displayName: 'Executor',
          description: '在项目目录内实施边界明确的修改。',
          whenToUse: '需要限制 糊来帮内置文件写工具的修改目录时。',
          source: 'studio-builtin',
          revision: 'studio-system-agent-v2',
          contentHash: 'demo-executor',
        ),
        binding: const NativeAgentBindingView(
          route: NewThreadModelRoute(
            accountId: 'demo',
            modelId: 'demo',
            effort: 'medium',
          ),
          systemInstructions: '遵守冻结的 writablePaths。',
        ),
        system: true,
        enabled: !_disabledSystemAgents.contains('executor'),
        workspaceMode: AgentWorkspaceMode.directory,
      ),
      AgentProfileView(
        definition: const AgentDefinitionView(
          definitionId: 'worktree_executor',
          displayName: 'Worktree Executor',
          description: '在独立 Git worktree 内实施修改。',
          whenToUse: '需要物理隔离并显式整合 commit 时。',
          source: 'studio-builtin',
          revision: 'studio-system-agent-v2',
          contentHash: 'demo-worktree_executor',
        ),
        binding: const NativeAgentBindingView(
          route: NewThreadModelRoute(
            accountId: 'demo',
            modelId: 'demo',
            effort: 'medium',
          ),
          systemInstructions: '只修改分配的 worktree，不自动整合。',
        ),
        system: true,
        enabled: !_disabledSystemAgents.contains('worktree_executor'),
        workspaceMode: AgentWorkspaceMode.worktree,
      ),
      AgentProfileView(
        definition: const AgentDefinitionView(
          definitionId: 'reviewer',
          displayName: 'Reviewer',
          description: '独立审查实现和验证证据。',
          whenToUse: '需要复核实现质量时。',
          source: 'studio-builtin',
          revision: 'studio-system-agent-v2',
          contentHash: 'demo-reviewer',
        ),
        binding: const NativeAgentBindingView(
          route: NewThreadModelRoute(
            accountId: 'demo',
            modelId: 'demo',
            effort: 'medium',
          ),
          systemInstructions: '只读审查并报告具体证据。',
        ),
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
    final rows = _sortedDirectoryRows();
    final row = rows
        .where((candidate) => candidate.threadId == threadId)
        .firstOrNull;
    if (row == null || !row.isRootRow) {
      throw StateError('only a root Thread can be archived');
    }
    // 归档前先结束会话树的活动工作：中断正在运行的 Turn，再归档。
    final activeTurn = _workspaces[threadId]?.activeTurn;
    if (activeTurn != null && activeTurn.state.isBusy) {
      _interruptDemoTurn(threadId, activeTurn.turnId);
    }
    final roots = rows.where((candidate) => candidate.isRootRow).toList();
    final index = roots.indexWhere(
      (candidate) => candidate.threadId == threadId,
    );
    if (index < 0) throw StateError('unknown demo root Thread $threadId');
    final nextRoot = index + 1 < roots.length
        ? roots[index + 1]
        : index > 0
        ? roots[index - 1]
        : null;
    final removedThreadIds = <String>{
      threadId,
      for (final candidate in _ensureWorkspaceFixture().threads)
        if (_demoSessionIdOf(candidate) == threadId) candidate.id,
    }.toList();
    _archivedThreadIds.add(threadId);
    if (_selectedThreadId == threadId) _selectedThreadId = nextRoot?.threadId;
    _threadDirectoryRevision += 1;
    _publishProductPayload(
      ThreadDirectoryChangedPayload(
        revision: _threadDirectoryRevision,
        upserted: const [],
        removed: removedThreadIds,
      ),
    );
    // 归档真实提交后撤下该宿主的待决集合投影（成员同被移除）。
    _publishChildInteractionsIfChanged(threadId);
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
  Future<DeleteThreadCommandReply?> deleteThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    _ensureDemoRunning();
    final allThreads = <StudioThread>[
      ..._workspaces.values.map((workspace) => workspace.thread),
      ..._createdRootThreads,
      ..._pageFillThreads,
    ];
    final root = allThreads
        .where((thread) => thread.id == threadId)
        .firstOrNull;
    if (root == null) return null;
    if (!root.isRoot) {
      throw StateError('only a root Thread can be deleted');
    }

    final roots = _sortedDirectoryRows()
        .where((row) => row.isRootRow && !row.archived)
        .toList();
    final index = roots.indexWhere((row) => row.threadId == threadId);
    final nextRow = index < 0
        ? roots.where((row) => row.threadId != threadId).firstOrNull
        : index + 1 < roots.length
        ? roots[index + 1]
        : index > 0
        ? roots[index - 1]
        : null;
    final nextRoot = nextRow;
    final deletedThreadIds = <String>{
      for (final thread in allThreads)
        if (_demoSessionIdOf(thread) == _demoSessionIdOf(root)) thread.id,
    }.toList();

    for (final id in deletedThreadIds) {
      final activeTurn = _workspaces[id]?.activeTurn;
      if (activeTurn != null && activeTurn.state.isBusy) {
        _interruptDemoTurn(id, activeTurn.turnId);
      }
    }
    _workspaces.removeWhere(
      (id, workspace) =>
          deletedThreadIds.contains(id) ||
          deletedThreadIds.contains(workspace.thread.id),
    );
    _createdRootThreads.removeWhere(
      (thread) => deletedThreadIds.contains(thread.id),
    );
    _pageFillThreads.removeWhere(
      (thread) => deletedThreadIds.contains(thread.id),
    );
    _archivedThreadIds.remove(threadId);
    _histories.removeWhere((id, _) => deletedThreadIds.contains(id));
    _pendingItems.removeWhere((id, _) => deletedThreadIds.contains(id));
    _promptGenerations.removeWhere((id, _) => deletedThreadIds.contains(id));
    _threadModes.removeWhere((id, _) => deletedThreadIds.contains(id));
    _demoContinuationPoints.removeWhere(
      (id, _) => deletedThreadIds.contains(id),
    );
    _resolvedInteractions.removeWhere(
      (_, value) => deletedThreadIds.contains(value.interaction.threadId),
    );
    _demoUserInputInvocations.removeWhere(
      (_, value) => deletedThreadIds.contains(value.$1.threadId),
    );

    if (_selectedThreadId != null &&
        deletedThreadIds.contains(_selectedThreadId)) {
      _selectedThreadId = nextRoot?.threadId;
    }
    _threadDirectoryRevision += 1;
    _publishProductPayload(
      ThreadDirectoryChangedPayload(
        revision: _threadDirectoryRevision,
        upserted: const [],
        removed: deletedThreadIds,
      ),
    );
    return DeleteThreadCommandReply(
      result: DeleteThreadResult(
        deletedRootId: threadId,
        deletedThreadIds: deletedThreadIds,
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
  Future<void> archiveProject(String workspaceId) async {
    if (workspaceId == 'project-local' &&
        _archivedProjectIds.add(workspaceId)) {
      _projectDirectoryRevision += 1;
      final removed = _workspaces.values
          .where((workspace) => workspace.thread.workspaceId == workspaceId)
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
      case SkillsExternalDirsCommand(:final value):
        _skills = _skills.copyWith(externalDirs: value);
      case SkillsDisabledCommand(:final value):
        _skills = _skills.copyWith(disabled: value);
      case SkillsAutoLearnMinToolCallsCommand(:final value):
        _skills = _skills.copyWith(autoLearnMinToolCalls: value);
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
    final row = _sortedDirectoryRows()
        .where((candidate) => candidate.threadId == threadId)
        .firstOrNull;
    final workspace = _workspaces[threadId];
    if (row == null || !row.isRootRow || workspace == null) {
      throw StateError('unknown root demo thread $threadId');
    }
    final previousRoute = workspace.modelRoute;
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
    if (!row.isRootRow ||
        row.backend is! NativeAgentBackendView ||
        row.mode == null) {
      throw StateError(
        'Saving a Native mode route requires a Native root with mode',
      );
    }
    _modeRoutes = [
      for (final route in current.modeModelRoutes)
        if (route.modeId != row.mode) route,
      ModeModelRouteView(
        modeId: row.mode!,
        accountId: accountId,
        modelId: modelId,
        effort: selectedEffort ?? '',
      ),
    ];
    _settingsRevision += 1;
    final route = ThreadModelRouteView(
      accountId: accountId,
      modelId: modelId,
      effort: selectedEffort,
      revision: previousRoute.revision + 1,
      available: true,
    );
    _workspaces[threadId] = workspace.copyWith(modelRoute: route);
    // route remains an independent Thread fact in the typed update.
    _emitThreadUpdate(
      threadId,
      ThreadRuntimeUpdate(
        runtime: workspace.runtime,
        todo: workspace.todo,
        modelRoute: route,
      ),
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
          _demoStamp('thread-route:$threadId', route.revision),
          _demoStamp('settings', settings.revision),
        ],
        effect: EffectPoint.nextTurn,
      ),
      runtime: workspace.runtime,
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
    final row = _sortedDirectoryRows()
        .where((candidate) => candidate.threadId == threadId)
        .firstOrNull;
    if (row == null) {
      throw StateError('unknown demo thread $threadId');
    }
    if (!row.isRootRow) {
      throw StateError('only a root Thread can change mode');
    }
    if (row.backend is! NativeAgentBackendView ||
        row.mode == null ||
        (row.backend as NativeAgentBackendView).status !=
            ThreadStatusView.idle) {
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
        role: row.isRootRow ? 'planner' : thread.role,
      );
      final modelRoute = route == null || workspace.modelRoute == null
          ? workspace.modelRoute
          : ThreadModelRouteView(
              accountId: route.accountId,
              modelId: route.modelId,
              effort: route.effort,
              revision: workspace.modelRoute!.revision + 1,
              available: true,
            );
      _emitThreadUpdate(
        threadId,
        ThreadRuntimeUpdate(
          runtime: workspace.runtime,
          todo: workspace.todo,
          modelRoute: modelRoute,
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
        AcpLocalDetectionTarget() => const AcpLocalDetectionTopic(),
        ChatGptLoginTarget() => const SettingsConfigTopic(),
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
      McpCatalogTopic(:final scope) => McpCatalogBaseline(
        _demoMcpCatalog(scope),
      ),
      ThreadMcpTopic(:final threadId) => ThreadMcpBaseline(
        _demoThreadMcp(threadId),
      ),
      LspTopic() => LspBaseline(_demoLspState()),
      SkillsTopic(:final workspaceId) => SkillsBaseline(
        _demoSkillsState(workspaceId, _skillsRevision),
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
      AcpLocalDetectionTopic() => const AcpLocalDetectionBaseline(
        AcpLocalDetectionSnapshotView.idle(),
      ),
      BotsTopic() => BotsBaseline(_demoBotsState()),
      ChildInteractionsTopic(:final hostThreadId) => ChildInteractionsBaseline(
        _demoChildInteractionsState(hostThreadId),
      ),
    };
    final revision = switch (baseline) {
      ProjectDirectoryBaseline(:final state) => state.revision,
      ThreadDirectoryBaseline(:final page) => page.revision,
      AgentDirectoryBaseline(:final state) => state.revision,
      SettingsConfigBaseline(:final state) => state.revision,
      ModelCatalogBaseline(:final state) => state.modelCatalogRevision,
      RecoveryBaseline(:final state) => state.revision,
      McpCatalogBaseline(:final state) => state.revision,
      ThreadMcpBaseline(:final state) => state.generation,
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
      AcpLocalDetectionBaseline(:final state) => state.revision,
      BotsBaseline(:final state) => state.revision,
      ChildInteractionsBaseline(:final state) => state.state.revision,
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

  /// Thread 首帧只暴露当前状态；历史正文由独立 reader 和完成尾部交付。
  ThreadWorkspace _snapshotOf(ThreadWorkspace workspace) {
    final history = _historyOf(workspace.thread.id);
    history.prepareCurrent(workspace);
    final plan = workspace.runtime.plan;
    final references = ThreadBusinessRefs(
      plan: plan == null
          ? null
          : CurrentPlanHead(
              revision: plan.revision,
              phase: plan.state,
              document: plan.document == null
                  ? null
                  : ContentRef(
                      databaseId: history.epoch,
                      target: BodyContentTarget(
                        owner: CurrentContentOwner(
                          domain: 'plan',
                          id: workspace.thread.id,
                          revision: plan.revision,
                        ),
                        key: 'plan.document',
                      ),
                    ),
            ),
      interactions: CurrentCollectionRef(
        databaseId: history.epoch,
        collection: 'interactions',
        revision: history.interactionRevision,
      ),
    );
    return workspace.copyWith(latestTurn: null, businessRefs: references);
  }

  /// 完成尾部与当前活动共享有界交付；历史查询独立持有读取 scope。
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    _ensureDemoRunning();
    if (!_workspaces.containsKey(threadId)) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Unknown Demo conversation',
        retryable: false,
        correlationId: 'demo-conversation-not-found',
      );
    }
    final connection = _DemoConversationFeed(
      this,
      threadId,
      _historyOf(threadId),
      scope,
      demand,
    );
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

  Future<TimelineFeed> Function(String, TimelineFeed)? _timelineFeedFactory;

  @visibleForTesting
  set timelineFeedFactory(
    Future<TimelineFeed> Function(String, TimelineFeed)? factory,
  ) => _timelineFeedFactory = factory;

  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) async {
    _ensureDemoRunning();
    if (!_workspaces.containsKey(threadId)) throw _demoMissing();
    final connection = _DemoTimelineFeed(
      this,
      threadId,
      _historyOf(threadId),
      demand,
    );
    _ownedConversationFeeds.add(connection);
    final factory = _timelineFeedFactory;
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

  /// 独立状态订阅：只承载 State/Failure/Closed，身份、序号与 ACK 都与内容连接无关。
  @override
  Future<ConversationStateFeed> openConversationStateFeed(
    String threadId,
  ) async {
    _ensureDemoRunning();
    if (!_workspaces.containsKey(threadId)) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Unknown Demo conversation',
        retryable: false,
        correlationId: 'demo-conversation-not-found',
      );
    }
    final connection = _DemoConversationStateFeed(this, threadId);
    _ownedConversationStateFeeds.add(connection);
    final factory = _conversationStateFeedFactory;
    if (factory == null) return connection;
    final opening = Completer<void>();
    _openingConversationFeeds.add(opening.future);
    try {
      final feed = await factory(threadId, connection);
      _ownedConversationStateFeeds.add(feed);
      if (_runtimeExiting) {
        await _closeDemoStateFeed(feed);
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

  @visibleForTesting
  void seedDisplayBlocks({
    required String threadId,
    required List<DisplayBlock> blocks,
    LiveDisplayWindow? live,
    Map<DisplayBlockRef, List<DisplayMemberHead>>? members,
  }) {
    _ensureDemoRunning();
    _demoWorkspace(threadId);
    final history = _historyOf(threadId);
    history.installDisplay(blocks: blocks, live: live, members: members);
    _publishContent(threadId);
  }

  /// 测试专用：包装状态订阅，用于状态流故障注入（首帧失败、断流、EOF、慢打开）。
  Future<ConversationStateFeed> Function(
    String threadId,
    ConversationStateFeed connection,
  )?
  _conversationStateFeedFactory;

  @visibleForTesting
  set conversationStateFeedFactory(
    Future<ConversationStateFeed> Function(
      String threadId,
      ConversationStateFeed connection,
    )?
    factory,
  ) {
    _conversationStateFeedFactory = factory;
  }

  /// 明确的 Demo producer 边界。scope 决定成员资格，不解析未知 payload。
  /// 正文身份和 bodies 必须由调用方在提交消息时明确给出，不猜 renderer。
  @visibleForTesting
  void seedChatAtoms(
    String threadId,
    Iterable<ChatAtom> atoms, {
    required ChatScope scope,
    List<ChatSourceState> sources = const [],
  }) {
    _ensureDemoRunning();
    _demoWorkspace(threadId);
    var changed = false;
    final history = _historyOf(threadId);
    for (final source in sources) {
      history.sourceStates[source.source] = source;
    }
    for (final atom in atoms) {
      changed = history.accept(atom, scope) || changed;
    }
    if (changed) _publishContent(threadId);
  }

  @visibleForTesting
  String conversationDatabaseId(String threadId) => _historyOf(threadId).epoch;

  /// Explicit display fixtures and their already chosen member scopes. No atom
  /// grouping or payload-based membership inference is performed by Demo.
  @visibleForTesting
  void seedTimelineItems(String threadId, Iterable<CompletedEntry> items) {
    _ensureDemoRunning();
    _demoWorkspace(threadId);
    final history = _historyOf(threadId);
    var changed = false;
    for (final item in items) {
      changed = history.acceptDisplay(item) || changed;
    }
    if (changed) _publishContent(threadId);
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
    final route = workspace.modelRoute;
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
        modelRoute: workspace.modelRoute,
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
    _historyOf(threadId)
        .declareDisplay(input.inputId, [input.inputId], work: false);
    _upsertChatItem(
      threadId,
      _messageItem(
        id: input.inputId,
        threadId: threadId,
        turnId: turnId,
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
    _historyOf(threadId).sealDisplay(input.inputId);
    _publishContent(threadId);
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
    _historyOf(threadId).declareDisplay(
      '$turnId:work',
      [reasoningId, '$turnId:tool'],
      work: true,
      turnId: turnId,
    );
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
      field: 'part.summaryText.0',
      text: '## Inspecting',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      field: 'part.summaryText.0',
      text: ' the request\n\nChecking the live ThreadItem projection.',
    );
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      field: 'part.reasoningText.0',
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
    final liveReasoning = _pendingItemsOf(threadId)
        .firstWhere((item) => item.id == reasoningId);
    final reasoningCompletedAt = DateTime.now();
    _upsertChatItem(
      threadId,
      _demoRevise(
        liveReasoning,
        updatedAt: reasoningCompletedAt,
        content: _demoThinking(
          summary: const [reasoningSummary],
          content: const [reasoningContent],
          lifecycle: CompletedThreadContentView(reasoningCompletedAt),
        ),
      ),
    );
    final commentaryId = '$turnId:commentary';
    // This story's commentary is an independent Single, not a Work member.
    _historyOf(
      threadId,
    ).declareDisplay(commentaryId, [commentaryId], work: false, turnId: turnId);
    _upsertChatItem(
      threadId,
      _demoItem(
        id: commentaryId,
        threadId: threadId,
        turnId: turnId,
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
      field: 'body',
      text: '正在逐段核对 Timeline',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: commentaryId,
      field: 'body',
      text: ' 的 typed delta。',
    );
    final commentaryCompletedAt = DateTime.now();
    final liveCommentary = _pendingItemsOf(threadId)
        .firstWhere((item) => item.id == commentaryId);
    _upsertChatItem(
      threadId,
      _demoRevise(
        liveCommentary,
        updatedAt: commentaryCompletedAt,
        content: _demoText(
          channel: ThreadTextChannel.commentary,
          text: '正在逐段核对 Timeline 的 typed delta。',
          attachments: const [],
          lifecycle: CompletedThreadContentView(commentaryCompletedAt),
        ),
      ),
    );
    _historyOf(threadId).sealDisplay(commentaryId);
    _publishContent(threadId);
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
        updatedAt: startedAt,
        content: _demoTool(
          invocation: _DemoInvocation(
            toolCallId: '$turnId:tool-call',
            name: 'exec',
            presentationContract: 'builtin.exec@2',
          ),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: toolId,
      field: 'tool.arguments',
      text: '{"command":"cargo test -p pl-model ',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: toolId,
      field: 'tool.arguments',
      text: '--test provider_wire"}',
    );
    final streamedTool = _pendingItemsOf(threadId)
        .firstWhere((item) => item.id == toolId);
    final streamedToolState = streamedTool.content.invocation!;
    _upsertChatItem(
      threadId,
      _demoRevise(
        streamedTool,
        updatedAt: DateTime.now(),
        content: _demoTool(
          invocation: streamedToolState,
          arguments: streamedTool.textFor('tool.arguments')!,
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: toolId,
      field: 'tool.result',
      text: 'running widget tests...\n',
    );
    await _waitDemo(promptToolDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: toolId,
      field: 'tool.result',
      text: '[stderr] analyzer warnings: 0\n',
    );
    final runningTool = _pendingItemsOf(threadId)
        .firstWhere((item) => item.id == toolId);
    final runningToolState = runningTool.content.invocation!;
    final toolCompletedAt = DateTime.now();
    _upsertChatItem(
      threadId,
      _demoRevise(
        runningTool,
        updatedAt: toolCompletedAt,
        content: _demoTool(
          invocation: runningToolState,
          outcome: _demoToolSucceeded(toolCompletedAt),
          arguments: runningTool.textFor('tool.arguments')!,
          result: 'running widget tests...\n[stderr] analyzer warnings: 0\nAll widget tests passed.',
        ),
      ),
    );
    final finalId = '$turnId:final';
    _historyOf(threadId).sealDisplay('$turnId:work');
    _historyOf(threadId)
        .declareDisplay(finalId, [finalId], work: false, turnId: turnId);
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: null,
      kind: ThreadActivityKind.responding,
    );
    _upsertChatItem(
      threadId,
      _demoItem(
        id: finalId,
        threadId: threadId,
        turnId: turnId,
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
      field: 'body',
      text: 'Demo response for: **$trimmedPrompt**',
    );
    await _waitDemo(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    const finalSuffix = '\n\n- reasoning、tool output 与 Plan 都直接来自 typed delta';
    _appendChatContent(
      threadId,
      itemId: finalId,
      field: 'body',
      text: finalSuffix,
    );
    final finalCompletedAt = DateTime.now();
    final liveFinal = _pendingItemsOf(threadId)
        .firstWhere((item) => item.id == finalId);
    _upsertChatItem(
      threadId,
      _demoRevise(
        liveFinal,
        updatedAt: finalCompletedAt,
        content: _demoText(
          channel: ThreadTextChannel.finalAnswer,
          text: 'Demo response for: **$trimmedPrompt**$finalSuffix',
          attachments: const [],
          lifecycle: CompletedThreadContentView(finalCompletedAt),
        ),
      ),
    );
    _historyOf(threadId).sealDisplay(finalId);
    _publishContent(threadId);
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
    final row = _sortedDirectoryRows()
        .where((candidate) => candidate.threadId == threadId)
        .firstOrNull;
    if (row != null && !row.isRootRow) {
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
    if (workspace.modelRoute?.revision != expectedModelRouteRevision) {
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
          modelRoute: current.modelRoute,
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
    return _collectChildInteractions(hostThreadId);
  }

  /// 主会话可见的子任务待决交互集合；child Plan 是诊断事实，不进入集合。
  List<ChildInteractionSummary> _collectChildInteractions(String hostThreadId) {
    // 归档的宿主或成员不再是可见事实来源：集合排除已归档子树。
    if (_archivedThreadIds.contains(hostThreadId)) return const [];
    final summaries = <ChildInteractionSummary>[];
    for (final workspace in _workspaces.values) {
      if (workspace.thread.parentThreadId != hostThreadId) continue;
      if (_archivedThreadIds.contains(_demoSessionIdOf(workspace.thread))) {
        continue;
      }
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

  final Map<String, int> _childInteractionRevisions = {};
  final Map<String, List<ChildInteractionSummary>> _childInteractionPublished =
      {};

  ChildInteractionsStateView _demoChildInteractionsState(String hostThreadId) {
    // Baseline reads the currently published projection; a host never
    // published before starts at its first snapshot without bumping revision.
    final published = _childInteractionPublished[hostThreadId];
    final items =
        published ??
        _childInteractionPublished.putIfAbsent(
          hostThreadId,
          () => List.unmodifiable(_collectChildInteractions(hostThreadId)),
        );
    return ChildInteractionsStateView(
      hostThreadId: hostThreadId,
      state: ReadyObservedResource(
        revision: _childInteractionRevisions[hostThreadId] ?? 0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastCheckedAt: null,
        value: ChildInteractionsData(items: items),
      ),
    );
  }

  /// 交互事实变化后重算宿主集合：未变集合不提升领域 revision。
  void _publishChildInteractionsIfChanged(String hostThreadId) {
    final current = _collectChildInteractions(hostThreadId);
    final previous = _childInteractionPublished[hostThreadId];
    if (previous != null && _sameChildInteractionSummaries(previous, current)) {
      return;
    }
    _childInteractionPublished[hostThreadId] = List.unmodifiable(current);
    final revision = (_childInteractionRevisions[hostThreadId] ?? 0) + 1;
    _childInteractionRevisions[hostThreadId] = revision;
    _publishProductPayload(
      ChildInteractionsChangedPayload(
        ChildInteractionsStateView(
          hostThreadId: hostThreadId,
          state: ReadyObservedResource(
            revision: revision,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            lastCheckedAt: null,
            value: ChildInteractionsData(items: current),
          ),
        ),
      ),
    );
  }

  bool _sameChildInteractionSummaries(
    List<ChildInteractionSummary> left,
    List<ChildInteractionSummary> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].childThreadId != right[i].childThreadId ||
          left[i].interactionId != right[i].interactionId ||
          left[i].kind != right[i].kind ||
          left[i].revision != right[i].revision) {
        return false;
      }
    }
    return true;
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
    if (decided.threadId != hostThreadId &&
        _demoPlanRequests.containsKey(decided.id)) {
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
    final planRequest = _demoPlanRequests[interactionId];
    // Validate the original command shape on replay too: the generic facts map
    // intentionally normalizes question keys and cannot prove answer uniqueness.
    final planDecision = planRequest == null
        ? null
        : _demoPlanDecision(resolution);
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
    if (planRequest != null) {
      _validateDemoPlanRequest(planRequest, interaction);
    }
    final completedAt = DateTime.now();
    if (planRequest != null && planDecision != null) {
      // Canonical admission can still reject a conflicting completion; do that
      // before mutating the runtime, interaction, or operation receipt table.
      final completion = _demoPlanCompletion(
        planRequest,
        planDecision,
        completedAt,
      );
      _completeDemoItem(completion);
      final display = _historyOf(completion.threadId);
      display.declareDisplay(completion.id, [completion.id], work: false);
      display.sealDisplay(completion.id);
    }
    final receipt = _demoReceipt(
      operationId,
      changed: true,
      targets: const [],
      effect: EffectPoint.immediate,
      requiresIdentityObservation: true,
    );
    if (planRequest == null && resolution is UserInputResolutionCommand) {
      _sealDemoUserInput(interaction, resolution);
    }
    if (planRequest?.document != null && planDecision != null) {
      final workspace = _workspaces[interaction.threadId]!;
      final plan = workspace.runtime.plan!;
      _workspaces[interaction.threadId] = workspace.copyWith(
        runtime: workspace.runtime.copyWith(
          plan: plan.copyWith(
            revision: plan.revision + 1,
            state: planDecision.decision == _DemoPlanDecisionKind.approved
                ? PlanRuntimePhase.approved
                : PlanRuntimePhase.revisionRequested,
            updatedAt: completedAt,
          ),
        ),
      );
    }
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
    if (planRequest != null) _publishContent(interaction.threadId);
    if (interaction.kind == InteractionKind.userInput) {
      _advanceDemoLastUserMessage(interaction.threadId, DateTime.now());
    }
    return InteractionCommandReply(interaction: interaction, receipt: receipt);
  }

  void _sealDemoUserInput(
    PendingInteraction interaction,
    UserInputResolutionCommand resolution,
  ) {
    final payload = interaction.payload;
    if (payload is! UserInputInteractionPayload) {
      throw _conversationQueryFailure;
    }
    final answers = {
      for (final answer in resolution.answers)
        answer.questionId: answer.answers,
    };
    final fields = <String, String>{};
    for (var i = 0; i < payload.questions.length; i++) {
      final question = payload.questions[i];
      if (question.isSecret) continue;
      final prefix = 'tool.user-input.question.$i';
      fields['$prefix.header'] = question.header;
      fields['$prefix.body'] = question.question;
      for (var j = 0; j < question.options.length; j++) {
        fields['$prefix.option.$j.label'] = question.options[j].label;
        fields['$prefix.option.$j.description'] =
            question.options[j].description;
      }
      final values = answers[question.id] ?? const <String>[];
      for (var j = 0; j < values.length; j++) {
        fields['tool.user-input.answer.$i.$j'] = values[j];
      }
    }
    final now = DateTime.now();
    // Publication follows the same command's removal of the pending interaction.
    // Do not expose completion with a pre-retirement current snapshot.
    _completeDemoItem(
      _demoItem(
        id: 'demo-user-input:${interaction.id}',
        threadId: interaction.threadId,
        turnId: interaction.turnId,
        updatedAt: now,
        content: (
          kind: _DemoContentKind.completed,
          mainPresentation: MainPresentation.single,
          contentPresent: null,
          textChannel: null,
          descriptor: {
            'type': 'tool',
            'data': {
              'invocation':
                  (identical(
                            _demoUserInputInvocations[interaction.id]?.$1,
                            interaction,
                          )
                          ? _demoUserInputInvocations[interaction.id]!.$2
                          : _DemoInvocation(
                              toolCallId: 'demo-user-input:${interaction.id}',
                              name: 'request_user_input',
                            ))
                      .toJson(),
              'state': _demoToolSucceeded(now),
              'wait': null,
              'userInput': {
                'interactionId': interaction.id,
                'questions': [
                  for (final question in payload.questions)
                    {
                      'id': question.id,
                      'isOther': question.isOther,
                      'isSecret': question.isSecret,
                      'optionCount': question.options.length,
                    },
                ],
                'state': {
                  'kind': 'resolved',
                  'answers': [
                    for (final question in payload.questions)
                      {
                        'questionId': question.id,
                        'answerCount': answers[question.id]?.length ?? 0,
                        'redacted': question.isSecret,
                      },
                  ],
                },
              },
            },
          },
          fields: fields,
          invocation: null,
        ),
      ),
    );
    final display = _historyOf(interaction.threadId);
    final displayId = 'demo-user-input:${interaction.id}';
    display.declareDisplay(displayId, [displayId], work: false);
    display.sealDisplay(displayId);
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
  Future<SkillsStateSnapshot> readSkillsState(String workspaceId) async {
    return _archivedProjectIds.contains(workspaceId)
        ? _demoSkillsState(workspaceId, 0, skills: const [])
        : _demoSkillsState(workspaceId, _skillsRevision);
  }

  @override
  Future<SkillsStateSnapshot> discoverSkills(String workspaceId) async {
    _skillsRevision += 1;
    final state = await readSkillsState(workspaceId);
    _publishProductPayload(SkillsStateChangedPayload(state));
    return state;
  }

  @override
  Future<SkillSearchResultView> searchSkills(
    String workspaceId,
    String query, {
    int limit = 50,
  }) async {
    final snapshot = await readSkillsState(workspaceId);
    final normalizedQuery = query.trim().toLowerCase();
    final allMatches = snapshot.summaries
        .where(
          (skill) =>
              skill.name.toLowerCase().contains(normalizedQuery) ||
              skill.description.toLowerCase().contains(normalizedQuery),
        )
        .toList();
    return SkillSearchResultView(
      workspaceId: workspaceId,
      catalogRevision: snapshot.catalogRevision,
      matches: allMatches.take(limit).toList(),
      truncated: allMatches.length > limit,
    );
  }

  @override
  Future<McpCatalogSnapshot> readMcpCatalog(McpScope scope) async =>
      _demoMcpCatalog(scope);

  @override
  Future<McpCatalogSnapshot> reloadMcpCatalog(McpScope scope) async {
    _bumpDemoMcpCatalogRevision(scope);
    final snapshot = _demoMcpCatalog(scope);
    _publishProductPayload(McpCatalogChangedPayload(snapshot));
    return snapshot;
  }

  @override
  Future<McpDocumentContent> readMcpDocument(McpDocumentRef document) async {
    final stored = _mcpDocuments[document];
    if (stored == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'MCP document not found',
        retryable: false,
        correlationId: 'demo-mcp-document-not-found',
      );
    }
    return McpDocumentContent(
      document: document,
      id: stored.id,
      revision: stored.revision,
      rawToml: stored.rawToml,
    );
  }

  @override
  Future<McpDocumentCommitReceipt> createMcpDocument({
    required McpScope scope,
    required String id,
    required String rawToml,
  }) async {
    final trimmed = id.trim();
    final document = McpDocumentRef(
      scope: scope,
      relativePath: switch (scope) {
        HostMcpScope() => 'mcp/$trimmed.toml',
        SshMcpScope(:final sshAlias) => 'ssh/$sshAlias/mcp/$trimmed.toml',
      },
    );
    _mcpDocuments[document] = (id: trimmed, revision: 1, rawToml: rawToml);
    _bumpDemoMcpCatalogRevision(scope);
    final snapshot = _demoMcpCatalog(scope);
    _publishProductPayload(McpCatalogChangedPayload(snapshot));
    return McpDocumentCommitReceipt(
      document: document,
      revision: 1,
      snapshot: snapshot,
    );
  }

  @override
  Future<McpDocumentCommitReceipt> updateMcpDocument({
    required McpDocumentRef document,
    required int expectedRevision,
    required String rawToml,
  }) async {
    final existing = _mcpDocuments[document];
    if (existing == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'MCP document not found',
        retryable: false,
        correlationId: 'demo-mcp-document-not-found',
      );
    }
    if (existing.revision != expectedRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'MCP document revision conflict',
        retryable: true,
        correlationId: 'demo-mcp-document-stale-revision',
      );
    }
    final nextRevision = existing.revision + 1;
    _mcpDocuments[document] = (
      id: existing.id,
      revision: nextRevision,
      rawToml: rawToml,
    );
    _bumpDemoMcpCatalogRevision(document.scope);
    final snapshot = _demoMcpCatalog(document.scope);
    _publishProductPayload(McpCatalogChangedPayload(snapshot));
    return McpDocumentCommitReceipt(
      document: document,
      revision: nextRevision,
      snapshot: snapshot,
    );
  }

  @override
  Future<McpDocumentCommitReceipt> deleteMcpDocument({
    required McpDocumentRef document,
    required int expectedRevision,
  }) async {
    final existing = _mcpDocuments[document];
    if (existing == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'MCP document not found',
        retryable: false,
        correlationId: 'demo-mcp-document-not-found',
      );
    }
    if (existing.revision != expectedRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'MCP document revision conflict',
        retryable: true,
        correlationId: 'demo-mcp-document-stale-revision',
      );
    }
    _mcpDocuments.remove(document);
    _bumpDemoMcpCatalogRevision(document.scope);
    final snapshot = _demoMcpCatalog(document.scope);
    _publishProductPayload(McpCatalogChangedPayload(snapshot));
    return McpDocumentCommitReceipt(
      document: null,
      revision: snapshot.revision,
      snapshot: snapshot,
    );
  }

  @override
  Future<ThreadMcpStateSnapshot> readThreadMcp(String threadId) async =>
      _demoThreadMcp(threadId);

  @override
  Future<ThreadMcpStateSnapshot> reconnectThreadMcp({
    required String threadId,
    String? serverId,
  }) async {
    _threadMcpGenerations[threadId] =
        (_threadMcpGenerations[threadId] ?? 1) + 1;
    final snapshot = _demoThreadMcp(threadId);
    _publishProductPayload(ThreadMcpStateChangedPayload(snapshot));
    return snapshot;
  }

  @override
  Future<LspStateSnapshot> readLspState() async => _demoLspState();

  @override
  Future<LspStateSnapshot> probeLspServer(String workspaceId) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> resetLspServer(
    String workspaceId,
    String serverId,
  ) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> resetLspWorkspace(String workspaceId) async {
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
        workspaceId: request.workspaceId,
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
      workspaceId: request.workspaceId,
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
        workspaceId: current.workspaceId,
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
        workspaceId: existing.workspaceId,
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
        workspaceId: existing.workspaceId,
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
        workspaceId: existing.workspaceId,
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
        workspaceId: existing.workspaceId,
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
      workspaceId: _findBot(request.botId)?.workspaceId ?? '',
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

  void _bumpDemoMcpCatalogRevision(McpScope scope) {
    _mcpCatalogRevisions[scope] = (_mcpCatalogRevisions[scope] ?? 1) + 1;
  }

  McpCatalogSnapshot _demoMcpCatalog(McpScope scope) {
    final revision = _mcpCatalogRevisions[scope] ?? 1;
    final entries = <McpCatalogEntry>[];
    for (final entry in _mcpDocuments.entries) {
      if (entry.key.scope != scope) continue;
      final id = entry.value.id;
      final raw = entry.value.rawToml;
      final disabled =
          raw.contains('enabled = false') || raw.contains('kind = "disabled"');
      final builtIn = raw.contains('kind = "builtin"');
      entries.add(
        McpCatalogEntry(
          id: id,
          document: entry.key,
          configStatus: disabled
              ? McpConfigStatusKind.disabled
              : McpConfigStatusKind.enabled,
          effectiveSource: switch (scope) {
            HostMcpScope() =>
              builtIn
                  ? McpEffectiveSource.hostBuiltin
                  : McpEffectiveSource.hostServer,
            SshMcpScope() =>
              raw.contains('kind = "disabled"')
                  ? McpEffectiveSource.sshDisabledTombstone
                  : builtIn
                  ? McpEffectiveSource.sshOverrideBuiltin
                  : McpEffectiveSource.sshOverrideServer,
          },
          executionLocation: switch (scope) {
            HostMcpScope() => const HostLocalMcpExecutionLocation(),
            SshMcpScope(:final sshAlias) => SshRemoteMcpExecutionLocation(
              sshAlias: sshAlias,
            ),
          },
          transport: 'stdio',
          endpointSummary: builtIn ? 'dart mcp-server' : id,
          builtIn: builtIn,
          inheritedFromHost: false,
          overriddenInScope: scope is SshMcpScope,
          canOverrideInSsh: scope is SshMcpScope,
          canDisableInSsh: scope is SshMcpScope && !disabled,
          canRestoreInheritance: scope is SshMcpScope,
        ),
      );
    }
    return McpCatalogSnapshot(
      scope: scope,
      revision: revision,
      entries: entries,
    );
  }

  ThreadMcpStateSnapshot _demoThreadMcp(String threadId) {
    final generation = _threadMcpGenerations[threadId] ?? 1;
    return ThreadMcpStateSnapshot(
      threadId: threadId,
      scope: const HostMcpScope(),
      generation: generation,
      servers: const [
        ThreadMcpServerState(
          id: 'dart',
          effectiveSource: McpEffectiveSource.hostBuiltin,
          executionLocation: HostLocalMcpExecutionLocation(),
          transport: 'stdio',
          endpointSummary: 'dart mcp-server',
          builtIn: true,
          lifecycle: ThreadMcpLifecycleKind.available,
          toolCount: 4,
        ),
      ],
    );
  }

  LspStateSnapshot _lspWriteResult() {
    _lspActivityPercentage = 40;
    final state = _demoLspState();
    _publishProductPayload(LspStateChangedPayload(state));
    return state;
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
              configurationPath: '.anywork/lsp/rust-analyzer.toml',
              phase: 'ready',
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

  void _publishContent(String threadId) {
    _historyOf(threadId).changed(_demoWorkspace(threadId));
    for (final feed in [...?_conversationFeeds[threadId]]) {
      feed._contentChanged();
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
    if (update case ThreadInteractionUpdate(
      :final interaction,
      pending: true,
    )) {
      _freezeDemoPlanRequest(interaction);
    }
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
      ThreadBusinessRefsUpdate(:final references) => workspace.copyWith(
        revision: revision,
        businessRefs: references,
      ),
      ThreadTurnUpdate(:final turn) => workspace.copyWith(
        revision: revision,
        activeTurn: turn.state.isBusy ? turn : null,
      ),
      // 活动与生产一样只从 typed 活动事实进入状态。
      ThreadActivityUpdate(:final activity) => workspace.copyWith(
        revision: revision,
        activity: activity,
      ),
      ThreadRuntimeUpdate(:final runtime, :final todo, :final modelRoute) =>
        workspace.copyWith(
          revision: revision,
          runtime: runtime,
          todo: todo,
          modelRoute: modelRoute,
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
    _historyOf(threadId).changed(updated);
    // 子会话的交互事实变化同时刷新宿主主会话的待决集合投影。
    if (update is ThreadInteractionUpdate) {
      final host = updated.thread.parentThreadId;
      if (host != null) _publishChildInteractionsIfChanged(host);
    }
    if (update case ThreadTurnUpdate(:final turn) when turn.state.isTerminal) {
      _historyOf(threadId).finishDisplayTurn(turn.turnId, switch (turn.state) {
        FailedStudioTurnState() => ChatTerminalOutcome.failed,
        CancelledStudioTurnState() => ChatTerminalOutcome.cancelled,
        _ => ChatTerminalOutcome.completed,
      });
      // Turn receipts are explicit hidden originals, not GUI display blocks.
      _completeDemoItem(
        _demoItem(
          id: 'turn:${turn.turnId.length}:${turn.turnId}',
          threadId: threadId,
          turnId: turn.turnId,
          updatedAt: turn.updatedAt,
          content: _demoTurn(turn.state, inputId: turn.inputId),
        ),
      );
      _retirePendingItems(threadId);
      _workspaces[threadId] = updated.copyWith(activity: null);
      // Completion and Activity are independent deliveries at the same cut;
      // the feed orders completion admission before publishing the live exit.
      _publishContent(threadId);
    }
    final receivers = _conversationStateFeeds[threadId];
    if (receivers != null && receivers.isNotEmpty) {
      for (final feed in receivers.toList()) {
        feed._stateChanged();
      }
    }
    // Activity-facing state facts (execution presence) also wake the content
    // owner's live Activity snapshot, exactly like the former combined feed's
    // pending-current duty; state frames themselves never flow through content.
    if (update is ThreadRuntimeUpdate) {
      for (final feed in [...?_conversationFeeds[threadId]]) {
        feed._contentChanged();
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
          modelRoute: updated.modelRoute,
        ),
      );
    }
    // Business-reference changes are State facts too. Publish the replacement
    // after its originating update, without refreshing Main or re-reading it.
    // Use the latest workspace because the execution update above can reenter.
    if (update is! ThreadBusinessRefsUpdate) {
      final latest = _workspaces[threadId]!;
      final references = _snapshotOf(latest).businessRefs;
      if (references != latest.businessRefs) {
        _emitThreadUpdate(
          threadId,
          ThreadBusinessRefsUpdate(references: references),
        );
      }
    }
  }

  /// Script progress remains private. Each member seals independently and moves
  /// to canonical completion before the feed captures the new live boundary.
  void _upsertChatItem(String threadId, _DemoItem item) {
    if (!_workspaces.containsKey(threadId)) return;
    final pending = _pendingItems.putIfAbsent(threadId, () => {});
    if (item.content.descriptor == null) {
      if (_historyOf(threadId).byId.containsKey(item.id)) {
        throw StateError('Completed Demo member cannot resume streaming');
      }
      _historyOf(threadId).sync(item);
      pending[item.id] = item;
    } else {
      _completeDemoItem(item);
      pending.remove(item.id);
    }
    _publishContent(threadId);
  }

  Iterable<_DemoItem> _pendingItemsOf(String threadId) =>
      _pendingItems[threadId]?.values ?? const <_DemoItem>[];

  void _retirePendingItems(String threadId) {
    final pending = _pendingItems.remove(threadId);
    final history = _historyOf(threadId);
    for (final id in pending?.keys ?? const <String>[]) {
      if (!history.byId.containsKey(id)) {
        if (!history.displayMembership.containsKey(id)) {
          history.bodies.remove(id);
        }
        history.positions.remove(('member', id));
      }
    }
  }

  void _installDemoHistory(String threadId, List<_DemoItem> items) {
    for (final item in items) {
      if (item.threadId != threadId) throw _conversationQueryFailure;
      _completeDemoItem(item);
    }
  }

  void _completeDemoItem(_DemoItem item) {
    final descriptor = item.content.descriptor;
    if (descriptor == null) throw StateError('Demo member has not completed');
    _historyOf(item.threadId).complete(item);
  }

  /// 单字段 append 的便捷入口（demo 脚本只追加正文）。
  void _appendChatContent(
    String threadId, {
    required String itemId,
    required String field,
    required String text,
  }) {
    final item = _pendingItems[threadId]?[itemId];
    if (item == null) throw StateError('No active Demo member $itemId');
    item.content.fields[field] = (item.content.fields[field] ?? '') + text;
    final bodies = _historyOf(threadId).bodies.putIfAbsent(itemId, () => {});
    (bodies[field] ??= _DemoBody()).append(utf8.encode(text));
    _publishContent(threadId);
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
          executionId: _demoExecutionId(turnId),
          inputId: inputId,
          kind: kind,
          summary: summary,
        ),
      ),
    );
  }

  /// Turn 结束或打断：清空当前活动（`activity == null`）。
  void _clearActivity(String threadId) {
    // Generation cancellation ends the script, not each partially produced
    // member. Only individually completed members are eligible for history.
    _retirePendingItems(threadId);
    _emitThreadUpdate(threadId, const ThreadActivityUpdate(activity: null));
  }
}

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

_DemoItem _messageItem({
  required String id,
  required String threadId,
  required String turnId,
  required ThreadTextChannel channel,
  required String text,
  required DateTime createdAt,
  List<ThreadAttachmentView> attachments = const [],
}) => _demoItem(
  id: id,
  threadId: threadId,
  turnId: turnId,
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

  /// 为子任务交互旅程准备真实 demo 工作区；订阅与归档仍走原所有者。
  void prepareChildInteractionScenario() {
    _ensureWorkspaceFixture();
    final child = _workspaces['thread-reviewer']!;
    _workspaces[child.thread.id] = child.copyWith(
      interactions: const [
        PendingInteraction(
          id: 'driver-child-approval',
          threadId: 'thread-reviewer',
          turnId: 'driver-child-turn',
          revision: 1,
          kind: InteractionKind.toolApproval,
          title: 'Review command',
          body: 'Approve the reviewer command.',
          payload: ToolApprovalInteractionPayload(
            toolName: 'exec',
            arguments: {'command': 'git diff --check'},
            workingDirectory: '/demo',
          ),
        ),
      ],
    );
    _publishChildInteractionsIfChanged('thread-main');
  }

  bool _retiredPlannerScenario = false;
  int _fixtureScenarioRevision = 0;
  int _appliedFixtureScenarioRevision = -1;
  String? _themePlanRequestId;

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
      final previousPlanRequestId = _themePlanRequestId;
      if (previousPlanRequestId != null) {
        _demoPlanRequests.remove(previousPlanRequestId);
        _themePlanRequestId = null;
      }
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
            updatedAt: now,
            content: _demoText(
              channel: ThreadTextChannel.commentary,
              text: '连接中断，正在重试（$attempt/5）。',
              attachments: const [],
              lifecycle: CompletedThreadContentView(now),
            ),
          ),
        );
        final displayId = '$turnId:connection-retry-$attempt';
        final display = _historyOf(threadId);
        display.declareDisplay(displayId, [displayId], work: false);
        display.sealDisplay(displayId);
        _publishContent(threadId);
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
    _themeScenario = false;
    _themePlanScenario = false;
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
    _themeScenario = false;
    _themePlanScenario = false;
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

  // Exact SHA-256 of the 613 UTF-8 bytes above, including its trailing newline.
  // Keep the digest synchronized when changing this fixed fixture document.
  static const _themePlanDocument = PlanDocumentView(
    version: 1,
    markdown: _themePlanMarkdown,
    contentHash: 'sha256:30205da061addd1c07201c28d92cd9533f77cb5740c452a478425751f3685f0d',
  );

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
      return workspace.copyWith(
        runtime: workspace.runtime.copyWith(plan: null),
        interactions: const [],
        todo: null,
      );
    }
    const threadId = 'thread-main';
    PendingInteraction? planInteraction;
    PlanRuntimeView? plan;
    if (_themePlanScenario) {
      // A fresh scenario is a new request, not a replay of a retired identity.
      final requestId = 'driver-theme-plan:$_fixtureScenarioRevision';
      const document = _themePlanDocument;
      plan = PlanRuntimeView(
        revision: 1,
        state: PlanRuntimePhase.awaitingConfirmation,
        document: document,
        updatedAt: _fixtureTime,
      );
      planInteraction = PendingInteraction(
        id: requestId,
        threadId: threadId,
        turnId: 'driver-origin-turn',
        revision: 1,
        kind: InteractionKind.userInput,
        title: 'Theme implementation plan',
        body: document.markdown,
        payload: UserInputInteractionPayload(
          questions: [
            UserQuestionView(
              id: agentSessionPlanConfirmationQuestionId,
              header: 'Plan',
              question: document.markdown,
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
      );
      _themePlanRequestId = requestId;
      _freezeDemoPlanRequest(
        planInteraction,
        document: document,
        planRevision: plan.revision,
      );
    }
    final prepared = workspace.copyWith(
      runtime: workspace.runtime.copyWith(plan: plan),
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
      interactions: planInteraction != null
          ? [planInteraction]
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
    // Freeze the marker with the actual scripted request. State seeded by a
    // caller never gains a contract merely because its name or fields match.
    for (final request in prepared.interactions) {
      if (request.kind == InteractionKind.userInput &&
          _demoPlanQuestion(request) == null) {
        _demoUserInputInvocations[request.id] = (
          request,
          _DemoInvocation(
            toolCallId: 'demo-user-input:${request.id}',
            name: 'request_user_input',
            presentationContract: 'builtin.request_user_input@1',
          ),
        );
      }
    }
    return prepared;
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
  String workspaceId,
  int revision, {
  List<String> skills = const [
    'flutter-ui-polish',
    'runtime-review',
    'studio-settings',
  ],
}) {
  return SkillsStateSnapshot.fromState(
    workspaceId: workspaceId,
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
