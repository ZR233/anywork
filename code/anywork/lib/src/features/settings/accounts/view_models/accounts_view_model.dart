import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/coalesced_publish.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../view_models/settings_tab_lifecycle.dart';
import '../state/accounts_state.dart';
import '../state/acp_account_target.dart';
import '../state/acp_command_notice.dart';
import 'account_detail_participant.dart';
import 'account_selectors.dart';
import 'account_usage_checks.dart';
import 'accounts_visible_reads.dart';

part 'accounts_view_model.g.dart';

@Riverpod(keepAlive: true)
class AccountsViewModel extends _$AccountsViewModel {
  late ConfigurationRepository _configuration;

  /// ACP 观察 owner：可选注入。缺少注入或读取失败只记录读问题，不影响 Native 账号路径。
  AcpAuthRepository? _acp;
  late ModelsRepository _models;
  late AccountUsageRepository _usage;
  late AccountsVisibleReads _reads;
  final _observations = <Observation>[];
  final _rowObservations = <(String, AccountRowAction), Observation>{};
  final _modelObservations = <(String, String), Observation>{};
  final _removalObservations = <String, Observation>{};
  AccountUsageChecks? _usageChecks;
  int _lifetime = 0;
  int _editorId = 0;
  bool _alive = true;
  bool _visible = true;
  Set<String> _visibleUsage = const {};
  AccountDetailParticipant? _detail;
  String? _detailAccountId;
  AcpObservationLease<AcpAuthObservation>? _acpLease;
  AcpAccountCatalog? _acpCatalog;
  AcpAccountDirectory? _acpDirectory;

  bool detailRequested(String accountId) =>
      _alive &&
      _visible &&
      state.asData?.value.showDetails == true &&
      state.requireValue.selectedAccountId == accountId &&
      state.requireValue.editor == null;

  void Function() attachDetail(
    String accountId,
    AccountDetailParticipant detail,
  ) {
    if (_detail != null && !identical(_detail, detail)) _detail!.endEditing();
    _detailAccountId = accountId;
    _detail = detail;
    return () {
      if (identical(_detail, detail)) {
        _detail = null;
        _detailAccountId = null;
      }
    };
  }

  void _endDetail() {
    final detail = _detail;
    _detail = null;
    _detailAccountId = null;
    detail?.endEditing();
  }

  @override
  Future<AccountsViewState> build() async {
    _alive = true;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _acp = _resolveAcpRepository();
    _models = ref.watch(modelsRepositoryProvider);
    _usage = ref.watch(accountUsageRepositoryProvider);
    _reads = AccountsVisibleReads(
      _configuration,
      _models,
      _usage,
      (field, error, current, reading) {
        if (!_owns(lifetime)) return;
        final issues = {...state.requireValue.readIssues};
        if (current) {
          if (error == null) {
            issues.remove(field);
          } else {
            issues[field] = error;
          }
        }
        final fields = {...state.requireValue.reading};
        if (reading) {
          fields.add(field);
        } else {
          fields.remove(field);
        }
        state = AsyncData(
          state.requireValue.copyWith(readIssues: issues, reading: fields),
        );
      },
      (templates) {
        if (_owns(lifetime)) {
          state = AsyncData(state.requireValue.copyWith(templates: templates));
        }
      },
    );
    final tab = ref
        .read(settingsNavigationViewModelProvider.notifier)
        .register(
          SettingsTab.accounts,
          SettingsTabLifecycle(visibility: setVisible),
        );
    _visible = tab.visible;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      _releaseAcpLease();
      _reads.dispose();
      _usageChecks?.dispose();
      tab.unregister();
      for (final observation in _observations) {
        observation.cancel();
      }
      _observations.clear();
      for (final observation in [
        ..._rowObservations.values,
        ..._modelObservations.values,
      ]) {
        observation.cancel();
      }
      _rowObservations.clear();
      _modelObservations.clear();
      for (final observation in _removalObservations.values) {
        observation.cancel();
      }
      _removalObservations.clear();
      // Repository, accepted checks and writes outlive their display observer.
    });
    // Sources publish while other providers may still be building; the write is
    // coalesced into one trailing microtask that applies the latest values.
    final sourcePublish = CoalescedPublish(() {
      if (_owns(lifetime)) _publishSources();
    });
    ref.onDispose(sourcePublish.dispose);
    _observations.add(
      _configuration.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _observations.add(
      _models.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _observations.add(
      _models.templates.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _observations.add(
      _usage.state.watchLatest((_) {
        if (_owns(lifetime)) sourcePublish.mark();
      }).observation,
    );
    _usageChecks = AccountUsageChecks(_configuration, _usage, (checks) {
      if (_owns(lifetime)) {
        state = AsyncData(state.requireValue.copyWith(usageChecks: checks));
      }
    });
    final errors = <AccountsReadField, StudioFailure>{};
    AccountTemplatesValue? templates;
    Future<void> read(
      AccountsReadField field,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } on StudioFailure catch (error) {
        errors[field] = error;
      }
    }

    await Future.wait<void>([
      read(AccountsReadField.accounts, () => _configuration.loadAccountsPage()),
      read(AccountsReadField.models, () => _models.loadAccountsPage()),
      read(AccountsReadField.templates, () async {
        templates = await _models.loadTemplates();
      }),
      read(AccountsReadField.defaultAccount, () async {
        await _configuration.loadDefaultAccountId();
      }),
      read(AccountsReadField.usage, () => _usage.loadRecordsPage()),
      read(
        AccountsReadField.configurationSource,
        _configuration.loadSourceStatus,
      ),
      read(AccountsReadField.modelSource, _models.loadSourceStatus),
      read(AccountsReadField.usageSource, _usage.loadSourceStatus),
      // ACP 目录与接入模板是两条独立的有界读取：任一侧失败都如实记录，不互相冒充。
      read(AccountsReadField.acpAccounts, () async {
        final acp = _acp;
        // 组合根未装配 ACP owner 时不发起 ACP 读取（账号页的 Native 路径与它无关）。
        if (acp == null) return;
        StudioFailure? issue;
        try {
          _acpDirectory = await _configuration.loadAcpAccounts();
        } on StudioFailure catch (error) {
          issue = error;
        }
        try {
          _acpCatalog = await acp.readCatalog();
        } on StudioFailure catch (error) {
          issue ??= error;
        }
        if (issue != null) throw issue;
      }),
    ]);
    if (_visible) _acquireAcpLease(lifetime);
    _reads.rememberInitialFailures();
    _usageChecks!.refresh();
    final initialAcpAuth = _acpLease?.latest.value.canonical;
    final initial = _filter(
      AccountsViewState(
        source: _configuration.state.value,
        modelSource: _models.state.value,
        templateSource: _models.templates.value,
        usageSource: _usage.state.value,
        templates: templates,
        acpAccounts: _acpDirectory,
        acpCatalog: _acpCatalog,
        acpAuth: initialAcpAuth,
        directory: _composeDirectory(auth: initialAcpAuth),
        readIssues: errors,
        usageChecks: _usageChecks!.snapshot,
      ),
    );
    Future<void>(() {
      if (_owns(lifetime)) _publish(state.requireValue);
    });
    return initial;
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;

  /// Publishes the latest canonical sources in one write.
  void _publishSources() {
    _publish(
      state.requireValue.copyWith(
        source: _configuration.state.value,
        modelSource: _models.state.value,
        templateSource: _models.templates.value,
        usageSource: _usage.state.value,
      ),
    );
  }

  void _publish(AccountsViewState value) {
    final lifetime = _lifetime;
    state = AsyncData(_filter(_withAcp(value)));
    if (!_owns(lifetime)) return;
    _reads.visible(_visible);
    if (!_owns(lifetime)) return;
    final current = state.requireValue;
    final ids = !_visible || current.editor != null
        ? <String>{}
        : current.showDetails
        ? {?current.selectedAccountId}
        : current.matchingAccountIds.toSet();
    _usageChecks?.visibleAccounts(ids);
    if (!_owns(lifetime)) return;
    final latest = state.requireValue;
    final latestIds = !_visible || latest.editor != null
        ? <String>{}
        : latest.showDetails
        ? {?latest.selectedAccountId}
        : latest.matchingAccountIds.toSet();
    if (ids.length != latestIds.length || !ids.containsAll(latestIds)) return;
    if (ids.length == _visibleUsage.length && ids.containsAll(_visibleUsage)) {
      return;
    }
    _visibleUsage = Set.unmodifiable(ids);
    try {
      _usage.setVisibleAccounts(ids);
    } on StudioFailure catch (error) {
      state = AsyncData(
        state.requireValue.copyWith(
          readIssues: {
            ...state.requireValue.readIssues,
            AccountsReadField.usage: error,
          },
        ),
      );
    }
  }

  AccountsViewState _filter(AccountsViewState value) {
    final query = value.query.trim().toLowerCase();
    final accounts = displayCollectionRows(value.source.accounts);
    final catalogs = displayCollectionRows(value.modelSource.accounts);
    final matching = [
      for (final account in accounts)
        if (query.isEmpty ||
            [
              account.accountId,
              account.name,
              for (final catalog in catalogs.where(
                (item) => item.accountId == account.accountId,
              )) ...[
                catalog.defaultModelId,
                for (final model in catalog.effectiveModels) ...[
                  model.modelId,
                  model.displayName,
                  model.transport.protocol,
                  model.transport.defaultConnectionMode,
                ],
              ],
            ].join(' ').toLowerCase().contains(query))
          account.accountId,
    ];
    final acpEntries =
        value.directory?.acpEntries ?? const <AcpAccountEntryView>[];
    final matchingAcp = [
      for (final entry in acpEntries)
        if (query.isEmpty ||
            [
              entry.account.accountId,
              entry.account.name,
              entry.account.provider.name,
            ].join(' ').toLowerCase().contains(query))
          entry.account.accountId,
    ];
    final complete = collectionComplete(
      value.source.accounts,
      value.source.projection.stamp?.origin,
    );
    final selected = value.selectedAccountId;
    if (selected != null &&
        complete &&
        !accounts.any((item) => item.accountId == selected) &&
        value.editor == null) {
      return value.copyWith(
        matchingAccountIds: matching,
        matchingAcpAccountIds: matchingAcp,
        selectedAccountId: accounts.firstOrNull?.accountId,
        showDetails: false,
      );
    }
    final selectedAcp = value.selectedAcpAccountId;
    final acpMissing =
        selectedAcp != null &&
        value.acpEditor == null &&
        value.directory != null &&
        !acpEntries.any((entry) => entry.account.accountId == selectedAcp);
    if (acpMissing) {
      return value.copyWith(
        matchingAccountIds: matching,
        matchingAcpAccountIds: matchingAcp,
        selectedAcpAccountId: null,
        showDetails: value.selectedAccountId == null
            ? false
            : value.showDetails,
        acpNotices: {...value.acpNotices}..remove(selectedAcp),
      );
    }
    return value.copyWith(
      matchingAccountIds: matching,
      matchingAcpAccountIds: matchingAcp,
    );
  }

  /// ACP 目录素材随任一 canonical 源一起刷新；缺任一侧时不合成空目录冒充事实。
  AccountsViewState _withAcp(AccountsViewState value) => value.copyWith(
    acpAccounts: _acpDirectory ?? value.acpAccounts,
    acpCatalog: _acpCatalog ?? value.acpCatalog,
    directory: _composeDirectory(auth: value.acpAuth),
  );

  AccountDirectoryView? _composeDirectory({required AcpAuthSnapshot? auth}) {
    final acpAccounts = _acpDirectory;
    final catalog = _acpCatalog;
    if (acpAccounts == null || catalog == null) return null;
    final templates = currentTemplatesValue(_models.templates.value);
    return AccountDirectoryView.from(
      acpAccounts: acpAccounts,
      nativeAccounts: displayCollectionRows(
        _configuration.state.value.accounts,
      ),
      nativeTemplates: templates?.templates ?? const [],
      acpCatalog: catalog,
      auth: auth,
    );
  }

  /// 页面可见时的 `acpAuth` 观察租约；离页只释放自身租约，不取消已受理的检查。
  void _acquireAcpLease(int lifetime) {
    if (_acpLease != null) return;
    final acp = _acp;
    if (acp == null) return;
    try {
      _acpLease = acp.observe(
        onState: (observation) {
          if (!_owns(lifetime) || !_visible) return;
          final snapshot = observation.canonical;
          state = AsyncData(
            _filter(
              _withAcp(
                state.requireValue.copyWith(
                  acpAuth: snapshot,
                  directory: _composeDirectory(auth: snapshot),
                ),
              ),
            ),
          );
        },
      );
    } on StudioFailure catch (error) {
      if (state.asData == null) return;
      state = AsyncData(
        state.requireValue.copyWith(
          readIssues: {
            ...state.requireValue.readIssues,
            AccountsReadField.acpAccounts: error,
          },
        ),
      );
      return;
    }
    unawaited(_synchronizeAcp(lifetime));
  }

  Future<void> _synchronizeAcp(int lifetime) async {
    final acp = _acp;
    if (acp == null) return;
    try {
      await acp.synchronize();
    } on StudioFailure catch (error) {
      if (!_owns(lifetime)) return;
      state = AsyncData(
        state.requireValue.copyWith(
          readIssues: {
            ...state.requireValue.readIssues,
            AccountsReadField.acpAccounts: error,
          },
        ),
      );
    }
  }

  /// ACP owner 的可选依赖接缝。
  ///
  /// 正式组合根总会装配它；只有只关注 Native 账号的测试装置会省略。因此这里只把
  /// “未注入”（provider 的 `StateError`）当作 ACP 附加能力缺席，其它错误照常向上抛，
  /// 不被静默吞掉。
  AcpAuthRepository? _resolveAcpRepository() {
    try {
      return ref.read(acpAuthRepositoryProvider);
    } on StateError {
      return null;
    }
  }

  void _releaseAcpLease() {
    _acpLease?.release();
    _acpLease = null;
  }

  void setVisible(bool value) {
    if (!_alive) return;
    if (!value) _detail?.leave();
    _visible = value;
    // ACP 认证观察是独立的可见需求：只在页面可见时持有自己的租约。
    if (value) {
      _acquireAcpLease(_lifetime);
    } else {
      _releaseAcpLease();
    }
    if (value &&
        state.asData?.value.showDetails == true &&
        _detailAccountId == state.requireValue.selectedAccountId) {
      _detail?.setVisible(true);
    }
    if (state.asData != null) _publish(state.requireValue);
  }

  void setQuery(String value) {
    if (_alive) _publish(state.requireValue.copyWith(query: value));
  }

  void select(String id) {
    if (!_alive ||
        !displayCollectionRows(state.requireValue.source.accounts)
            .any((item) => item.accountId == id)) {
      return;
    }
    if (_detailAccountId != id) _endDetail();
    _publish(
      state.requireValue.copyWith(
        selectedAccountId: id,
        selectedAcpAccountId: null,
        acpEditor: null,
        acpNeedsPreparation: false,
        showDetails: true,
        navigationIntent: state.requireValue.navigationIntent + 1,
      ),
    );
  }

  void showList() {
    if (!_alive) return;
    _endDetail();
    _publish(
      state.requireValue.copyWith(
        showDetails: false,
        selectedAcpAccountId: null,
        acpEditor: null,
        acpNeedsPreparation: false,
        navigationIntent: state.requireValue.navigationIntent + 1,
      ),
    );
  }

  /// 选择一条已保存的 ACP 接入进入详情；与 Native 选择互斥。
  void selectAcp(String accountId) {
    if (!_alive) return;
    final entries =
        state.requireValue.directory?.acpEntries ??
        const <AcpAccountEntryView>[];
    if (!entries.any((entry) => entry.account.accountId == accountId)) return;
    _endDetail();
    _publish(
      state.requireValue.copyWith(
        selectedAcpAccountId: accountId,
        selectedAccountId: null,
        acpEditor: null,
        acpNeedsPreparation: false,
        showDetails: true,
        navigationIntent: state.requireValue.navigationIntent + 1,
      ),
    );
  }

  /// 打开已保存接入的编辑表单。
  ///
  /// 模板必须来自后端目录：解析不到时返回 null，由调用方报告模板不可用，不在这里合成
  /// 受管版本或安装资格。
  AcpAccountEditorTarget? startAcpEdit(AcpAccountSettings account) {
    if (!_alive || state.requireValue.editor != null) return null;
    final template = state.requireValue.directory?.acpEntries
        .where((entry) => entry.account.accountId == account.accountId)
        .firstOrNull
        ?.template;
    if (template == null) return null;
    final target = AcpAccountEditTarget(account: account, template: template);
    _publish(
      state.requireValue.copyWith(
        acpEditor: target,
        selectedAcpAccountId: account.accountId,
        selectedAccountId: null,
        showDetails: false,
        acpNeedsPreparation: _needsPreparation(account.accountId),
        editorError: null,
        navigationIntent: state.requireValue.navigationIntent + 1,
      ),
    );
    return target;
  }

  void closeAcpEditor({String? savedAccountId}) {
    if (!_alive) return;
    _publish(
      state.requireValue.copyWith(
        acpEditor: null,
        acpNeedsPreparation: false,
        selectedAcpAccountId: savedAccountId,
        selectedAccountId: null,
        showDetails: savedAccountId != null,
        navigationIntent: state.requireValue.navigationIntent + 1,
      ),
    );
  }

  /// 该接入的 canonical 认证回执是否明确“需要准备/安装不合格”：只看 typed 失败码。
  bool _needsPreparation(String accountId) {
    final entry = state.requireValue.directory?.acpEntries
        .where((value) => value.account.accountId == accountId)
        .firstOrNull;
    final auth = entry?.auth;
    if (auth is! AcpAuthFailed) return false;
    return auth.failure.code == AcpAuthFailureCode.preparationRequired ||
        auth.failure.code == AcpAuthFailureCode.installationInvalid;
  }

  /// 命令失败通知按目标接入记账：只影响该行/该详情，不跨账号串位。
  void setAcpNotice(String accountId, AcpCommandNotice notice) {
    if (!_alive || state.asData == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        acpNotices: {...state.requireValue.acpNotices, accountId: notice},
      ),
    );
  }

  void clearAcpNotice(String accountId) {
    if (!_alive || state.asData == null) return;
    if (!state.requireValue.acpNotices.containsKey(accountId)) return;
    state = AsyncData(
      state.requireValue.copyWith(
        acpNotices: {...state.requireValue.acpNotices}..remove(accountId),
      ),
    );
  }

  /// 保存 ACP 接入后重新读取 canonical 目录并发布；返回该账号的已保存身份。
  ///
  /// 只做一次有界读取：配置写入已由保存编排结算，这里用于让列表/详情看到新事实，而不是
  /// 反向证明保存成功。
  Future<AcpAccountSettings?> refreshAcpAccounts(String accountId) async {
    if (!_alive || state.asData == null) return null;
    // 未装配 ACP owner 的装置里不存在 ACP 账号，也就没有可刷新的事实。
    if (_acp == null) return null;
    final lifetime = _lifetime;
    try {
      _acpDirectory = await _configuration.loadAcpAccounts();
    } on StudioFailure catch (error) {
      if (_owns(lifetime)) {
        state = AsyncData(
          state.requireValue.copyWith(
            readIssues: {
              ...state.requireValue.readIssues,
              AccountsReadField.acpAccounts: error,
            },
          ),
        );
      }
      return null;
    }
    if (!_owns(lifetime)) return null;
    _publish(state.requireValue);
    return state.requireValue.directory?.acpEntries
        .where((entry) => entry.account.accountId == accountId)
        .firstOrNull
        ?.account;
  }

  /// 删除一条 ACP 接入：不注销官方账号、不删除凭据、也不取消共享安装。
  Future<void> removeAcp(String accountId) async {
    if (!_alive ||
        (state.requireValue.acpRemovals[accountId]?.preventsResubmission ??
            false)) {
      return;
    }
    final entry = state.requireValue.directory?.acpEntries
        .where((value) => value.account.accountId == accountId)
        .firstOrNull;
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        acpRemovals: {
          ...state.requireValue.acpRemovals,
          accountId: SettingsAction(intent: intent, pending: true),
        },
        acpNotices: {...state.requireValue.acpNotices}..remove(accountId),
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.acpRemovals[accountId]?.intent == intent;
    void update(SettingsAction action) {
      if (!owns()) return;
      state = AsyncData(
        state.requireValue.copyWith(
          acpRemovals: {...state.requireValue.acpRemovals, accountId: action},
        ),
      );
    }

    OperationTicket<Unit> ticket;
    try {
      ticket = _configuration.removeAcpAccount(accountId);
    } on StudioFailure catch (error) {
      update(
        SettingsAction(
          intent: intent,
          outcome: SettingsActionOutcome.rejected,
          error: error,
        ),
      );
      _acpRemovalNotice(accountId, entry, error);
      return;
    }
    StudioFailure? observationError;
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (!owns()) return;
          update(
            state.requireValue.acpRemovals[accountId]!.copyWith(
              operation: operation,
            ),
          );
        });
        if (owns()) {
          _removalObservations[accountId]?.cancel();
          _removalObservations[accountId] = watch.observation;
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
    }
    final result = await ticket.result;
    if (!owns()) return;
    final action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    update(action);
    final error = action.error;
    if (error != null) {
      _acpRemovalNotice(accountId, entry, error);
      return;
    }
    // 删除已结算：canonical 目录必须重新读取，列表不得继续显示已删除的接入。
    // 只重新读 Settings 快照，不注销官方账号、不删除凭据，也不取消共享安装。
    await refreshAcpAccounts(accountId);
    if (state.asData == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        acpRemovals: {...state.requireValue.acpRemovals}..remove(accountId),
        selectedAcpAccountId:
            state.requireValue.selectedAcpAccountId == accountId
            ? null
            : state.requireValue.selectedAcpAccountId,
        showDetails: state.requireValue.selectedAcpAccountId == accountId
            ? false
            : state.requireValue.showDetails,
        acpNotices: {...state.requireValue.acpNotices}..remove(accountId),
      ),
    );
  }

  void _acpRemovalNotice(
    String accountId,
    AcpAccountEntryView? entry,
    StudioFailure error,
  ) {
    if (!_alive || state.asData == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        acpNotices: {
          ...state.requireValue.acpNotices,
          accountId: AcpCommandNotice(
            kind: AcpCommandNoticeKind.remove,
            accountId: accountId,
            connectionRevision: entry?.account.connectionRevision ?? -1,
            failure: error,
          ),
        },
      ),
    );
  }

  void retryRead() {
    if (!_alive || !_visible) return;
    _usageChecks?.refresh(retryObservations: true);
    _reads.retry();
    // A failed initial open has no origin/ref for a demand key. Explicit retry
    // can bootstrap that source without invalidating an editor's raw state.
    if (_configuration.state.value.projection.header?.reference == null) {
      unawaited(
        _page(
          AccountsReadField.accounts,
          () => _configuration.loadAccountsPage(),
        ),
      );
      unawaited(
        _page(AccountsReadField.defaultAccount, () async {
          await _configuration.loadDefaultAccountId();
        }),
      );
      unawaited(
        _page(
          AccountsReadField.configurationSource,
          _configuration.loadSourceStatus,
        ),
      );
    }
    if (_models.state.value.projection.header?.reference == null) {
      unawaited(
        _page(AccountsReadField.models, () => _models.loadAccountsPage()),
      );
      unawaited(_page(AccountsReadField.modelSource, _models.loadSourceStatus));
    }
    if (_models.templates.value.projection.header == null) {
      unawaited(
        _page(AccountsReadField.templates, () async {
          final lifetime = _lifetime;
          final templates = await _models.loadTemplates();
          if (_owns(lifetime)) {
            state = AsyncData(
              state.requireValue.copyWith(templates: templates),
            );
          }
        }),
      );
    }
    if (_usage.state.value.projection.header?.reference == null) {
      unawaited(_page(AccountsReadField.usage, () => _usage.loadRecordsPage()));
      unawaited(_page(AccountsReadField.usageSource, _usage.loadSourceStatus));
    }
    // ACP 目录与接入模板是独立的具名读取：失败后由显式重试重新取一次。
    final acp = _acp;
    if (acp != null &&
        (_acpDirectory == null ||
            _acpCatalog == null ||
            state.requireValue.readIssues.containsKey(
              AccountsReadField.acpAccounts,
            ))) {
      unawaited(
        _page(AccountsReadField.acpAccounts, () async {
          _acpCatalog ??= await acp.readCatalog();
          _acpDirectory = await _configuration.loadAcpAccounts();
        }),
      );
    }
  }

  Future<void> loadMore() async {
    if (!_alive || !_visible) return;
    await Future.wait<void>([
      _page(
        AccountsReadField.accounts,
        () => _configuration.loadAccountsPage(),
      ),
      _page(AccountsReadField.models, () => _models.loadAccountsPage()),
      _page(AccountsReadField.usage, () => _usage.loadRecordsPage()),
    ]);
  }

  Future<void> _page(
    AccountsReadField field,
    Future<void> Function() read,
  ) async {
    final lifetime = _lifetime;
    if (state.requireValue.reading.contains(field)) return;
    state = AsyncData(
      state.requireValue.copyWith(
        reading: {...state.requireValue.reading, field},
      ),
    );
    StudioFailure? issue;
    try {
      await read();
    } on StudioFailure catch (error) {
      issue = error;
    }
    if (!_owns(lifetime)) return;
    final errors = {...state.requireValue.readIssues};
    if (issue == null) {
      errors.remove(field);
    } else {
      errors[field] = issue;
    }
    _publish(
      state.requireValue.copyWith(
        reading: {...state.requireValue.reading}..remove(field),
        readIssues: errors,
      ),
    );
  }

  /// 从统一“添加账号”入口按 typed 分支创建草稿。
  ///
  /// Native 模型账号进入既有编辑器；ACP 接入进入只含显示名的编辑表单，账号 ID 由
  /// Native+ACP 已占用身份集合推出，保存前不会写入任何账号。
  Future<void> startCreate(AccountTemplateChoice choice) async {
    if (!_alive || state.requireValue.editor != null) return;
    _endDetail();
    final lifetime = _lifetime;
    final navigation = state.requireValue.navigationIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        navigationIntent: navigation,
        editorError: null,
      ),
    );
    if (choice is AcpAccountTemplateChoice) {
      final ids = {
        for (final account in displayCollectionRows(
          _configuration.state.value.accounts,
        ))
          account.accountId,
        for (final entry
            in state.requireValue.directory?.acpEntries ??
                const <AcpAccountEntryView>[])
          entry.account.accountId,
      };
      var id = choice.template.provider.name;
      for (var index = 2; ids.contains(id); index++) {
        id = '${choice.template.provider.name}-$index';
      }
      _publish(
        state.requireValue.copyWith(
          acpEditor: AcpAccountCreateTarget(
            accountId: id,
            template: choice.template,
          ),
          selectedAcpAccountId: id,
          selectedAccountId: null,
          acpNeedsPreparation: false,
          showDetails: false,
        ),
      );
      return;
    }
    if (choice is! NativeAccountTemplateChoice) return;
    final nativeChoice = choice;
    // A stable human-readable ID is based on the complete current account set,
    // not the visible page. Each await explicitly asks for one bounded page.
    try {
      while (!collectionComplete(
        _configuration.state.value.accounts,
        _configuration.state.value.projection.stamp?.origin,
      )) {
        await _configuration.loadAccountsPage();
        if (!_owns(lifetime) ||
            state.requireValue.navigationIntent != navigation) {
          return;
        }
      }
      final templates =
          state.requireValue.templates ?? await _models.loadTemplates();
      if (!_owns(lifetime) ||
          state.requireValue.navigationIntent != navigation) {
        return;
      }
      final template = templates.templates
          .where((value) => value.id == nativeChoice.template.id)
          .firstOrNull;
      if (template == null) {
        throw _failure(
          StudioFailureCode.notFound,
          'The chosen account template is unavailable.',
        );
      }
      final ids = displayCollectionRows(_configuration.state.value.accounts)
          .map((item) => item.accountId)
          .toSet();
      var id = template.id;
      for (var index = 2; ids.contains(id); index++) {
        id = '${template.id}-$index';
      }
      _publish(
        state.requireValue.copyWith(
          templates: templates,
          editorAccountId: id,
          editor: AccountEditorKey(
            editorId: ++_editorId,
            initialTemplateId: template.id,
          ),
          acpEditor: null,
          selectedAcpAccountId: null,
          showDetails: false,
        ),
      );
    } on StudioFailure catch (error) {
      if (_owns(lifetime) &&
          state.requireValue.navigationIntent == navigation) {
        state = AsyncData(state.requireValue.copyWith(editorError: error));
      }
    }
  }

  void startEdit(String id) {
    if (!_alive || state.requireValue.editor != null) return;
    _endDetail();
    _publish(
      state.requireValue.copyWith(
        selectedAccountId: id,
        selectedAcpAccountId: null,
        acpEditor: null,
        acpNeedsPreparation: false,
        editorAccountId: id,
        showDetails: false,
        navigationIntent: state.requireValue.navigationIntent + 1,
        editorError: null,
        editor: AccountEditorKey(editorId: ++_editorId, accountId: id),
      ),
    );
  }

  String accountIdForEditor(AccountEditorKey key) {
    final value = state.requireValue;
    if (value.editor != key || value.editorAccountId == null) {
      throw _failure(
        StudioFailureCode.superseded,
        'Account editor no longer owns this target.',
      );
    }
    return value.editorAccountId!;
  }

  void closeEditor(AccountEditorKey key, {bool saved = false}) {
    if (!_alive || state.requireValue.editor != key) return;
    _publish(
      state.requireValue.copyWith(
        editor: null,
        editorAccountId: null,
        showDetails: false,
        selectedAccountId: saved
            ? state.requireValue.editorAccountId
            : state.requireValue.selectedAccountId,
        navigationIntent: state.requireValue.navigationIntent + 1,
      ),
    );
  }

  Future<void> setDefault(String id) => _row(
    id,
    AccountRowAction.setDefault,
    () => _configuration.setDefaultAccount(id),
  );

  Future<void> remove(String id) async {
    if (!_alive ||
        state.requireValue.preparingRemovalIds.contains(id) ||
        (state
                .requireValue
                .rowActions[(id, AccountRowAction.remove)]
                ?.preventsResubmission ??
            false)) {
      return;
    }
    final lifetime = _lifetime;
    state = AsyncData(
      state.requireValue.copyWith(
        preparingRemovalIds: {...state.requireValue.preparingRemovalIds, id},
      ),
    );
    try {
      var source = _configuration.state.value;
      if (!isCurrentRead(
        source.defaultAccountId,
        source.projection.header?.reference,
        source.projection.stamp?.origin,
      )) {
        await _configuration.loadDefaultAccountId();
        if (!_owns(lifetime)) return;
        source = _configuration.state.value;
      }
      var defaultId = displayReadValue<String?, ConfigurationReadRef>(
        source.defaultAccountId,
      );
      var replacement = defaultId == id
          ? displayCollectionRows(source.accounts)
                .where((item) => item.accountId != id)
                .firstOrNull
                ?.accountId
          : defaultId;
      if (defaultId == id && replacement == null) {
        await _configuration.loadAccountsPage();
        if (!_owns(lifetime)) return;
        source = _configuration.state.value;
        if (!isCurrentRead(
          source.defaultAccountId,
          source.projection.header?.reference,
          source.projection.stamp?.origin,
        )) {
          throw _failure(
            StudioFailureCode.superseded,
            'Default account changed while choosing a replacement.',
          );
        }
        defaultId = displayReadValue<String?, ConfigurationReadRef>(
          source.defaultAccountId,
        );
        replacement = defaultId == id
            ? displayCollectionRows(source.accounts)
                  .where((item) => item.accountId != id)
                  .firstOrNull
                  ?.accountId
            : defaultId;
      }
      final current = source.accounts;
      if (current is! CurrentCollectionMirror<AccountConfiguration> ||
          current.window.reference.total <= 1) {
        return;
      }
      if (defaultId == id && replacement == null) {
        throw _failure(
          StudioFailureCode.unavailable,
          'A replacement account has not been materialized.',
        );
      }
      await _row(
        id,
        AccountRowAction.remove,
        () =>
            _configuration.removeAccount(id, replacementAccountId: replacement),
      );
    } on StudioFailure catch (error) {
      if (_owns(lifetime)) {
        state = AsyncData(
          state.requireValue.copyWith(
            readIssues: {
              ...state.requireValue.readIssues,
              AccountsReadField.accounts: error,
            },
          ),
        );
      }
    } finally {
      if (_owns(lifetime)) {
        state = AsyncData(
          state.requireValue.copyWith(
            preparingRemovalIds: {...state.requireValue.preparingRemovalIds}
              ..remove(id),
          ),
        );
      }
    }
  }

  Future<void> _row(
    String id,
    AccountRowAction field,
    OperationTicket<Unit> Function() admit,
  ) async {
    if (!_alive ||
        (state.requireValue.rowActions[(id, field)]?.preventsResubmission ??
            false)) {
      return;
    }
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        rowActions: {
          ...state.requireValue.rowActions,
          (id, field): SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.rowActions[(id, field)]?.intent == intent;
    void update(SettingsAction action) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            rowActions: {...state.requireValue.rowActions, (id, field): action},
          ),
        );
      }
    }

    _rowObservations.remove((id, field))?.cancel();
    await _run<Unit>(
      admit,
      intent,
      owns,
      update,
      (observation) => _rowObservations[(id, field)] = observation,
    );
  }

  Future<void> removeModel(String accountId, String modelId) async {
    if (!_alive) return;
    final catalog = currentCollectionRow(
      _models.state.value.accounts,
      _models.state.value.projection.stamp?.origin,
      (item) => item.accountId == accountId,
    )?.value;
    if (catalog == null ||
        !catalog.effectiveModels.any(
          (model) =>
              model.modelId == modelId && model.origin == ModelOrigin.manual,
        )) {
      return;
    }
    final key = (accountId, modelId);
    if (state.requireValue.modelActions[key]?.preventsResubmission ?? false) {
      return;
    }
    final lifetime = _lifetime;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        modelActions: {
          ...state.requireValue.modelActions,
          key: SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.modelActions[key]?.intent == intent;
    _modelObservations.remove(key)?.cancel();
    await _run<Unit>(
      () => _configuration.removeAccountModel(accountId, modelId),
      intent,
      owns,
      (action) {
        if (owns()) {
          state = AsyncData(
            state.requireValue.copyWith(
              modelActions: {...state.requireValue.modelActions, key: action},
            ),
          );
        }
      },
      (observation) => _modelObservations[key] = observation,
    );
  }

  Future<void> refreshUsage([String? accountId]) async {
    if (!_alive) return;
    if (accountId != null) {
      await _check(accountId);
      return;
    }
    if (state.requireValue.refreshingAll) return;
    final lifetime = _lifetime;
    state = AsyncData(state.requireValue.copyWith(refreshingAll: true));
    try {
      while (!collectionComplete(
        _configuration.state.value.accounts,
        _configuration.state.value.projection.stamp?.origin,
      )) {
        await _configuration.loadAccountsPage();
        if (!_owns(lifetime)) return;
      }
      final ids = displayCollectionRows(_configuration.state.value.accounts)
          .map((item) => item.accountId)
          .toList();
      await Future.wait<void>([for (final id in ids) _check(id)]);
    } on StudioFailure catch (error) {
      if (_owns(lifetime)) {
        state = AsyncData(
          state.requireValue.copyWith(
            readIssues: {
              ...state.requireValue.readIssues,
              AccountsReadField.accounts: error,
            },
          ),
        );
      }
    } finally {
      if (_owns(lifetime)) {
        state = AsyncData(state.requireValue.copyWith(refreshingAll: false));
      }
    }
  }

  Future<void> _check(String id) async {
    if (!_alive || (state.requireValue.usageActions[id]?.pending ?? false)) {
      return;
    }
    final lifetime = _lifetime;
    final usage = _usage;
    final intent = state.requireValue.latestIntent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        usageActions: {
          ...state.requireValue.usageActions,
          id: SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _owns(lifetime) &&
        state.requireValue.usageActions[id]?.intent == intent;
    if (!owns()) return;
    OperationTicket<AccountUsageRecord> ticket;
    try {
      ticket = usage.check(id);
    } on StudioFailure catch (error) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            usageActions: {
              ...state.requireValue.usageActions,
              id: SettingsAction(
                intent: intent,
                outcome: SettingsActionOutcome.rejected,
                error: error,
              ),
            },
            usageActionIds: {...state.requireValue.usageActionIds}..remove(id),
          ),
        );
      }
      return;
    }
    if (owns()) {
      state = AsyncData(
        state.requireValue.copyWith(
          usageActionIds: {
            ...state.requireValue.usageActionIds,
            id: ticket.state.value.id,
          },
          usageActions: {
            ...state.requireValue.usageActions,
            id: SettingsAction(
              intent: intent,
              pending: true,
              operation: ticket.state.value,
            ),
          },
        ),
      );
      // The checks projection owns the one observer for this ticket, including
      // an automatic check that manual refresh joined. No second subscription.
      _usageChecks?.refresh();
    }
    final result = await ticket.result;
    if (!owns()) return;
    state = AsyncData(
      state.requireValue.copyWith(
        usageActions: {
          ...state.requireValue.usageActions,
          id: settledSettingsAction(
            intent,
            result,
            operation: ticket.state.value,
          ),
        },
      ),
    );
    _usageChecks?.refresh();
  }

  Future<void> _run<T>(
    OperationTicket<T> Function() admit,
    int intent,
    bool Function() owns,
    void Function(SettingsAction) update,
    void Function(Observation) retain,
  ) async {
    OperationTicket<T> ticket;
    try {
      ticket = admit();
    } on StudioFailure catch (error) {
      update(
        SettingsAction(
          intent: intent,
          outcome: SettingsActionOutcome.rejected,
          error: error,
        ),
      );
      return;
    }
    StudioFailure? observationError;
    var action = SettingsAction(
      intent: intent,
      pending: true,
      operation: ticket.state.value,
    );
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) {
            action = action.copyWith(operation: operation);
            update(action);
          }
        });
        if (owns()) {
          retain(watch.observation);
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
      action = action.copyWith(
        operation: ticket.state.value,
        observationError: observationError,
      );
      update(action);
    }
    final result = await ticket.result;
    if (!owns()) return;
    action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    update(action);
    _publish(state.requireValue);
  }

  static StudioFailure _failure(StudioFailureCode code, String message) =>
      StudioFailure(
        code: code,
        message: message,
        retryable: true,
        correlationId: 'settings-accounts',
      );
}
