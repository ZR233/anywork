import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/account_usage_queries.dart';

import 'package:anywork_client/studio_client.dart';

import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_account_details.dart';
import 'settings_account_draft_save.dart';
import 'settings_account_drafts.dart';
import 'settings_account_editor.dart';
import 'settings_account_list.dart';
import 'settings_account_usage_demand.dart';
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
  AccountDraft? _draft;
  GlobalKey<FormState> _draftFormKey = GlobalKey<FormState>();
  bool _showDetails = false;
  String? _draftError;
  final AccountDraftSaveSession _saveSession = AccountDraftSaveSession();
  final AccountUsageAutoDemand _usageDemand = AccountUsageAutoDemand();
  ProviderSubscription<bool>? _visibilitySubscription;
  ProviderSubscription<AccountUsageQueryIdentitySnapshot>?
  _identitySubscription;
  late final AnyworkClient _client;
  final Map<(String, String), _AutoCompactIntent> _compactIntents = {};
  bool _disposing = false;

  SettingsAccountsView get _settings => ref.read(settingsAccountsViewProvider);

  bool get _visible => ref.read(settingsVisibleTabProvider) == widget.tabIndex;

  @override
  void initState() {
    super.initState();
    _client = ref.read(anyworkClientProvider);
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
    final settings = ref.watch(settingsAccountsViewProvider);
    final catalog = settings.accountCatalog;
    final defaultAccountId = settings.defaultAccountId;
    final selectedId =
        _selectedAccountId ??
        defaultAccountId ??
        _settings.accounts.firstOrNull?.id;
    final selected = _settings.accounts
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
    if (_draft != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: AccountEditor(
              key: ValueKey((
                _draft!.mode,
                _draft!.originalId,
                _draft!.account.templateId,
              )),
              formKey: _draftFormKey,
              draft: _draft!,
              templates: catalog.templates,
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
    final details = AccountDetails(
      account: selected,
      usage: selected == null ? null : usageByAccount[selected.id],
      usageLoading: selected != null && loadingAccountIds.contains(selected.id),
      usageError: selected == null ? null : usageErrorsByAccountId[selected.id],
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
    );
    final list = AccountList(
      accounts: filtered,
      selectedAccountId: _showDetails ? selectedId : null,
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

  void _startAdd() {
    _flushCompactIntents();
    final catalog = ref.read(settingsAccountsViewProvider).accountCatalog;
    final template = catalog.templates.firstOrNull;
    if (template == null) {
      setState(
        () => _draftError = context.l10n.settingsAccountCatalogUnavailable,
      );
      return;
    }
    final id = _suggestAccountId(template.id);
    final draft = AccountDraftFactory.create(
      catalog: catalog,
      templateId: template.id,
      accountId: id,
    );
    if (draft == null) {
      setState(
        () => _draftError = context.l10n.settingsAccountTemplateUnavailable,
      );
      return;
    }
    setState(() {
      _saveSession.abandon();
      _selectedAccountId = id;
      _showDetails = false;
      _draft = draft;
      _draftFormKey = GlobalKey<FormState>();
      _draftError = null;
    });
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
      _showDetails = false;
      _draft = AccountDraft.edit(latest);
      _draftFormKey = GlobalKey<FormState>();
      _draftError = null;
    });
  }

  void _changeDraftTemplate(String templateId) {
    final catalog = ref.read(settingsAccountsViewProvider).accountCatalog;
    final current = _draft;
    if (current == null || current.account.templateId == templateId) {
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
      _draft = next;
      // A retained GlobalKey would reparent the old Form under the new
      // AccountEditor and preserve its text, validation and secret fields.
      _draftFormKey = GlobalKey<FormState>();
    });
  }

  void _updateDraft(AccountSettingsView Function(AccountSettingsView) update) {
    final current = _draft;
    if (current == null) {
      return;
    }
    setState(() => _draft = current.copyWith(account: update(current.account)));
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
    final current = _draft;
    if (current == null || _saveSession.isSaving) {
      return;
    }
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
        if (_draft?.originalId == account.id) {
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

  String _suggestAccountId(String base) {
    final existing = _canonicalAccounts.map((account) => account.id).toSet();
    if (!existing.contains(base)) {
      return base;
    }
    for (var index = 2; ; index += 1) {
      final candidate = '$base-$index';
      if (!existing.contains(candidate)) {
        return candidate;
      }
    }
  }
}

/// 对象身份隔离旧完成通知；不把原始文本、焦点或 canonical 数据放进提交状态。
class _AutoCompactIntent {
  _AutoCompactIntent(this.value);

  final int? value;
  Timer? timer;
  bool submitted = false;
  bool failed = false;
}
