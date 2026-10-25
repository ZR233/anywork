import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/account_usage_queries.dart';
import '../../presentation/providers/acp_install_store.dart';

import 'package:anywork_client/studio_client.dart';

import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_account_details.dart';
import 'settings_account_draft_save.dart';
import 'settings_account_drafts.dart';
import 'settings_account_editor.dart';
import 'settings_account_editor_draft.dart';
import 'settings_account_list.dart';
import 'settings_account_template_picker.dart';
import 'settings_account_usage_demand.dart';
import 'settings_acp_failure_labels.dart';
import 'settings_acp_account_details.dart';
import 'settings_acp_account_draft.dart';
import 'settings_acp_account_editor.dart';
import 'settings_scope.dart';
import 'settings_views.dart';

class AccountsTab extends ConsumerStatefulWidget {
  const AccountsTab({super.key, required this.tabIndex});

  /// Tab visibility controls display observation; Client retains its topic owner.
  final int tabIndex;

  @override
  ConsumerState<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends ConsumerState<AccountsTab> {
  String _query = '';
  String? _selectedAccountId;

  /// 当前选中的 ACP 接入身份；与 Native 选择互斥，避免两套详情同时可见。
  String? _selectedAcpId;
  AccountEditorDraft? _draft;
  GlobalKey<FormState> _draftFormKey = GlobalKey<FormState>();
  bool _showDetails = false;
  String? _draftError;

  /// ACP 认证命令层的就地失败说明与在途标志（业务状态仍只来自 canonical）。
  /// 命令层就地失败通知：按**目标 accountId** 记账，并绑定连接身份与在途操作。
  ///
  /// 列表里的删除失败只出现在目标行/目标详情，不会挂到另一个被选中的账号上；
  /// 后续 canonical 进展或终态会取代旧拒绝。
  final Map<String, AcpCommandNotice> _acpNotices = {};

  /// start/check/login 在途：只挡新的 start，不挡取消。
  bool _authBusy = false;

  /// 正在取消的接入（按 accountId）：宽窗切换账号时只让对应详情忙，不误锁其它账号。
  final Set<String> _cancelPending = <String>{};

  /// 准备命令在途：只挡新的 start，不挡取消（取消走独立 lane）。
  bool _preparePending = false;

  /// 当前 ACP 草稿（非 ACP 编辑态时为 null）。
  AcpAccountDraft? get _acpDraftOrNull {
    final editor = _draft;
    return editor is AcpAccountEditorDraft ? editor.draft : null;
  }

  /// 准备取消在途：只锁当前准备面板的取消按钮。

  final AccountDraftSaveSession _saveSession = AccountDraftSaveSession();

  /// 取消的本地观察：按表单/operation 记账，旧回执不污染新草稿。
  final AccountDraftCancelSession _installCancelSession =
      AccountDraftCancelSession();
  final AccountUsageAutoDemand _usageDemand = AccountUsageAutoDemand();
  ProviderSubscription<bool>? _visibilitySubscription;
  ProviderSubscription<AccountUsageQueryIdentitySnapshot>?
  _identitySubscription;
  late final AnyworkClient _client;

  /// 准备协调器：拥有尝试序号、在途门控与回填判断，直接调用 Client 动作。
  late final AcpPreparationCoordinator _preparation;

  final Map<(String, String), _AutoCompactIntent> _compactIntents = {};
  bool _disposing = false;

  SettingsAccountsView get _settings => ref.read(settingsAccountsViewProvider);

  bool get _visible => ref.read(settingsVisibleTabProvider) == widget.tabIndex;

  @override
  void initState() {
    super.initState();
    _client = ref.read(anyworkClientProvider);
    _preparation = AcpPreparationCoordinator(
      commands: _client.acpInstallCommands,
    );
    _visibilitySubscription = ref.listenManual<bool>(
      settingsVisibleTabProvider.select((index) => index == widget.tabIndex),
      (previous, next) {
        if (!next) _flushCompactIntents();
        _scheduleUsageDemand();
      },
      fireImmediately: true,
    );
    _identitySubscription = ref.listenManual<AccountUsageQueryIdentitySnapshot>(
      settingsAccountUsageQueryIdentitiesProvider,
      (previous, next) => _scheduleUsageDemand(),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _disposing = true;
    _flushCompactIntents();
    _visibilitySubscription?.close();
    _identitySubscription?.close();
    super.dispose();
  }

  void _changeCompact(String accountId, String modelId, int? value) {
    final key = (accountId, modelId);
    final current = _compactIntents[key];
    if (current != null && current.value == value && !current.failed) return;
    _compactIntents[key]?.timer?.cancel();
    final intent = _AutoCompactIntent(value);
    setState(() => _compactIntents[key] = intent);
    intent.timer = Timer(
      const Duration(milliseconds: 650),
      () => _submitCompact(key, intent),
    );
  }

  void _invalidateCompact(String accountId, String modelId) {
    final key = (accountId, modelId);
    final intent = _compactIntents.remove(key);
    intent?.timer?.cancel();
    if (intent != null) setState(() {});
  }

  void _commitCompact(String accountId, String modelId) {
    final key = (accountId, modelId);
    final intent = _compactIntents[key];
    if (intent == null) return;
    if (intent.failed) {
      final retry = _AutoCompactIntent(intent.value);
      setState(() => _compactIntents[key] = retry);
      _submitCompact(key, retry);
    } else if (!intent.submitted) {
      _submitCompact(key, intent);
    }
  }

  void _flushCompactIntents() {
    for (final entry in _compactIntents.entries.toList()) {
      if (!entry.value.submitted && !entry.value.failed) {
        _submitCompact(entry.key, entry.value);
      }
    }
  }

  void _submitCompact((String, String) key, _AutoCompactIntent intent) {
    if (intent.submitted) return;
    intent.timer?.cancel();
    intent.timer = null;
    intent.submitted = true;
    // Client owns the queued command and joins it even after this page leaves.
    unawaited(
      _client.settingsCommands
          .setModelAutoCompactLimit(key.$1, key.$2, intent.value)
          .then<void>(
            (_) {
              if (_disposing ||
                  !mounted ||
                  !identical(_compactIntents[key], intent)) {
                return;
              }
              setState(() => _compactIntents.remove(key));
            },
            onError: (Object error, StackTrace stack) {
              if (_disposing ||
                  !mounted ||
                  !identical(_compactIntents[key], intent)) {
                return;
              }
              setState(() => intent.failed = true);
            },
          ),
    );
  }

  void _scheduleUsageDemand() {
    scheduleMicrotask(_syncUsageDemand);
  }

  void _syncUsageDemand() {
    if (!mounted) return;
    final queries = ref.read(anyworkClientProvider).accountUsageQueries;
    _usageDemand.apply(
      visible: _visible,
      accounts: ref
          .read(settingsAccountUsageQueryIdentitiesProvider)
          .identities,
      refresh: (accountId) =>
          ignoreAccountUsageQueryErrors(queries.refresh(accountId)),
    );
  }

  @override
  void didUpdateWidget(covariant AccountsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedAccountId;
    if (selected != null &&
        !_settings.accounts.any((account) => account.id == selected)) {
      _selectedAccountId = _settings.accounts.firstOrNull?.id;
      _showDetails = false;
    }
    final selectedAcp = _selectedAcpId;
    if (selectedAcp != null &&
        !ref
            .read(settingsAccountDirectoryProvider)
            .acpEntries
            .any((entry) => entry.id == selectedAcp)) {
      _selectedAcpId = null;
      _acpNotices.remove(selectedAcp);
      if (_selectedAccountId == null) _showDetails = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Visibility only drives display observation; Client retains the topic.
    final visible = ref.watch(settingsVisibleTabProvider) == widget.tabIndex;
    watchSettingsScope(
      ref,
      visible: visible,
      kind: BridgeSettingsScopeKind.usage,
    );
    // ACP 认证观察是独立的可见需求：进入页面只租用观察，不启动检查。
    watchSettingsScope(
      ref,
      visible: visible,
      kind: BridgeSettingsScopeKind.acp,
    );
    final settings = ref.watch(settingsAccountsViewProvider);
    final directory = ref.watch(settingsAccountDirectoryProvider);
    final defaultAccountId = settings.defaultAccountId;
    final draft = _draft;
    if (draft is NativeAccountEditorDraft) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: AccountEditor(
              key: ValueKey((
                draft.draft.mode,
                draft.draft.originalId,
                draft.draft.account.templateId,
              )),
              formKey: _draftFormKey,
              draft: draft.draft,
              templates: settings.accountCatalog.templates,
              saving: _saveSession.isSaving,
              error: _draftError,
              onCancel: () => setState(() {
                _saveSession.abandon();
                _draft = null;
                _draftError = null;
              }),
              onSave: _saveDraft,
              onChangeTemplate: _changeDraftTemplate,
              onUpdate: _updateDraft,
              onAddCustomModel: _addCustomModel,
              onUpdateCustomModel: _updateCustomModel,
              onRemoveCustomModel: _removeCustomModel,
            ),
          ),
        ),
      );
    }
    if (draft is AcpAccountEditorDraft) {
      // 准备状态只读 canonical `acpInstall`：本草稿只承认自己认领的 operation。
      final installSnapshot = ref.watch(acpInstallStateProvider).value;
      final provider = draft.draft.template.provider;
      final installState =
          installSnapshot?.stateOf(provider) ?? const AcpInstallIdleState();
      final prepared = draft.draft.intent.resolve(
        installState,
        provider: provider,
      );
      final availableElsewhere = draft.draft.intent.availableElsewhere(
        installState,
        provider: provider,
      );
      // 已有账号缺安装时也要有**显式准备动作**：只认 typed 失败码，不按文案猜。
      final needsPreparation =
          !draft.draft.isCreate &&
          switch (_acpEntryOf(directory, draft.draft.accountId)?.auth) {
            final AcpFailedState failed =>
              failed.failure.code ==
                      AcpAuthFailureCodeView.preparationRequired ||
                  failed.failure.code ==
                      AcpAuthFailureCodeView.installationInvalid,
            _ => false,
          };
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: AcpAccountEditor(
              key: ValueKey(('acp', draft.draft.accountId, draft.draft.formId)),
              formKey: _draftFormKey,
              draft: draft.draft,
              installState: installState,
              prepared: prepared,
              availableElsewhere: availableElsewhere,
              needsPreparation: needsPreparation,
              saving: _saveSession.isSaving,
              preparePending: _preparePending,
              admissionPending:
                  _preparePending && installState.operationId == null,
              cancelPending:
                  installState.operationId != null &&
                  _installCancelSession.isPending(
                    formId: draft.draft.formId,
                    provider: provider,
                    operationId: installState.operationId!,
                  ),
              error: _draftError,
              onCancel: () => setState(() {
                _saveSession.abandon();
                _draft = null;
                _draftError = null;
              }),
              onSave: _saveAcpDraft,
              onPrepare: _prepareAcpDraft,
              onCancelPrepare: _cancelAcpInstall,
              onUsePrepared: () => _usePreparedAcp(installState),
              onUpdate: _updateAcpDraft,
            ),
          ),
        ),
      );
    }

    final selectedAcp = _selectedAcpId == null
        ? null
        : directory.acpEntries
              .where((entry) => entry.id == _selectedAcpId)
              .firstOrNull;
    // 只有 ACP 条目真实存在时才进入其详情；不把缺失条目当成空详情。
    final AcpAccountEntryView? acpDetails = _showDetails ? selectedAcp : null;
    final selectedId =
        _selectedAccountId ??
        defaultAccountId ??
        settings.accounts.firstOrNull?.id;
    final selected = settings.accounts
        .where((account) => account.id == selectedId)
        .firstOrNull;
    final filtered = _filteredAccounts();
    final usageView = ref.watch(settingsUsageViewProvider);
    final canonicalUsages = usageView.usages;
    final usageByAccount = {
      for (final usage in canonicalUsages) usage.accountId: usage,
    };
    final queryState = ref.watch(accountUsageQueriesProvider);
    final usageErrorsByAccountId = queryState.errorsByAccountId;
    final loadingAccountIds = queryState.loadingAccountIds;
    final details = switch (acpDetails) {
      final entry? => AcpAccountDetails(
        entry: entry,
        busy: _authBusy,
        cancelBusy: _cancelPending.contains(entry.id),
        authNotice: _noticeFor(entry),
        onBack: () {
          _flushCompactIntents();
          setState(() {
            _showDetails = false;
            _acpNotices.remove(entry.id);
          });
        },
        onEdit: () => _startAcpEdit(entry),
        onRemove: () => _removeAcpAccount(entry),
        onCheck: () => _runAcpAuth(
          entry.account.accountId,
          () => ref
              .read(anyworkClientProvider)
              .acpCommands
              .check(entry.account.accountId),
        ),
        // 取消绕过 start 的 busy 守卫：只要 canonical 给出 operation 身份就能提交。
        onCancel: () => _runAcpCancel(entry.account.accountId),
        onLogin: (methodId) => _runAcpAuth(
          entry.account.accountId,
          () => ref
              .read(anyworkClientProvider)
              .acpCommands
              .login(entry.account.accountId, methodId: methodId),
        ),
      ),
      null => AccountDetails(
        account: selected,
        usage: selected == null ? null : usageByAccount[selected.id],
        usageLoading:
            selected != null && loadingAccountIds.contains(selected.id),
        usageError: selected == null
            ? null
            : usageErrorsByAccountId[selected.id],
        onBack: () {
          _flushCompactIntents();
          setState(() => _showDetails = false);
        },
        onEdit: _startEdit,
        autoCompactEdits: {
          for (final entry in _compactIntents.entries)
            if (entry.key.$1 == selectedId)
              entry.key.$2: (
                overrideLimit: entry.value.value,
                pending: !entry.value.failed,
                failed: entry.value.failed,
              ),
        },
        onAutoCompactChanged: (modelId, value) =>
            _changeCompact(selectedId!, modelId, value),
        onAutoCompactCommit: (modelId) => _commitCompact(selectedId!, modelId),
        onAutoCompactInvalid: (modelId) =>
            _invalidateCompact(selectedId!, modelId),
        onRemoveManualModel: selected == null
            ? (_) {}
            : (model) => unawaited(_removeManualModel(selected, model)),
        onRefreshUsage: selected == null
            ? null
            : () => unawaited(_refreshUsages(accountId: selected.id)),
      ),
    };
    final acpEntries = _filteredAcpEntries(directory);
    final list = AccountList(
      accounts: filtered,
      acpEntries: acpEntries,
      // 只在目标账号行显示它自己的命令失败：不会跨账号、也不会被旧拒绝掩盖成功。
      acpNotices: _visibleNotices(acpEntries),
      selectedAccountId: acpDetails == null && _showDetails ? selectedId : null,
      selectedAcpAccountId: acpDetails?.id,
      onSelectAcp: (entry) {
        _flushCompactIntents();
        setState(() {
          _selectedAcpId = entry.id;
          _selectedAccountId = null;
          _showDetails = true;
        });
      },
      onEditAcp: _startAcpEdit,
      onRemoveAcp: _removeAcpAccount,
      defaultAccountId: defaultAccountId,
      filtering: _query.trim().isNotEmpty,
      usageByAccount: usageByAccount,
      loadingAccountIds: loadingAccountIds,
      usageErrorsByAccountId: usageErrorsByAccountId,
      onQueryChanged: (value) => setState(() => _query = value),
      onAdd: _startAdd,
      onSelect: (account) {
        _flushCompactIntents();
        setState(() {
          _selectedAccountId = account.id;
          _selectedAcpId = null;
          _showDetails = true;
        });
      },
      onSetDefault: _setDefaultAccount,
      onRefreshAll: _refreshUsages,
      onRefreshProvider: (account) =>
          unawaited(_refreshUsages(accountId: account.id)),
      onEdit: _startEdit,
      onDelete: _settings.accounts.length <= 1 ? null : _removeAccount,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 1100 && _showDetails;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (visible)
                SettingsTopicStatus(topic: const AccountUsageTopic()),
              Expanded(
                child: split
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 360, child: list),
                          const SizedBox(width: 24),
                          const VerticalDivider(width: 1),
                          const SizedBox(width: 24),
                          Expanded(child: details),
                        ],
                      )
                    : _showDetails
                    ? details
                    : list,
              ),
            ],
          ),
        );
      },
    );
  }

  List<AcpAccountEntryView> _filteredAcpEntries(
    AccountDirectoryView directory,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return directory.acpEntries;
    return directory.acpEntries.where((entry) {
      final haystack = [
        entry.name,
        entry.id,
        entry.account.provider.wire,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _startAcpEdit(AcpAccountEntryView entry) {
    _flushCompactIntents();
    setState(() {
      _saveSession.abandon();
      _selectedAcpId = entry.id;
      _selectedAccountId = null;
      _showDetails = false;
      _draft = AcpAccountEditorDraft(
        AcpAccountDraft.edit(account: entry.account, template: entry.template),
      );
      _draftFormKey = GlobalKey<FormState>();
      _draftError = null;
    });
  }

  void _updateAcpDraft(AcpAccountDraft Function(AcpAccountDraft) update) {
    final editor = _draft;
    if (editor is! AcpAccountEditorDraft) return;
    setState(() => _draft = AcpAccountEditorDraft(update(editor.draft)));
  }

  /// 显式认领同 provider 已准备好的结果（来自另一个操作）。
  ///
  /// 只有用户按下“使用已准备结果”才绑定该 operation：同名品牌或相似路径都不是
  /// 认领依据。
  void _usePreparedAcp(AcpInstallStateView state) {
    final editor = _draft;
    if (editor is! AcpAccountEditorDraft) return;
    final operationId = state.operationId;
    if (operationId == null || state.server == null) return;
    // 与测试走同一生产入口：准备请求在途时认领被拒绝，迟到的 start 不能覆盖它。
    final claimed = _preparation.claim(
      draft: editor.draft,
      currentDraft: () => _acpDraftOrNull,
      operationId: operationId,
    );
    if (claimed == null) return;
    setState(() {
      _draft = AcpAccountEditorDraft(claimed);
      _draftError = null;
    });
  }

  /// “下载并准备”：只受理共享操作并把 operation 绑定到本草稿。
  ///
  /// 不保存账号、不检查连接；终态与进度全部由 `acpInstall` topic 推进。
  Future<void> _prepareAcpDraft() async {
    final editor = _draft;
    if (editor is! AcpAccountEditorDraft) return;
    if (_preparation.isPending) return;
    setState(() {
      _preparePending = true;
      _draftError = null;
    });
    // 协调器在内部冻结尝试身份并调用 Client；这里只应用结论。
    final outcome = await _preparation.prepare(
      draft: editor.draft,
      currentDraft: () => _acpDraftOrNull,
    );
    if (!mounted) return;
    setState(() => _preparePending = _preparation.isPending);
    if (outcome == null || outcome.stale) return;
    final claimed = outcome.claimed;
    if (claimed != null) {
      setState(() => _draft = AcpAccountEditorDraft(claimed));
    }
    final error = outcome.error;
    if (error != null) {
      setState(() => _draftError = _installFailureSummary(error));
    }
  }

  /// 取消当前共享准备；命中 canonical operation 身份，独立于 start 的在途标志。
  Future<void> _cancelAcpInstall() async {
    final editor = _draft;
    if (editor is! AcpAccountEditorDraft) return;
    final provider = editor.draft.template.provider;
    final target = ref
        .read(anyworkClientProvider)
        .acpInstall
        .stateOf(provider)
        .operationId;
    // 没有 canonical 目标就没有可取消身份：不发无目标取消。
    if (target == null) return;
    // await 之前冻结身份：表单实例 + provider + 目标 operation + 唯一序号。
    final attempt = _installCancelSession.begin(
      formId: editor.draft.formId,
      provider: provider,
      operationId: target,
    );
    if (attempt == null) return;
    setState(() => _draftError = null);
    try {
      // 命令后仍由 Client 拥有：离开表单只释放本地观察，不取消已发出的请求。
      await ref.read(anyworkClientProvider).acpInstallCommands.cancel(provider);
    } catch (error) {
      if (!mounted) return;
      final current = _draft;
      final accepted = _installCancelSession.accepts(
        attempt,
        currentFormId: current is AcpAccountEditorDraft
            ? current.draft.formId
            : null,
        currentProvider: provider,
        currentOperationId: ref
            .read(anyworkClientProvider)
            .acpInstall
            .stateOf(provider)
            .operationId,
      );
      // 旧取消的失败只属于旧草稿/旧 operation：不写进当前表单的错误位。
      if (!accepted) return;
      setState(() => _draftError = _installFailureSummary(error));
    } finally {
      final released = _installCancelSession.finish(attempt);
      if (released && mounted) setState(() {});
    }
  }

  /// 准备命令的 typed 就地说明：只显示安全码值，不展示原始库错误。
  String _installFailureSummary(Object error) {
    final l10n = context.l10n;
    return l10n.acpInstallCommandFailed(
      error is StudioFailure
          ? studioFailureCodeText(l10n, error.code)
          : l10n.acpAuthCommandUnavailable,
    );
  }

  /// “保存并连接”：先确认 canonical 保存，再提交检查。
  ///
  /// 检查被拒绝时保留已保存的接入、进入同一账号的详情页并就地说明“账号已保存，
  /// 连接未完成”；不重建账号、不回滚保存、不重复保存。
  Future<void> _saveAcpDraft() async {
    final editor = _draft;
    if (editor is! AcpAccountEditorDraft || _saveSession.isSaving) return;
    if (_draftFormKey.currentState?.validate() == false) return;
    // 受管 program/argv 由产品固定发行与安装事实决定，保存意图只有身份与显示名。
    // 新建必须先准备到 Ready（界面已按 prepared 门控保存入口）；编辑只改名字，
    // 因此保存后不发起连接检查、也不改 connectionRevision。
    final provider = editor.draft.template.provider;
    final installState = ref
        .read(anyworkClientProvider)
        .acpInstall
        .stateOf(provider);
    final ready = editor.draft.intent.resolve(installState, provider: provider);
    if (editor.draft.isCreate && ready == null) return;
    final update = editor.draft.toUpdate();
    final epoch = _saveSession.begin();
    setState(() => _draftError = null);
    try {
      final commands = ref.read(anyworkClientProvider).acpCommands;
      if (!editor.draft.isCreate) {
        final renamed = await commands.saveAccount(update);
        if (!_saveSession.owns(epoch)) return;
        _saveSession.succeed(epoch);
        if (!mounted) return;
        setState(() {
          _selectedAcpId = renamed.accountId;
          _selectedAccountId = null;
          _showDetails = true;
          _draft = null;
        });
        return;
      }
      final result = await commands.saveAndConnect(update);
      if (!_saveSession.owns(epoch)) return;
      _saveSession.succeed(epoch);
      if (!mounted) return;
      final failure = result.checkFailure;
      setState(() {
        _selectedAcpId = result.saved.accountId;
        _selectedAccountId = null;
        _showDetails = true;
        _draft = null;
        final notice = failure == null
            ? null
            : _savedConnectNotice(
                failure,
                accountId: result.saved.accountId,
                connectionRevision: result.saved.connectionRevision,
              );
        if (notice == null) {
          _acpNotices.remove(result.saved.accountId);
        } else {
          _acpNotices[result.saved.accountId] = notice;
        }
      });
    } catch (error) {
      if (_saveSession.owns(epoch)) {
        _saveSession.fail(epoch);
        if (mounted) {
          setState(() => _draftError = _saveFailureSummary(error));
        }
      }
    }
  }

  Future<void> _removeAcpAccount(AcpAccountEntryView entry) async {
    final l10n = context.l10n;
    try {
      await ref.read(anyworkClientProvider).acpCommands.removeAccount(entry.id);
      if (!mounted) return;
      setState(() {
        if (_selectedAcpId == entry.id) {
          _selectedAcpId = null;
          _showDetails = false;
        }
        _acpNotices.remove(entry.id);
      });
    } catch (error) {
      if (!mounted) return;
      // 失败就地显示在**目标行**：不挂到另一个被选中的账号上；删除属于配置命令，
      // 不会被该账号后续认证成功掩盖。
      final notice = _commandNotice(
        error,
        kind: AcpCommandNoticeKind.remove,
        accountId: entry.id,
        connectionRevision: entry.account.connectionRevision,
        summary: (code) =>
            l10n.acpAuthCommandFailure(studioFailureCodeText(l10n, code)),
        fallbackSummary: l10n.acpAccountRemoveFailed,
      );
      setState(() => _acpNotices[entry.id] = notice);
    }
  }

  /// 取消命令：独立于 start 的在途标志，避免迟到的 start 回执锁死取消。
  ///
  /// 忙状态按传入的 [accountId] 记账（不是当前选中项）：切换详情页时只影响该账号，
  /// 也不会用新的 selectedId 清掉别人的 pending。
  Future<void> _runAcpCancel(String accountId) async {
    if (_cancelPending.contains(accountId)) return;
    final l10n = context.l10n;
    // 身份在发起时冻结：响应晚于配置变化时按过时处理，而不是绑定新一代连接。
    final requestConnectionRevision = _connectionRevisionOf(accountId);
    setState(() {
      _cancelPending.add(accountId);
      _acpNotices.remove(accountId);
    });
    try {
      await ref.read(anyworkClientProvider).acpCommands.cancel(accountId);
    } catch (error) {
      if (!mounted) return;
      final notice = _commandNotice(
        error,
        kind: AcpCommandNoticeKind.authentication,
        accountId: accountId,
        connectionRevision: requestConnectionRevision,
        operationId: _accountEntry(accountId)?.auth.operationId,
        summary: (code) =>
            l10n.acpAuthCommandFailure(studioFailureCodeText(l10n, code)),
      );
      setState(() => _acpNotices[accountId] = notice);
    } finally {
      if (mounted && _cancelPending.contains(accountId)) {
        setState(() => _cancelPending.remove(accountId));
      }
    }
  }

  /// 认证命令只提交意图；状态仍由 `acpAuth` canonical 观察推进。
  ///
  /// typed `busy` 且该账号当前连接身份下**已有 canonical 在途操作**时，这只是一次
  /// 重复输入：进度由 canonical 状态承接，不记成红色失败（其他账号的 busy、真正的
  /// cleanup/认证失败仍照常呈现）。
  Future<void> _runAcpAuth(
    String accountId,
    Future<void> Function() action,
  ) async {
    if (_authBusy) return;
    final l10n = context.l10n;
    // 请求身份在 await **之前**冻结：迟到的回执不会绑定到新一代连接。
    final requestConnectionRevision = _connectionRevisionOf(accountId);
    setState(() {
      _authBusy = true;
      _acpNotices.remove(accountId);
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      if (isAcpAuthDuplicateWhileInFlight(
        error: error,
        accountId: accountId,
        requestConnectionRevision: requestConnectionRevision,
        entry: _accountEntry(accountId),
      )) {
        return;
      }
      final notice = _commandNotice(
        error,
        kind: AcpCommandNoticeKind.authentication,
        accountId: accountId,
        connectionRevision: requestConnectionRevision,
        operationId: _accountEntry(accountId)?.auth.operationId,
        summary: (code) =>
            l10n.acpAuthCommandFailure(studioFailureCodeText(l10n, code)),
      );
      setState(() => _acpNotices[accountId] = notice);
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  /// 该账号当前的连接身份；账号已不存在时用 0（notice 会因身份不匹配而不显示）。
  int _connectionRevisionOf(String accountId) =>
      _accountEntry(accountId)?.account.connectionRevision ?? 0;

  AcpAccountEntryView? _accountEntry(String accountId) => ref
      .read(settingsAccountDirectoryProvider)
      .acpEntries
      .where((entry) => entry.id == accountId)
      .firstOrNull;

  /// 列表行要显示的通知（逐账号过滤）。
  Map<String, AcpCommandNotice> _visibleNotices(
    List<AcpAccountEntryView> entries,
  ) {
    final visible = <String, AcpCommandNotice>{};
    for (final entry in entries) {
      final notice = _noticeFor(entry);
      if (notice != null) visible[entry.id] = notice;
    }
    return visible;
  }

  /// 通知呈现规则由 `visibleAcpCommandNotice` 统一实现（可被适配层测试直接驱动）。
  AcpCommandNotice? _noticeFor(AcpAccountEntryView entry) =>
      visibleAcpCommandNotice(_acpNotices[entry.id], entry);

  /// typed 命令失败 → 本地化摘要 + 可选后端安全原文（不是 raw stderr）。
  AcpCommandNotice _commandNotice(
    Object error, {
    required AcpCommandNoticeKind kind,
    required String accountId,
    required int connectionRevision,
    String? operationId,
    required String Function(StudioFailureCode code) summary,
    String? fallbackSummary,
  }) {
    final detail = error is StudioFailure && error.message.isNotEmpty
        ? error.message
        : null;
    return AcpCommandNotice(
      kind: kind,
      summary: error is StudioFailure
          ? summary(error.code)
          : (fallbackSummary ?? context.l10n.acpAuthCommandUnavailable),
      detail: detail,
      accountId: accountId,
      connectionRevision: connectionRevision,
      operationId: operationId,
    );
  }

  /// “账号已保存，连接未完成”：认证类通知，摘要本地化（typed code），原文作次级详情。
  AcpCommandNotice _savedConnectNotice(
    StudioFailure failure, {
    required String accountId,
    required int connectionRevision,
  }) {
    final l10n = context.l10n;
    return AcpCommandNotice(
      kind: AcpCommandNoticeKind.authentication,
      summary: l10n.acpAccountSavedConnectIncomplete(
        studioFailureCodeText(l10n, failure.code),
      ),
      detail: failure.message.isEmpty ? null : failure.message,
      accountId: accountId,
      connectionRevision: connectionRevision,
    );
  }

  /// ACP 保存失败的本地化摘要：typed code → 文案，未知错误用通用文案。
  /// 不把任意 `toString()`（可能含关联 ID/内部信息）放进产品文案。
  String _saveFailureSummary(Object error) {
    final l10n = context.l10n;
    return l10n.acpAccountSaveFailed(
      error is StudioFailure
          ? studioFailureCodeText(l10n, error.code)
          : l10n.acpAuthCommandUnavailable,
    );
  }

  List<AccountSettingsView> _filteredAccounts() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _settings.accounts;
    }
    return _settings.accounts.where((account) {
      final haystack = [
        account.name,
        account.id,
        account.defaultModelId,
        for (final model in account.models) model.modelId,
        for (final model in account.models) model.displayName,
        for (final model in account.models) model.wireApi,
        for (final model in account.models) model.connectionMode,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _startAdd() async {
    _flushCompactIntents();
    final l10n = context.l10n;
    final settings = ref.read(settingsAccountsViewProvider);
    final directory = ref.read(settingsAccountDirectoryProvider);
    if (directory.templates.isEmpty) {
      setState(() => _draftError = l10n.settingsAccountCatalogUnavailable);
      return;
    }
    // 同一入口汇集两个 typed 目录；选择结果决定草稿分支，不按模板 id 猜协议。
    final choice = await showAccountTemplatePicker(
      context,
      templates: directory.templates,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case NativeAccountTemplateChoice(:final template):
        final id = directory.suggestId(template.id);
        final draft = AccountDraftFactory.create(
          catalog: settings.accountCatalog,
          templateId: template.id,
          accountId: id,
        );
        if (draft == null) {
          setState(() => _draftError = l10n.settingsAccountTemplateUnavailable);
          return;
        }
        setState(() {
          _saveSession.abandon();
          _selectedAccountId = id;
          _selectedAcpId = null;
          _showDetails = false;
          _draft = NativeAccountEditorDraft(draft);
          _draftFormKey = GlobalKey<FormState>();
          _draftError = null;
        });
      case AcpAccountTemplateChoice(:final template):
        final id = directory.suggestId(template.provider.wire);
        setState(() {
          _saveSession.abandon();
          _selectedAcpId = id;
          _selectedAccountId = null;
          _showDetails = false;
          _draft = AcpAccountEditorDraft(
            AcpAccountDraft.create(template: template, accountId: id),
          );
          _draftFormKey = GlobalKey<FormState>();
          _draftError = null;
        });
    }
  }

  Future<void> _startEdit(AccountSettingsView account) async {
    _flushCompactIntents();
    await _client.settingsCommands.enqueueSettingsWrite(() async {});
    if (!mounted) return;
    final latest = _settings.accounts
        .where((item) => item.id == account.id)
        .firstOrNull;
    if (latest == null) return;
    setState(() {
      _saveSession.abandon();
      _selectedAccountId = account.id;
      _selectedAcpId = null;
      _showDetails = false;
      _draft = NativeAccountEditorDraft(AccountDraft.edit(latest));
      _draftFormKey = GlobalKey<FormState>();
      _draftError = null;
    });
  }

  void _changeDraftTemplate(String templateId) {
    final catalog = ref.read(settingsAccountsViewProvider).accountCatalog;
    final editor = _draft;
    if (editor is! NativeAccountEditorDraft) return;
    final current = editor.draft;
    if (current.account.templateId == templateId) {
      return;
    }
    // 账号 ID 只分配一次：切换模板重建草稿内容，但不改账号身份。
    final next = AccountDraftFactory.changeTemplate(
      draft: current,
      catalog: catalog,
      templateId: templateId,
      accountId: current.account.id,
    );
    if (next == null) {
      return;
    }
    setState(() {
      _draft = NativeAccountEditorDraft(next);
      // A retained GlobalKey would reparent the old Form under the new
      // AccountEditor and preserve its text, validation and secret fields.
      _draftFormKey = GlobalKey<FormState>();
    });
  }

  void _updateDraft(AccountSettingsView Function(AccountSettingsView) update) {
    final editor = _draft;
    if (editor is! NativeAccountEditorDraft) return;
    final current = editor.draft;
    setState(
      () => _draft = NativeAccountEditorDraft(
        current.copyWith(account: update(current.account)),
      ),
    );
  }

  void _addCustomModel() {
    _updateDraft((account) {
      final existing = account.models.map((model) => model.modelId).toSet();
      var modelId = 'custom-model';
      for (var index = 2; existing.contains(modelId); index += 1) {
        modelId = 'custom-model-$index';
      }
      final model = AccountModelView(
        modelId: modelId,
        displayName: modelId,
        contextWindow: 32000,
        maxOutputTokens: 4096,
        reasoningEfforts: const [],
        wireApi: 'chat_completions',
        supportedConnectionModes: const ['http'],
        defaultConnectionMode: 'http',
        connectionMode: 'http',
        origin: ModelOrigin.manual,
      );
      return account.copyWith(models: [...account.models, model]);
    });
  }

  void _updateCustomModel(int index, AccountModelView model) {
    _updateDraft((account) {
      final previousModel = account.customModels[index];
      final previousModelId = previousModel.modelId;
      final connections = {...account.modelConnectionModes};
      if (previousModelId != model.modelId ||
          previousModel.wireApi != model.wireApi) {
        connections.remove(previousModelId);
      }
      // 草稿仅保留覆盖意图；保存后由后端重新解析容量与最终阈值。
      final limits = {...account.autoCompactLimits};
      final overrideDraft = AccountModelAutoCompactView(
        modelId: model.modelId,
        overrideLimit: limits[previousModelId]?.overrideLimit,
      );
      if (previousModelId != model.modelId) {
        limits.remove(previousModelId);
      }
      limits[model.modelId] = overrideDraft;
      final models = [
        for (final candidate in account.models)
          if (candidate.modelId == previousModelId)
            model.copyWith(origin: ModelOrigin.manual)
          else
            candidate,
      ];
      return account.copyWith(
        modelConnectionModes: connections,
        autoCompactLimits: limits,
        models: models,
      );
    });
  }

  void _removeCustomModel(int index) {
    _updateDraft((account) {
      final custom = [...account.customModels];
      final removedModelId = custom[index].modelId;
      custom.removeAt(index);
      final models = [
        for (final candidate in account.models)
          if (candidate.modelId != removedModelId) candidate,
      ];
      final limits = {...account.autoCompactLimits}..remove(removedModelId);
      final connections = {...account.modelConnectionModes}
        ..remove(removedModelId);
      // 账号不保存第二份默认模型：删除手动模型只清理它的覆盖与声明。
      return account.copyWith(
        modelConnectionModes: connections,
        autoCompactLimits: limits,
        models: models,
      );
    });
  }

  Future<void> _removeManualModel(
    AccountSettingsView account,
    AccountModelView model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsRemoveManualModelConfirmTitle),
        content: Text(context.l10n.settingsRemoveManualModelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsCancel),
          ),
          FilledButton(
            key: StudioDriverKeys.accountManualModelDeleteConfirm,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.settingsRemoveManualModelConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _client.settingsCommands.removeAccountModel(
        account.id,
        model.modelId,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsRemoveManualModelFailed)),
      );
    }
  }

  Future<void> _saveDraft() async {
    final editor = _draft;
    if (editor is! NativeAccountEditorDraft || _saveSession.isSaving) {
      return;
    }
    final current = editor.draft;
    if (_draftFormKey.currentState?.validate() == false) {
      return;
    }
    final epoch = _saveSession.begin();
    setState(() => _draftError = null);
    try {
      final account = AccountCommandBuilder.normalizeAccount(current.account);
      final makeDefault =
          current.mode == AccountDraftMode.create ||
          ref.read(settingsAccountsViewProvider).defaultAccountId ==
              current.originalId;
      final saved = await ref
          .read(anyworkClientProvider)
          .settingsCommands
          .saveAccount(AccountCommandBuilder.buildAccount(account));
      if (!saved.accounts.any((candidate) => candidate.id == account.id)) {
        throw StateError(
          'Account save returned a canonical snapshot without ${account.id}.',
        );
      }
      if (makeDefault) {
        await ref
            .read(anyworkClientProvider)
            .settingsCommands
            .setDefaultAccount(account.id);
      }
      if (!_saveSession.owns(epoch)) {
        return;
      }
      _saveSession.succeed(epoch);
      if (mounted) {
        setState(() {
          _selectedAccountId = account.id;
          _draft = null;
          _showDetails = false;
        });
      }
    } catch (error) {
      if (_saveSession.owns(epoch)) {
        _saveSession.fail(epoch);
        if (mounted) {
          setState(() => _draftError = error.toString());
        }
      }
    }
  }

  Future<void> _removeAccount(AccountSettingsView account) async {
    if (_settings.accounts.length <= 1) {
      return;
    }
    final accounts = _canonicalAccounts
        .where((candidate) => candidate.id != account.id)
        .toList();
    final currentDefaultId = ref
        .read(settingsAccountsViewProvider)
        .defaultAccountId;
    final selectedAccountId = ModelRouteQueries.accountAfterRemoval(
      accounts: accounts,
      currentDefault: currentDefaultId,
      removed: account.id,
    );
    final saved = await ref
        .read(anyworkClientProvider)
        .settingsCommands
        .removeAccount(account.id, replacementAccountId: selectedAccountId);
    if (saved.accounts.any((candidate) => candidate.id == account.id)) {
      throw StateError(
        'Account removal returned a canonical snapshot that still contains '
        '${account.id}.',
      );
    }
    if (mounted) {
      setState(() {
        _selectedAccountId = selectedAccountId;
        _showDetails = false;
        if (_draft case NativeAccountEditorDraft(:final draft)
            when draft.originalId == account.id) {
          _draft = null;
        }
      });
    }
    ref.read(anyworkClientProvider).accountUsageQueries.forget(account.id);
  }

  Future<void> _setDefaultAccount(AccountSettingsView account) async {
    setState(() => _selectedAccountId = account.id);
    await ref
        .read(anyworkClientProvider)
        .settingsCommands
        .setDefaultAccount(account.id);
    final saved = ref.read(settingsAccountsViewProvider);
    if (saved.canonical == null || saved.defaultAccountId != account.id) {
      throw StateError(
        'Account default save returned ${saved.defaultAccountId}, '
        'expected ${account.id}.',
      );
    }
  }

  Future<void> _refreshUsages({String? accountId}) async {
    final queries = ref.read(anyworkClientProvider).accountUsageQueries;
    if (accountId == null) {
      await queries.refreshAll();
      return;
    }
    ignoreAccountUsageQueryErrors(queries.refresh(accountId));
  }

  List<AccountSettingsView> get _canonicalAccounts => _settings.accounts;
}

/// 对象身份隔离旧完成通知；不把原始文本、焦点或 canonical 数据放进提交状态。
class _AutoCompactIntent {
  _AutoCompactIntent(this.value);

  final int? value;
  Timer? timer;
  bool submitted = false;
  bool failed = false;
}

/// 在目录投影里按 accountId 取 ACP 条目；找不到返回 null（不猜身份）。
AcpAccountEntryView? _acpEntryOf(AccountDirectoryView directory, String id) =>
    directory.acpEntries.where((entry) => entry.id == id).firstOrNull;
