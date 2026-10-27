import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart'
    show OperationState, OperationPhase;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_projection.dart';
import 'account_operation_result.dart';

part 'accounts_view_model.g.dart';

final class _ListAttempt {
  _ListAttempt(this.key, this.owner, this.acpRevision);
  final AccountDisplayKey key;
  final Object owner;
  final int? acpRevision;
  final observations = <Observation>[];
}

/// Summary-only list and navigation. This owner never opens a detail slot and
/// never copies an editor's draft. Visibility is separate from subscriptions.
@riverpod
class AccountsViewModel extends _$AccountsViewModel {
  late AccountsRepository _accounts;
  late AccountUsageRepository _usage;
  late AcpService _acp;
  AccountStrings _strings = const AccountStrings.empty();
  AccountDemand? _usageDemand;
  AccountDemand? _summaryDemand;
  String _search = '';
  AccountDisplayKey? _selected;
  AccountEditorKey? _editor;
  bool _choosing = false;
  bool _templatesLoading = false;
  String? _templateError;
  int _editorSequence = 0;
  final Map<AccountDisplayKey, String> _errors = {};
  final Set<AccountDisplayKey> _pending = {};
  final Map<AccountDisplayKey, _ListAttempt> _attempts = {};
  final Map<AccountDisplayKey, ({int? query, String message})> _refreshErrors =
      {};
  Object _ownerLifecycle = Object();
  String? _ownerEpoch;
  bool _ownerStale = false;

  @override
  FutureOr<AccountsViewState> build() {
    _accounts = ref.read(accountsRepositoryProvider);
    _usage = ref.read(accountUsageRepositoryProvider);
    _acp = ref.read(acpServiceProvider);
    _ownerEpoch = _accounts.state.value.stamp?.ownerEpoch;
    _ownerStale = _accounts.state.value.stale;
    _summaryDemand = _accounts.observeSummaries();
    final observations = [
      _accounts.state.watch(_summariesChanged),
      _usage.state.watch((_) => _publish()),
      _usage.queryFailures.watch((_) => _publish()),
      _acp.templates.watch((_) => _publish()),
    ];
    ref.onDispose(() {
      releaseAccountDemand(_summaryDemand);
      releaseAccountDemand(_usageDemand);
      for (final attempt in _attempts.values) {
        for (final observation in attempt.observations) {
          observation.cancel();
        }
      }
      for (final observation in observations) {
        observation.cancel();
      }
    });
    return _derive();
  }

  void setStrings(AccountStrings strings) {
    _strings = strings;
    _publish();
  }

  void setVisible(bool visible) {
    if (visible) {
      _usageDemand ??= _usage.observeVisible();
    } else {
      final demand = _usageDemand;
      _usageDemand = null;
      releaseAccountDemand(demand);
    }
  }

  void search(String raw) {
    _search = raw;
    _publish();
  }

  void open(AccountDisplayKey key) {
    if (_editor != null) {
      throw StateError('Confirm the editor before navigating');
    }
    _selected = key;
    _choosing = false;
    _publish();
  }

  void back() {
    if (_editor != null) {
      throw StateError('Confirm the editor before navigating');
    }
    _selected = null;
    _choosing = false;
    _publish();
  }

  void edit(AccountDisplayKey key) {
    if (_editor != null) {
      throw StateError('Confirm the editor before navigating');
    }
    _editor = AccountEditorKey(
      editorId: 'account-editor-${++_editorSequence}',
      target: key,
      creating: false,
    );
    _selected = key;
    _publish();
  }

  /// The caller has already resolved save/discard/cancel with the editor owner.
  void finishEditor(AccountEditorKey key, {bool saved = false}) {
    if (_editor != key) return;
    _editor = null;
    if (saved) _selected = key.target;
    _publish();
  }

  Future<void> chooseTemplate() async {
    if (_editor != null) {
      throw StateError('Confirm the editor before navigating');
    }
    _choosing = true;
    _templatesLoading = true;
    _templateError = null;
    _publish();
    try {
      await Future.wait([_accounts.loadTemplates(), _acp.loadTemplates()]);
    } catch (error) {
      if (ref.mounted) _templateError = safeAccountError(error, _strings);
    } finally {
      if (ref.mounted) {
        _templatesLoading = false;
        _publish();
      }
    }
  }

  void cancelTemplate() {
    _choosing = false;
    _publish();
  }

  /// Stable identity is allocated before constructing the form. Native and ACP
  /// may use the same bare id; collisions are checked within the selected kind.
  AccountEditorKey? create(AccountTemplateKey template) {
    final exists = template.kind == AccountKind.native
        ? _accounts.state.value.templates.template(template.id) != null
        : _acp.templates.value.templates.any(
            (value) => value.provider.wire == template.id,
          );
    if (!exists || _editor != null) {
      _templateError = _strings['unknownTemplate'];
      _publish();
      return null;
    }
    final used = {
      for (final account in _accounts.state.value.accounts)
        if (displayIdentity(account.identity).kind == template.kind)
          account.identity.accountId,
    };
    var id = template.id;
    for (var suffix = 2; used.contains(id); suffix++) {
      id = '${template.id}-$suffix';
    }
    _editor = AccountEditorKey(
      editorId: 'account-editor-${++_editorSequence}',
      target: AccountDisplayKey(kind: template.kind, id: id),
      template: template,
      creating: true,
    );
    _choosing = false;
    _publish();
    return _editor;
  }

  Future<void> refresh(AccountDisplayKey key) async {
    if (key.kind != AccountKind.native) return;
    final owner = _ownerLifecycle;
    final query = _accounts.state.value
        .account(domainIdentity(key))
        ?.usageQueryRevision;
    _refreshErrors.remove(key);
    try {
      await _usage.refresh(NativeAccountIdentity(key.id));
    } catch (error) {
      if (ref.mounted &&
          identical(owner, _ownerLifecycle) &&
          _accounts.state.value.loaded &&
          _accounts.state.value
                  .account(domainIdentity(key))
                  ?.usageQueryRevision ==
              query) {
        _refreshErrors[key] = (
          query: query,
          message: safeAccountError(error, _strings),
        );
        _publish();
      }
    }
  }

  Future<void> refreshAll() async {
    final keys = [
      for (final account in _accounts.state.value.accounts)
        if (account.identity is NativeAccountIdentity &&
            account.capabilities.queryUsage)
          displayIdentity(account.identity),
    ];
    await Future.wait(keys.map(refresh));
  }

  void retryObservation() {
    releaseAccountDemand(_summaryDemand);
    _summaryDemand = _accounts.observeSummaries();
  }

  String accountName(AccountDisplayKey key) =>
      _accounts.state.value.account(domainIdentity(key))?.name ?? key.id;
  bool needsReplacement(AccountDisplayKey key) =>
      key.kind == AccountKind.native &&
      _accounts.state.value.account(domainIdentity(key))?.isDefault == true &&
      replacements(key).isNotEmpty;
  List<AccountRowPresentation> replacements(AccountDisplayKey key) => [
    for (final summary in _accounts.state.value.accounts)
      if (summary.identity is NativeAccountIdentity &&
          summary.identity != domainIdentity(key))
        AccountRowPresentation(
          key: displayIdentity(summary.identity),
          name: summary.name,
        ),
  ];

  Future<bool> remove(
    AccountDisplayKey key, {
    AccountDisplayKey? replacement,
  }) => replacement?.kind == AccountKind.acp
      ? Future.value(false)
      : _command(
          key,
          () => key.kind == AccountKind.native
              ? _accounts.remove(
                  NativeAccountIdentity(key.id),
                  replacement: replacement == null
                      ? null
                      : NativeAccountIdentity(replacement.id),
                )
              : _acp.remove(AcpAccountIdentity(key.id)),
        );

  Future<bool> setDefault(AccountDisplayKey key) =>
      key.kind == AccountKind.native
      ? _command(key, () => _accounts.setDefault(NativeAccountIdentity(key.id)))
      : Future.value(false);

  Future<bool> _command(
    AccountDisplayKey key,
    Future<OperationState> Function() action,
  ) async {
    final summary = _accounts.state.value.account(domainIdentity(key));
    if (!_accounts.state.value.loaded ||
        summary == null ||
        (key.kind == AccountKind.acp &&
            summary.acpConnectionRevision == null) ||
        !_pending.add(key)) {
      return false;
    }
    final previous = _attempts[key];
    if (previous != null) {
      for (final observation in previous.observations) {
        observation.cancel();
      }
    }
    final attempt = _ListAttempt(
      key,
      _ownerLifecycle,
      key.kind == AccountKind.acp ? summary.acpConnectionRevision : null,
    );
    _attempts[key] = attempt;
    _errors.remove(key);
    _publish();
    try {
      if (!_owns(attempt)) return false;
      final result = await action();
      if (!_owns(attempt)) return false;
      void apply(OperationState operation) {
        if (!_owns(attempt)) return;
        if (operationSaved(operation) ||
            operation.failurePhase == OperationPhase.rejected) {
          _pending.remove(key);
        }
        final message = operationMessage(operation, _strings);
        if (message == null) {
          _errors.remove(key);
          if (_selected == key &&
              _accounts.state.value.account(domainIdentity(key)) == null) {
            _selected = null;
          }
        } else {
          _errors[key] = message;
        }
        _publish();
      }

      trackAccountOperation(ref, result, attempt.observations, apply);
      return operationSaved(result);
    } catch (error) {
      if (_owns(attempt)) {
        _errors[key] = safeAccountError(error, _strings);
        _pending.remove(key);
      }
      return false;
    } finally {
      if (_owns(attempt)) _publish();
    }
  }

  bool _owns(_ListAttempt attempt) {
    if (!ref.mounted ||
        !identical(_attempts[attempt.key], attempt) ||
        !identical(_ownerLifecycle, attempt.owner)) {
      return false;
    }
    final source = _accounts.state.value;
    final summary = source.account(domainIdentity(attempt.key));
    return source.loaded &&
        summary != null &&
        (attempt.key.kind == AccountKind.native ||
            summary.acpConnectionRevision == attempt.acpRevision);
  }

  void _summariesChanged(AccountsState source) {
    final epoch = source.stamp?.ownerEpoch;
    final changed =
        (source.stale && !_ownerStale) ||
        (epoch != null && epoch != _ownerEpoch);
    if (changed) {
      _ownerLifecycle = Object();
      _refreshErrors.clear();
    }
    _ownerStale = source.stale;
    _ownerEpoch = epoch ?? _ownerEpoch;
    for (final attempt in _attempts.values.toList()) {
      final summary = source.account(domainIdentity(attempt.key));
      if (changed ||
          (source.loaded &&
              (summary == null ||
                  (attempt.key.kind == AccountKind.acp &&
                      summary.acpConnectionRevision != attempt.acpRevision)))) {
        for (final observation in attempt.observations) {
          observation.cancel();
        }
        _attempts.remove(attempt.key);
        _errors.remove(attempt.key);
        _pending.remove(attempt.key);
      }
    }
    if (source.loaded &&
        _editor == null &&
        _selected != null &&
        source.account(domainIdentity(_selected!)) == null) {
      _selected = null;
    }
    _refreshErrors.removeWhere(
      (key, value) =>
          source.loaded &&
          source.account(domainIdentity(key))?.usageQueryRevision !=
              value.query,
    );
    _publish();
  }

  AccountsViewState _derive() {
    final source = _accounts.state.value;
    final filtered = source.accounts.where((account) {
      final query = _search.trim().toLowerCase();
      return query.isEmpty ||
          account.name.toLowerCase().contains(query) ||
          account.identity.accountId.toLowerCase().contains(query);
    });
    return AccountsViewState(
      selected: _selected,
      editor: _editor,
      actions: {
        for (final attempt in _attempts.values)
          if (_owns(attempt))
            attempt.key: AccountActionPresentation(
              ownerEpoch: source.stamp!.ownerEpoch,
              acpConnectionRevision: attempt.acpRevision,
              pending: _pending.contains(attempt.key),
              message: _errors[attempt.key],
            ),
      },
      choosingTemplate: _choosing,
      templatesLoading: _templatesLoading,
      templateError: _templateError,
      templates: [
        for (final template in _acp.templates.value.templates)
          AccountTemplatePresentation(
            key: AccountTemplateKey(
              kind: AccountKind.acp,
              id: template.provider.wire,
            ),
            name: template.displayName,
            iconKey: template.iconKey,
            description: template.description,
          ),
        if (source.templates.revision.isNotEmpty)
          for (final template in source.templates.templates)
            AccountTemplatePresentation(
              key: AccountTemplateKey(
                kind: AccountKind.native,
                id: template.id,
              ),
              name: template.displayName,
              iconKey: template.iconKey,
              description: template.description,
            ),
      ],
      list: AccountsListPresentation(
        phase: source.stamp == null
            ? (source.failure != null
                  ? AccountListPhase.failed
                  : AccountListPhase.loading)
            : AccountListPhase.ready,
        search: _search,
        searchHasNoResults: _search.trim().isNotEmpty && filtered.isEmpty,
        selectedKey: _selected,
        editingKey: _editor?.target,
        refreshing: source.loading,
        canAdd: source.loaded,
        canRefresh: source.loaded,
        error: source.stale ? _strings['stale'] : source.failure?.message,
        rows: [
          for (final account in filtered)
            AccountRowPresentation(
              key: displayIdentity(account.identity),
              name: account.name,
              iconKey: account.brandKey,
              isDefault: account.isDefault,
              billing: account.identity is NativeAccountIdentity
                  ? displayBilling(account.billingKind)
                  : null,
              usage: account.identity is NativeAccountIdentity
                  ? projectUsage(
                      account,
                      _usage.state.value,
                      _usage.queryFailures.value,
                      _strings,
                    )
                  : null,
              operationError:
                  _errors[displayIdentity(account.identity)] ??
                  _refreshErrors[displayIdentity(account.identity)]?.message,
              actions:
                  _pending.contains(displayIdentity(account.identity)) ||
                      !source.loaded ||
                      (account.identity is AcpAccountIdentity &&
                          account.acpConnectionRevision == null)
                  ? const []
                  : [
                      if (account.capabilities.queryUsage)
                        AccountRowAction.refresh,
                      if (account.capabilities.setDefault && !account.isDefault)
                        AccountRowAction.setDefault,
                      if (account.capabilities.edit) AccountRowAction.edit,
                      if (account.capabilities.remove) AccountRowAction.delete,
                    ],
            ),
        ],
      ),
    );
  }

  void _publish() {
    if (ref.mounted) state = AsyncData(_derive());
  }
}
