import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_editor_ids.dart';
import 'account_editor_view_model.dart';
import 'account_models_view_model.dart';
import 'account_projection.dart';

part 'account_editor_session_view_model.g.dart';

final class _TemplateReplacement {
  _TemplateReplacement(this.source, this.owner, this.draftToken);
  final AccountEditorKey? source;
  final AccountEditorViewModel? owner;
  final Object? draftToken;
}

final class _LeaveDecision {
  _LeaveDecision(this.source, this.owner, this.editorToken);
  final AccountEditorKey? source;
  final AccountEditorViewModel? owner;
  final Object? editorToken;
}

final class _LeaveResolution {
  _LeaveResolution(
    this.decision,
    this.models,
    this.compactToken,
    this.discardCompact,
  );
  final _LeaveDecision decision;
  final AccountModelsViewModel? models;
  final Object? compactToken;
  final bool discardCompact;
  void Function()? closeEditorObservation;
  void Function()? closeModelsObservation;

  void closeObservations() {
    closeEditorObservation?.call();
    closeEditorObservation = null;
    closeModelsObservation?.call();
    closeModelsObservation = null;
  }
}

/// Finite draft resources for one actual editor entry. This owner does not
/// select pages, interpret URIs or initiate ACP preparation.
@riverpod
class AccountEditorSessionViewModel extends _$AccountEditorSessionViewModel {
  late AccountEditorEntryKey _entry;
  late AccountsRepository _accounts;
  late AcpService _acp;
  late AccountEditorIds _ids;
  AccountStrings _strings = const AccountStrings.empty();
  AccountEditorKey? _editor;
  AccountEditorViewModel? _editorOwner;
  bool _initialized = false;
  bool _finished = false;
  bool _templatesLoading = false;
  String? _error;
  String? _ownerEpoch;
  Future<void>? _loading;
  Object _templateIntent = Object();
  Object? _defaultIntent;
  _TemplateReplacement? _replacement;
  _LeaveDecision? _leaveDecision;
  _LeaveResolution? _leaveResolution;
  AccountDemand? _summaryDemand;
  final List<Observation> _observations = [];
  void Function()? _closeRetention;

  @override
  FutureOr<AccountEditorSessionState> build(AccountEditorEntryKey entry) {
    _entry = entry;
    _accounts = ref.read(accountsRepositoryProvider);
    _acp = ref.read(acpServiceProvider);
    _ids = ref.read(accountEditorIdsProvider);
    _ownerEpoch = _accounts.state.value.stamp?.ownerEpoch;
    final retention = ref.keepAlive();
    _closeRetention = retention.close;
    _observations.addAll([
      _accounts.state.watch((_) => _catalogChanged()),
      _acp.templates.watch((_) => _publish()),
    ]);
    ref.onDispose(() {
      _finished = true;
      _leaveDecision = null;
      _leaveResolution?.closeObservations();
      _leaveResolution = null;
      _replacement = null;
      _defaultIntent = null;
      _templateIntent = Object();
      releaseAccountDemand(_summaryDemand);
      for (final observation in _observations) {
        observation.cancel();
      }
    });
    return _derive();
  }

  bool get isActive => ref.mounted && !_finished;
  AccountEditorKey? get currentEditor => isActive ? _editor : null;
  bool isEditorCurrent(AccountEditorKey source) =>
      isActive && _editor == source;

  /// A finite decision for this entry's frozen draft, not navigation state.
  Object beginLeaveDecision() {
    final token = _LeaveDecision(
      _editor,
      _editorOwner,
      _editorOwner?.leaveToken,
    );
    if (!isActive) return token;
    _invalidateLeaveDecision();
    cancelPendingSelection();
    _leaveDecision = token;
    return token;
  }

  bool isLeaveDecisionCurrent(Object token) =>
      isActive &&
      identical(_leaveDecision, token) &&
      token is _LeaveDecision &&
      _editor == token.source &&
      identical(_editorOwner, token.owner) &&
      (token.owner == null ||
          (token.owner!.matchesLeaveToken(token.editorToken!) &&
              !token.owner!.leaveBlocked));

  /// Retain only source identities/revisions after the common UI decision.
  /// Existing owners are checked, never initialized by this guard protocol.
  bool resolveLeaveDecision(
    Object token, {
    required AccountEditorKey? source,
    required Object? editorToken,
    AccountModelsViewModel? models,
    Object? compactToken,
    bool discardCompact = false,
  }) {
    if (!isLeaveDecisionCurrent(token) ||
        token is! _LeaveDecision ||
        token.source != source ||
        token.editorToken != editorToken ||
        !_matchesLeaveModels(models, compactToken)) {
      return false;
    }
    _leaveResolution?.closeObservations();
    final resolution = _LeaveResolution(
      token,
      models,
      compactToken,
      discardCompact,
    );
    _leaveResolution = resolution;
    if (source != null) {
      resolution.closeEditorObservation = ref
          .listen(
            accountEditorViewModelProvider(source),
            (_, _) => _revalidateLeaveResolution(resolution),
          )
          .close;
    }
    if (models != null) {
      final account = _leaveAccount!;
      resolution.closeModelsObservation = ref
          .listen(
            accountModelsViewModelProvider(account),
            (_, _) => _revalidateLeaveResolution(resolution),
          )
          .close;
    }
    if (!_isLeaveResolutionCurrent(resolution)) {
      cancelLeaveDecision(token);
      resolution.closeObservations();
      return false;
    }
    return true;
  }

  bool get hasCurrentLeaveDecision {
    final resolution = _leaveResolution;
    return resolution != null && _isLeaveResolutionCurrent(resolution);
  }

  void cancelLeaveDecision(Object token) {
    if (identical(_leaveDecision, token)) _invalidateLeaveDecision();
  }

  AccountDisplayKey? get _leaveAccount =>
      _editor?.target ??
      switch (_entry) {
        EditingAccountEditorEntryKey(:final account) => account,
        CreatingAccountEditorEntryKey() => null,
      };

  bool _matchesLeaveModels(AccountModelsViewModel? models, Object? token) {
    final account = _leaveAccount;
    if (models == null) {
      return token == null &&
          (account == null ||
              account.kind != AccountKind.native ||
              !ref.exists(accountModelsViewModelProvider(account)));
    }
    if (token == null ||
        account == null ||
        account.kind != AccountKind.native) {
      return false;
    }
    final provider = accountModelsViewModelProvider(account);
    return ref.exists(provider) &&
        identical(ref.read(provider.notifier), models) &&
        models.matchesCompactLeaveToken(token) &&
        !models.compactLeaveBlocked;
  }

  bool _isLeaveResolutionCurrent(_LeaveResolution resolution) =>
      identical(_leaveResolution, resolution) &&
      isLeaveDecisionCurrent(resolution.decision) &&
      _matchesLeaveModels(resolution.models, resolution.compactToken);

  void _revalidateLeaveResolution(_LeaveResolution resolution) {
    // A new wait retires the decision permanently, even if that wait later
    // settles without changing the draft revision. This is not a navigation ACK.
    if (identical(_leaveResolution, resolution) &&
        !_isLeaveResolutionCurrent(resolution)) {
      _invalidateLeaveDecision();
    }
  }

  void _invalidateLeaveDecision() {
    _leaveDecision = null;
    final resolution = _leaveResolution;
    _leaveResolution = null;
    resolution?.closeObservations();
  }

  void setStrings(AccountStrings strings) {
    if (!isActive) return;
    _strings = strings;
    _editorOwner?.setStrings(strings);
    _publish();
  }

  /// Only the first call accepts route-entry hints; query-only changes cannot
  /// allocate another editor or append another manual-model entry.
  Future<void> initialize({String? focusModelId, bool addModel = false}) {
    if (!isActive || _initialized) return _loading ?? Future.value();
    _initialized = true;
    // Direct entry uses the existing narrow summary resource too: saved
    // billing and save readiness must not depend on constructing a list page.
    _summaryDemand = _accounts.observeSummaries();
    switch (_entry) {
      case EditingAccountEditorEntryKey(:final account):
        _installEditor(
          AccountEditorKey(
            editorId: _ids.next(),
            target: account,
            creating: false,
            focusModelId: focusModelId,
            addModel: addModel,
          ),
        );
      case CreatingAccountEditorEntryKey():
        break;
    }
    return loadTemplates();
  }

  /// Queries only canonical template resources. Default selection never means
  /// prepare/install/authenticate; a later explicit template choice wins.
  Future<void> loadTemplates() {
    if (!isActive || !_initialized) return Future.value();
    if (_loading case final pending?) return pending;
    final intent = _templateIntent;
    _templatesLoading = true;
    _error = null;
    _publish();
    // Assign the shared future before invoking repository code, including a
    // synchronous before-admission throw or an already-completed query.
    final work = Future<void>(() async {
      if (isActive) await _loadTemplates(intent);
    });
    _loading = work;
    return work;
  }

  Future<void> _loadTemplates(Object intent) async {
    try {
      await Future.wait([_accounts.loadTemplates(), _acp.loadTemplates()]);
      if (!isActive) return;
      if (_editor == null && identical(intent, _templateIntent)) {
        _defaultIntent = intent;
        _selectDefaultIfReady();
      }
    } catch (error) {
      if (isActive && identical(intent, _templateIntent)) {
        _error = safeAccountError(error, _strings);
      }
    } finally {
      if (isActive) {
        _templatesLoading = false;
        _loading = null;
        _publish();
      }
    }
  }

  /// Captures a same-page business replacement, not a navigation intent. The
  /// caller captures its UI decision before awaiting and cancels this token if
  /// a later navigation/selection supersedes it.
  Object? beginTemplateReplacement(AccountEditorKey? source) {
    if (!isActive ||
        !_initialized ||
        _entry is! CreatingAccountEditorEntryKey ||
        _editor != source) {
      return null;
    }
    _invalidateLeaveDecision();
    final owner = _editorOwner;
    final token = _TemplateReplacement(source, owner, owner?.leaveToken);
    _templateIntent = Object();
    _defaultIntent = null;
    _replacement = token;
    return token;
  }

  bool isTemplateReplacementCurrent(AccountEditorKey? source, Object token) =>
      isActive &&
      identical(_replacement, token) &&
      token is _TemplateReplacement &&
      token.source == source &&
      _editor == source &&
      identical(_editorOwner, token.owner) &&
      (token.owner == null ||
          token.owner!.matchesLeaveToken(token.draftToken!));

  void cancelTemplateReplacement(Object token) {
    if (identical(_replacement, token)) cancelPendingSelection();
  }

  /// A newer route request may supersede a pending choice without retiring the
  /// entry or its draft. It also prevents a late initial query creating a draft
  /// after onExit captured an entry with no editor. Query results remain usable.
  void cancelPendingSelection() {
    if (!isActive) return;
    _replacement = null;
    _defaultIntent = null;
    _templateIntent = Object();
  }

  /// Commit only after the caller's save/discard decision and identity checks.
  /// The new identity is installed before retiring the captured old UI owner.
  AccountEditorKey? replaceTemplate({
    required AccountEditorKey? source,
    required AccountTemplateKey template,
    required Object token,
  }) {
    if (!isTemplateReplacementCurrent(source, token)) return null;
    final oldOwner = _editorOwner;
    if (oldOwner?.leaveBlocked == true) return null;
    final next = _newDraft(template);
    if (next == null) return null;
    _replacement = null;
    _templateIntent = Object();
    _defaultIntent = null;
    _installEditor(next);
    oldOwner?.finish();
    return isEditorCurrent(next) ? next : null;
  }

  AccountEditorKey? _newDraft(AccountTemplateKey template) {
    final source = _accounts.state.value;
    final exists = template.kind == AccountKind.native
        ? source.templates.template(template.id) != null
        : _acp.templates.value.templates.any(
            (value) => value.provider.wire == template.id,
          );
    if (!exists || !source.loaded || source.stale) {
      _error = _strings[exists ? 'stale' : 'unknownTemplate'];
      _publish();
      return null;
    }
    final used = {
      for (final account in source.accounts)
        if (displayIdentity(account.identity).kind == template.kind)
          account.identity.accountId,
    };
    var id = template.id;
    for (var suffix = 2; used.contains(id); suffix++) {
      id = '${template.id}-$suffix';
    }
    return AccountEditorKey(
      editorId: _ids.next(),
      target: AccountDisplayKey(kind: template.kind, id: id),
      template: template,
      creating: true,
    );
  }

  void _installEditor(AccountEditorKey next) {
    _invalidateLeaveDecision();
    _editor = next;
    _error = null;
    final owner = ref.read(accountEditorViewModelProvider(next).notifier);
    if (!isEditorCurrent(next)) {
      owner.finish();
      return;
    }
    _editorOwner = owner;
    owner.setStrings(_strings);
    _publish();
  }

  void _selectDefaultIfReady() {
    if (!isActive ||
        _entry is! CreatingAccountEditorEntryKey ||
        _editor != null ||
        _defaultIntent == null ||
        !identical(_defaultIntent, _templateIntent) ||
        !_accounts.state.value.loaded ||
        _accounts.state.value.stale) {
      return;
    }
    final native = _accounts.state.value.templates.templates.firstOrNull;
    final acp = _acp.templates.value.templates.firstOrNull;
    final template = native != null
        ? AccountTemplateKey(kind: AccountKind.native, id: native.id)
        : acp != null
        ? AccountTemplateKey(kind: AccountKind.acp, id: acp.provider.wire)
        : null;
    if (template == null) {
      _error = _strings['unknownTemplate'];
      return;
    }
    final next = _newDraft(template);
    if (next != null) {
      _defaultIntent = null;
      _installEditor(next);
    }
  }

  void _catalogChanged() {
    if (!isActive) return;
    final epoch = _accounts.state.value.stamp?.ownerEpoch;
    if (epoch != null && _ownerEpoch != null && epoch != _ownerEpoch) {
      _invalidateLeaveDecision();
      _replacement = null;
      _defaultIntent = null;
      _templateIntent = Object();
    }
    _ownerEpoch = epoch ?? _ownerEpoch;
    _selectDefaultIfReady();
    _publish();
  }

  /// Actual entry disposal, never a guard's permission result. Late queries or
  /// selections cannot create another editor after this idempotent retirement.
  void finish() {
    if (!isActive) return;
    final resolution = _leaveResolution;
    final discardResolution =
        resolution != null &&
            resolution.discardCompact &&
            _isLeaveResolutionCurrent(resolution)
        ? resolution
        : null;
    final models = discardResolution?.models;
    final compactToken = discardResolution?.compactToken;
    final owner = _editorOwner;
    _finished = true;
    _invalidateLeaveDecision();
    _replacement = null;
    _defaultIntent = null;
    _templateIntent = Object();
    _editorOwner = null;
    if (models != null &&
        compactToken != null &&
        models.matchesCompactLeaveToken(compactToken)) {
      models.discardCompactDrafts(compactToken);
    }
    releaseAccountDemand(_summaryDemand);
    _summaryDemand = null;
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    owner?.finish();
    _closeRetention?.call();
    _closeRetention = null;
  }

  AccountEditorSessionState _derive() => AccountEditorSessionState(
    entry: _entry,
    editor: _editor,
    templatesLoading: _templatesLoading,
    error:
        _error ??
        (_editor == null ? _accounts.state.value.failure?.message : null),
    templates: [
      for (final template in _acp.templates.value.templates)
        AccountTemplatePresentation(
          key: AccountTemplateKey(
            kind: AccountKind.acp,
            id: template.provider.wire,
          ),
          name: template.displayName,
          content: const AccountTemplateContent.acp(),
          iconKey: template.iconKey,
          description: template.description,
        ),
      if (_accounts.state.value.templates.revision.isNotEmpty)
        for (final template in _accounts.state.value.templates.templates)
          AccountTemplatePresentation(
            key: AccountTemplateKey(kind: AccountKind.native, id: template.id),
            name: template.displayName,
            content: AccountTemplateContent.native(
              defaultBilling: displayBilling(template.defaultBillingKind),
              protocolLabel: template.protocol,
              defaultEndpoint: template.baseUrl,
              supportsModelDiscovery: template.supportsModelDiscovery,
              supportsUsageQuery: template.supportsUsageQuery,
            ),
            iconKey: template.iconKey,
            description: template.description,
          ),
    ],
  );

  void _publish() {
    if (isActive) state = AsyncData(_derive());
  }
}
