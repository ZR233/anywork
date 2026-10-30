import 'dart:async';
import 'dart:math';

import 'package:anywork_client/accounts.dart'
    hide
        AccountAuthenticationMethod,
        ChatGptAccountInfo,
        ChatGptLoginFailureCode,
        ChatGptLoginPhase,
        ChatGptLoginSnapshot;
import 'package:anywork_client/accounts.dart'
    as account_domain
    show
        AccountAuthenticationMethod,
        ChatGptAccountInfo,
        ChatGptLoginFailureCode,
        ChatGptLoginPhase,
        ChatGptLoginSnapshot;
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart'
    show DraftStamp, OperationPhase, OperationState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import 'account_operation_result.dart';
import 'account_projection.dart';
import 'account_models_view_model.dart';
import 'acp_account_view_model.dart';
import 'native_account_draft.dart';
import 'acp_command_notice.dart';

part 'account_editor_view_model.g.dart';

/// One form owns raw input, baseline, dirty and revision. No Widget controller
/// or canonical mirror is used to decide whether a save completed this draft.
@riverpod
class AccountEditorViewModel extends _$AccountEditorViewModel {
  late AccountEditorKey _key;
  late AccountsRepository _accounts;
  late ModelsRepository _models;
  late AcpService _acp;
  AccountStrings _strings = const AccountStrings.empty();
  NativeAccountDraft? _raw;
  NativeAccountDraft? _baseline;
  NativeAccountDetails? _initialNative;
  AcpAccountSettingsView? _initialAcp;
  AccountAcpKey? _acpKey;
  String? _acpName;
  String? _baselineAcpName;
  bool _created = false;
  bool _saving = false;
  bool _finished = false;
  bool _unknownResult = false;
  bool _setDefaultOnCreate = false;
  bool _baselineSetDefaultOnCreate = false;
  String? _baselineOwnerEpoch;
  bool _baselineInvalidated = false;
  int _revision = 0;
  int _rowSequence = 0;
  String? _addModelEntryEditorKey;
  String? _error;
  AcpCommandNotice? _configurationNotice;
  void Function()? _closeRetention;
  ValueObservation<AccountResource<AccountDetails>>? _details;
  AccountAcpKey? _subscribedAcpKey;
  void Function()? _closeAcpListener;
  AccountDemand? _detailDemand;
  AccountDemand? _modelDemand;
  AccountDemand? _chatGptLoginDemand;
  AccountDemand? _chatGptIntentDemand;
  ValueObservation<AccountResource<account_domain.ChatGptLoginSnapshot>>?
  _chatGptLoginValue;
  Observation? _chatGptLoginWatch;
  account_domain.ChatGptLoginSnapshot? _chatGptLoginSnapshot;
  Future<void>? _chatGptLoginStart;
  String? _authenticationError;
  String? _autoOpenedChatGptLoginId;

  @override
  FutureOr<AccountEditorViewState> build(AccountEditorKey key) {
    _key = key;
    _accounts = ref.read(accountsRepositoryProvider);
    _models = ref.read(modelsRepositoryProvider);
    _acp = ref.read(acpServiceProvider);
    final retention = ref.keepAlive();
    _closeRetention = retention.close;
    final observations = <Observation>[
      _accounts.state.watch((_) => _changed()),
      _models.state.watch((_) => _changed()),
      _acp.templates.watch((_) => _changed()),
      _acp.install.watch((_) => _publish()),
    ];
    if (!key.creating) {
      _detailDemand = _accounts.observeDetails(domainIdentity(key.target));
      _details = _accounts.details(domainIdentity(key.target));
      observations.add(_details!.watch((_) => _changed()));
      if (key.target.kind == AccountKind.native) {
        _modelDemand = _models.observeAccount(
          NativeAccountIdentity(key.target.id),
        );
      }
    }
    ref.onDispose(() {
      final login = _raw?.loginId;
      final cancelLogin = login != null;
      _chatGptLoginWatch?.cancel();
      _releaseChatGptLogin();
      if (cancelLogin) {
        unawaited(_cancelChatGptLogin(login));
      }
      _closeAcpListener?.call();
      releaseAccountDemand(_detailDemand);
      releaseAccountDemand(_modelDemand);
      for (final observation in observations) {
        observation.cancel();
      }
    });
    _initialize();
    return _derive();
  }

  Future<void> loadTemplates() async {
    try {
      await Future.wait([_accounts.loadTemplates(), _acp.loadTemplates()]);
    } catch (error) {
      if (ref.mounted && !_finished) {
        _error = safeAccountError(error, _strings);
        _publish();
      }
    }
  }

  /// Diagnostic read of this editor's existing subscription only. A new form
  /// without an observed canonical target remains unknown.
  AccountResource<AccountDetails>? readObservedDetails() => _details?.value;

  void retryObservation() {
    if (_details == null) {
      unawaited(loadTemplates());
      return;
    }
    releaseAccountDemand(_detailDemand);
    _detailDemand = _accounts.observeDetails(domainIdentity(_key.target));
    if (_key.target.kind == AccountKind.native) {
      releaseAccountDemand(_modelDemand);
      _modelDemand = _models.observeAccount(
        NativeAccountIdentity(_key.target.id),
      );
    }
  }

  void setStrings(AccountStrings strings) {
    _strings = strings;
    _publish();
  }

  Future<void> prepareSelectedTemplate() async {
    final key = _acpKey;
    if (!_key.creating || key == null || _finished) return;
    await ref.read(acpAccountViewModelProvider(key).notifier).prepare();
  }

  void _initialize() {
    if (_raw != null || _acpName != null) return;
    final detail = _details?.value;
    if (_key.creating) {
      final templateKey = _key.template;
      if (_key.target.kind == AccountKind.native) {
        final template = _accounts.state.value.templates.template(
          templateKey?.id ?? '',
        );
        if (template != null) {
          _raw = NativeAccountDraft.fromTemplate(template);
          _baseline = _raw;
        }
      } else {
        final template = _acp.templates.value.templates
            .where((value) => value.provider.wire == templateKey?.id)
            .firstOrNull;
        if (template != null) {
          _acpName = template.displayName;
          _baselineAcpName = _acpName;
          _acpKey = AccountAcpKey(
            target: _key.target,
            providerId: template.provider.wire,
            connectionRevision: 0,
            editorId: _key.editorId,
            creating: true,
          );
        }
      }
    } else if (detail?.loaded == true) {
      switch (detail!.value) {
        case NativeAccountDetails native:
          final configuration =
              _models.state.value.configurations[native.identity];
          if (configuration?.loaded != true) return;
          _initialNative = native;
          _raw =
              NativeAccountDraft.fromDetails(
                native,
                configuration!.value?.connections ?? const {},
              ).withBilling(
                _accounts.state.value
                    .account(native.identity)
                    ?.billingKindOverride,
              );
          _baseline = _raw;
        case AcpAccountDetails(:final account):
          _initialAcp = account;
          _acpName = account.name;
          _baselineAcpName = account.name;
          _acpKey = AccountAcpKey(
            target: _key.target,
            providerId: account.provider.wire,
            connectionRevision: account.connectionRevision,
            editorId: _key.editorId,
          );
        default:
          break;
      }
    }
    if (_raw != null || _acpName != null) {
      _baselineOwnerEpoch = _accounts.state.value.stamp?.ownerEpoch;
    }
    _observeAcp();
  }

  void _observeAcp() {
    final acpKey = _acpKey;
    if (acpKey != null && _subscribedAcpKey != acpKey) {
      _closeAcpListener?.call();
      _subscribedAcpKey = acpKey;
      _closeAcpListener = ref
          .listen(acpAccountViewModelProvider(acpKey), (_, _) => _publish())
          .close;
    }
  }

  void _observeCreatedDetails() {
    if (_details != null) return;
    _detailDemand = _accounts.observeDetails(domainIdentity(_key.target));
    _details = _accounts.details(domainIdentity(_key.target));
    final observation = _details!.watch((_) => _changed());
    _modelDemand = _key.target.kind == AccountKind.native
        ? _models.observeAccount(NativeAccountIdentity(_key.target.id))
        : null;
    ref.onDispose(() {
      observation.cancel();
    });
  }

  bool get _dirty =>
      !_finished &&
      ((_key.creating && !_created) ||
          (_key.creating &&
              _key.target.kind == AccountKind.native &&
              _setDefaultOnCreate != _baselineSetDefaultOnCreate) ||
          (_raw != null &&
              _baseline != null &&
              !_raw!.sameFields(_baseline!)) ||
          (_acpName != null && _acpName != _baselineAcpName));
  bool get _stale =>
      _baselineInvalidated ||
      _accounts.state.value.stale ||
      _details?.value.stale == true ||
      (_initialAcp != null &&
          _details?.value.value is AcpAccountDetails &&
          (_details!.value.value as AcpAccountDetails)
                  .account
                  .connectionRevision !=
              _initialAcp!.connectionRevision) ||
      (_key.target.kind == AccountKind.native &&
          !_key.creating &&
          _models
                  .state
                  .value
                  .configurations[NativeAccountIdentity(_key.target.id)]
                  ?.loaded !=
              true);

  void changeField(NativeAccountField field, String raw) {
    final draft = _raw;
    if (draft == null || _finished) return;
    _raw = draft.field(field, raw);
    _revision++;
    _publish();
  }

  void changeAuthentication(AccountAuthenticationMethod method) {
    final authentication = switch (method) {
      AccountAuthenticationMethod.apiKey =>
        account_domain.AccountAuthenticationMethod.apiKey,
      AccountAuthenticationMethod.chatGpt =>
        account_domain.AccountAuthenticationMethod.chatGpt,
    };
    final draft = _raw;
    if (draft == null ||
        _finished ||
        draft.authentication == authentication ||
        draft.templateId != 'openai') {
      return;
    }
    final loginId = draft.loginId;
    if (loginId != null) {
      unawaited(_cancelChatGptLogin(loginId));
    }
    _releaseChatGptLogin();
    _authenticationError = null;
    _raw = draft.withAuthentication(authentication);
    _revision++;
    _publish();
  }

  String? get chatGptAuthorizationUrl => _currentChatGptLogin?.authorizationUrl;

  String? claimAuthorizationUrlForAutomaticOpen() {
    final login = _currentChatGptLogin;
    if (login == null ||
        login.phase != account_domain.ChatGptLoginPhase.awaitingBrowser) {
      return null;
    }
    final url = login.authorizationUrl;
    if (url == null || _autoOpenedChatGptLoginId == login.loginId) return null;
    _autoOpenedChatGptLoginId = login.loginId;
    return url;
  }

  bool get _isChatGptLoginActive {
    final phase = _currentChatGptLogin?.phase;
    return phase != null &&
        phase != account_domain.ChatGptLoginPhase.succeeded &&
        phase != account_domain.ChatGptLoginPhase.cancelled &&
        phase != account_domain.ChatGptLoginPhase.failed;
  }

  account_domain.ChatGptLoginSnapshot? get _currentChatGptLogin {
    final draft = _raw;
    final snapshot = _chatGptLoginSnapshot;
    if (draft?.loginId == null ||
        snapshot == null ||
        snapshot.loginId != draft!.loginId ||
        snapshot.editorId != _key.editorId ||
        snapshot.accountId != _key.target.id) {
      return null;
    }
    return snapshot;
  }

  Future<void> startChatGptLogin() async {
    final draft = _raw;
    if (draft == null ||
        _finished ||
        _saving ||
        draft.templateId != 'openai' ||
        draft.authentication !=
            account_domain.AccountAuthenticationMethod.chatGpt) {
      return;
    }
    final current = _currentChatGptLogin;
    if (_chatGptLoginStart != null ||
        (current != null && !current.isTerminal)) {
      return;
    }
    final retryIdempotentStart =
        draft.loginId != null &&
        current == null &&
        _authenticationError != null;
    _releaseChatGptLogin(releaseIntent: !retryIdempotentStart);
    final loginId = retryIdempotentStart ? draft.loginId! : _newLoginId();
    _raw = draft.withAuthentication(
      account_domain.AccountAuthenticationMethod.chatGpt,
      loginId: loginId,
    );
    _authenticationError = null;
    try {
      // Register a local typed read model before dispatch. The Rust pull demand
      // is admitted only after start returns a canonical stamped reply.
      _chatGptIntentDemand ??= _accounts.registerChatGptLogin(
        loginId: loginId,
        editorId: _key.editorId,
        accountId: _key.target.id,
      );
      _chatGptLoginValue = _accounts.chatGptLogin(loginId);
      _chatGptLoginWatch = _chatGptLoginValue!.watch((_) {
        _acceptChatGptLoginObservation(loginId);
      });
      _acceptChatGptLoginObservation(loginId);
      _revision++;
      _publish();
      final pending = _accounts.startChatGptLogin(
        loginId: loginId,
        editorId: _key.editorId,
        accountId: _key.target.id,
      );
      _chatGptLoginStart = pending.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      await pending;
      _acceptChatGptLoginObservation(loginId);
      _chatGptLoginDemand ??= _accounts.observeChatGptLogin(loginId);
    } catch (error) {
      if (ref.mounted && !_finished && _raw?.loginId == loginId) {
        _authenticationError = safeAccountError(error, _strings);
        _publish();
      }
    } finally {
      _chatGptLoginStart = null;
    }
  }

  Future<void> cancelChatGptLogin() async {
    final loginId = _raw?.loginId;
    if (loginId == null || !_isChatGptLoginActive) return;
    await _cancelChatGptLogin(loginId);
  }

  Future<void> _cancelChatGptLogin(String loginId) async {
    final starting = _chatGptLoginStart;
    if (starting != null) {
      await starting.catchError((Object _) {});
    }
    try {
      await _accounts.cancelChatGptLogin(
        loginId: loginId,
        editorId: _key.editorId,
        accountId: _key.target.id,
      );
      _acceptChatGptLoginObservation(loginId);
    } catch (error) {
      if (ref.mounted && !_finished && _raw?.loginId == loginId) {
        _authenticationError = safeAccountError(error, _strings);
        _publish();
      }
    }
  }

  void authorizationOpenFailed() {
    if (_finished) return;
    _authenticationError = _strings['chatGptOpenLinkFailed'];
    _publish();
  }

  void usageOpenFailed() {
    if (_finished) return;
    _authenticationError = _strings['chatGptOpenUsageFailed'];
    _publish();
  }

  void _releaseChatGptLogin({bool releaseIntent = true}) {
    _chatGptLoginWatch?.cancel();
    _chatGptLoginWatch = null;
    releaseAccountDemand(_chatGptLoginDemand);
    _chatGptLoginDemand = null;
    if (releaseIntent) {
      releaseAccountDemand(_chatGptIntentDemand);
      _chatGptIntentDemand = null;
    }
    _chatGptLoginValue = null;
    _chatGptLoginSnapshot = null;
  }

  void _acceptChatGptLoginObservation(String loginId) {
    final resource = _chatGptLoginValue?.value;
    final snapshot = resource?.value;
    final failure = resource?.failure;
    if (_raw?.loginId == loginId && failure != null) {
      _authenticationError = safeAccountError(failure, _strings);
      if (ref.mounted && !_finished) _publish();
      return;
    }
    if (_raw?.loginId != loginId ||
        snapshot == null ||
        snapshot.loginId != loginId ||
        snapshot.editorId != _key.editorId ||
        snapshot.accountId != _key.target.id) {
      return;
    }
    _chatGptLoginSnapshot = snapshot;
    _authenticationError = null;
    if (ref.mounted && !_finished) _publish();
  }

  static String _newLoginId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  void changeName(String raw) {
    if (_finished) return;
    _acpName = raw;
    _revision++;
    _publish();
  }

  void changeBilling(AccountBilling? value) {
    if (_raw == null || _finished) return;
    _raw = _raw!.withBilling(value == null ? null : domainBilling(value));
    _revision++;
    _publish();
  }

  void changeSetDefaultOnCreate(bool value) {
    if (!_key.creating ||
        _key.target.kind != AccountKind.native ||
        _finished ||
        _saving ||
        _unknownResult ||
        value == _setDefaultOnCreate) {
      return;
    }
    _setDefaultOnCreate = value;
    _revision++;
    _publish();
  }

  void addModel() {
    if (_raw == null || _finished) return;
    _appendModelRow();
    _publish();
  }

  /// An entry request is consumed by this editor, not by a Connector mount.
  /// Removing its row never authorizes an automatic replacement on a remount.
  String? addModelEntryEditorKey() => _addModelEntryEditorKey;

  String? consumeAddModelEntry({required bool requested}) {
    if (_finished || !requested) return null;
    if (_addModelEntryEditorKey != null) return _addModelEntryEditorKey;
    if (_raw == null || _saving || _stale) return null;
    _addModelEntryEditorKey = _appendModelRow();
    _publish();
    return _addModelEntryEditorKey;
  }

  String _appendModelRow() {
    final editorKey = '${_key.editorId}-row-${++_rowSequence}';
    _raw = _raw!.withRows([
      ..._raw!.rows,
      ManualModelDraft(editorKey: editorKey),
    ]);
    _revision++;
    return editorKey;
  }

  void changeModel(
    String editorKey, {
    ManualModelField? field,
    String? raw,
    AccountWireApi? api,
    AccountConnection? connection,
  }) {
    final draft = _raw;
    if (draft == null || _finished) return;
    _raw = draft.withRows([
      for (final row in draft.rows)
        if (row.editorKey == editorKey)
          row.change(field: field, raw: raw, api: api, mode: connection)
        else
          row,
    ]);
    _revision++;
    _publish();
  }

  bool isSavedModel(String editorKey) =>
      _raw?.rows.any(
        (row) => row.editorKey == editorKey && row.savedId != null,
      ) ==
      true;
  String modelName(String editorKey) =>
      _raw?.rows.where((row) => row.editorKey == editorKey).firstOrNull?.name ??
      editorKey;
  Future<bool> removeModel(
    String editorKey, {
    AccountModelsViewModel? modelsOwner,
    Object? expectedCompactToken,
  }) async {
    final row = _raw?.rows
        .where((row) => row.editorKey == editorKey)
        .firstOrNull;
    if (row == null || _saving || _finished || _unknownResult) return false;
    final savedRow = row.savedId != null;
    final sourceToken = leaveToken();
    if (savedRow) {
      // Only compare the captured resource with its existing typed family.
      // Never create/adopt a latest Models owner to complete an old action.
      final provider = accountModelsViewModelProvider(_key.target);
      if (modelsOwner == null ||
          expectedCompactToken == null ||
          !modelsOwner.canRemove(expectedToken: expectedCompactToken) ||
          !ref.exists(provider) ||
          !identical(ref.read(provider.notifier), modelsOwner)) {
        return false;
      }
    }
    if (savedRow) {
      _saving = true;
      _error = null;
    }
    try {
      if (savedRow) {
        // The unique Models admission installs its deleting qualification before
        // either owner's notification can re-enter an input handler.
        final pending = modelsOwner!.removeManual(
          row.savedId!,
          expectedToken: expectedCompactToken!,
        );
        _publish();
        final result = await pending;
        if (result == null || !_acceptSettled(result)) return false;
        if (!matchesLeaveToken(sourceToken) ||
            !identical(
              _raw?.rows
                  .where((value) => value.editorKey == editorKey)
                  .firstOrNull,
              row,
            )) {
          return false;
        }
        _baseline = _baseline?.withRows([
          for (final value in _baseline!.rows)
            if (value.savedId != row.savedId) value,
        ]);
      }
      _raw = _raw?.withRows([
        for (final value in _raw!.rows)
          if (value.editorKey != editorKey) value,
      ]);
      _revision++;
      _publish();
      return true;
    } catch (error) {
      if (ref.mounted && !_finished) {
        _error = safeAccountError(error, _strings);
        _publish();
      }
      return false;
    } finally {
      if (savedRow && ref.mounted && !_finished) {
        _saving = false;
        _publish();
      }
    }
  }

  /// The submitted revision and all input intent are captured before awaiting.
  /// Success of an earlier revision never clears later input or allows leaving.
  Future<bool> save() async {
    if (!_derive().canSave || _saving || _finished) return false;
    final revision = _revision;
    final raw = _raw;
    final baseline = _baseline;
    final acpName = _acpName;
    final acpKey = _acpKey;
    final target = _key.target;
    final creating = _key.creating;
    final wasCreating = creating && !_created;
    final defaultIntent = _setDefaultOnCreate;
    final defaultBaseline = _baselineSetDefaultOnCreate;
    final stamp = DraftStamp(draftId: _key.editorId, revision: revision);
    var settingDefault = false;
    _saving = true;
    _error = null;
    _configurationNotice = null;
    _publish();
    try {
      if (raw != null && baseline != null) {
        final identity = NativeAccountIdentity(target.id);
        // A retry of only the follow-up intent must not patch or create again.
        if (wasCreating || !raw.sameFields(baseline)) {
          final result = wasCreating
              ? await _accounts.create(
                  raw.create(identity, editorId: _key.editorId),
                  draft: stamp,
                )
              : await _accounts.patch(
                  raw.patch(identity, baseline, editorId: _key.editorId),
                  draft: stamp,
                );
          if (!await _accept(result)) return false;
          _created = true;
          final savedRows = [for (final row in raw.rows) row.saved()];
          // Mark only declaration identity, never replace newer field contents.
          // If an unsaved id was changed while saving, retain the newly persisted
          // row alongside the newer raw row. Removing it now requires confirmation.
          final currentRows = [...?_raw?.rows];
          for (final saved in savedRows) {
            final index = currentRows.indexWhere(
              (row) => row.editorKey == saved.editorKey,
            );
            if (index >= 0 && currentRows[index].id.trim() == saved.id.trim()) {
              currentRows[index] = currentRows[index].saved();
            } else {
              currentRows.add(
                saved.saved(key: '${saved.editorKey}-persisted-${saved.id}'),
              );
            }
          }
          _raw = _raw?.withRows(currentRows);
          // Configuration is already saved even if a following narrow step fails.
          _baseline = NativeAccountDraft(
            name: raw.name,
            endpoint: raw.endpoint,
            credential: raw.credential,
            protocol: raw.protocol,
            templateId: raw.templateId,
            rows: [
              for (final row in savedRows)
                row.change(
                  mode: wasCreating
                      ? row.connection
                      : baseline.rows
                                .where((old) => old.id == row.id)
                                .firstOrNull
                                ?.connection ??
                            AccountConnection.automatic,
                ),
            ],
            billing: wasCreating ? raw.billing : baseline.billing,
            authentication: raw.authentication,
            loginId: null,
            apiEndpoint: raw.apiEndpoint,
            mustEnterApiKey: raw.mustEnterApiKey,
          );
          if (_raw?.loginId == raw.loginId) {
            _raw = _raw?.withAuthentication(raw.authentication);
          }
          if (raw.loginId != null) _releaseChatGptLogin();
          // Opening a display subscription may fail independently. Record the
          // already-durable configuration first, including saved model identity.
          _observeCreatedDetails();
          if (!wasCreating) {
            for (final row in raw.rows) {
              final old = baseline.rows
                  .where((value) => value.id == row.id)
                  .firstOrNull;
              if (row.connection ==
                  (old?.connection ?? AccountConnection.automatic)) {
                continue;
              }
              final connectionResult = await _models.setConnection(
                AccountModelIdentity(account: identity, modelId: row.id.trim()),
                switch (row.connection) {
                  AccountConnection.automatic =>
                    const ModelConnectionIntent.clear(),
                  AccountConnection.http => const ModelConnectionIntent.set(
                    AccountConnectionMode.http,
                  ),
                  AccountConnection.webSocket =>
                    const ModelConnectionIntent.set(
                      AccountConnectionMode.webSocket,
                    ),
                },
              );
              if (!await _accept(connectionResult)) return false;
              _baseline = _baseline!.withRows([
                for (final value in _baseline!.rows)
                  value.id == row.id
                      ? value.change(mode: row.connection)
                      : value,
              ]);
            }
            if (raw.billing != baseline.billing) {
              if (!await _accept(
                await _accounts.setBillingKind(identity, raw.billing),
              )) {
                return false;
              }
            }
          }
          _baseline = raw
              .withRows(savedRows)
              .withAuthentication(raw.authentication);
        }
        if (creating) {
          if (defaultIntent && !defaultBaseline) {
            settingDefault = true;
            if (!await _accept(await _accounts.setDefault(identity))) {
              if (ref.mounted && !_finished) {
                _error =
                    '${_strings['createdDefaultIncomplete']} ${_error ?? _strings['saveFailed']}';
              }
              return false;
            }
            settingDefault = false;
          }
          // Settle only the submitted local preference, never later form edits.
          // Opting out does not undo a default route already saved earlier.
          _baselineSetDefaultOnCreate = defaultIntent;
        }
      } else if (acpKey != null && acpName != null) {
        final provider = AcpProviderView.fromWire(acpKey.providerId)!;
        final command = AcpAccountUpdateView(
          accountId: target.id,
          name: acpName.trim(),
          provider: provider,
        );
        if (_key.creating && !_created) {
          final result = await _acp.saveAndConnect(command, draft: stamp);
          if (!ref.mounted || _finished || _baselineInvalidated) return false;
          if (!await _accept(result.operation)) return false;
          // The Client supplies typed saved details only for this confirmed save.
          final saved = result.saved!;
          _created = true;
          _baselineAcpName = acpName;
          _initialAcp = saved;
          _observeCreatedDetails();
          _acpKey = AccountAcpKey(
            target: _key.target,
            providerId: saved.provider.wire,
            connectionRevision: saved.connectionRevision,
            editorId: _key.editorId,
          );
          _observeAcp();
          if (result.checkFailure != null) {
            _error =
                '${_strings['savedConnectionFailed']} ${result.checkFailure!.message}';
            return false;
          }
        } else {
          if (!await _accept(await _acp.save(command, draft: stamp))) {
            return false;
          }
          _baselineAcpName = acpName;
        }
      }
      return ref.mounted && !_finished && _revision == revision && !_dirty;
    } catch (error) {
      if (ref.mounted && !_finished) {
        if (_initialAcp case final account?) {
          _configurationNotice = AcpCommandNotice(
            kind: AcpCommandNoticeKind.configuration,
            summary: safeAccountError(error, _strings),
            accountId: account.accountId,
            connectionRevision: account.connectionRevision,
          );
        } else {
          final message = safeAccountError(error, _strings);
          _error = settingDefault
              ? '${_strings['createdDefaultIncomplete']} $message'
              : message;
        }
      }
      return false;
    } finally {
      if (ref.mounted && !_finished) {
        _saving = false;
        _publish();
      }
    }
  }

  Future<bool> _accept(OperationState result) async {
    if (!ref.mounted || _finished) return false;
    final settled = await observeAccountOperation(ref, result);
    return settled != null && _acceptSettled(settled);
  }

  // A delegated deletion is already settled once by its admitting Models owner.
  // Reusing the same acceptance logic must not look up a later board snapshot.
  bool _acceptSettled(OperationState settled) {
    if (!ref.mounted || _finished) return false;
    _unknownResult =
        settled.failurePhase == OperationPhase.unknownOutcome ||
        settled.failurePhase == OperationPhase.syncFailed ||
        (settled.failurePhase == null && !operationSaved(settled));
    _error = operationMessage(settled, _strings);
    return !_baselineInvalidated && operationSaved(settled);
  }

  /// UI supplies only the user's choice. A permission result never retires the
  /// form: the actual route-entry disposal or template commit calls finish.
  bool hasUnconfirmedSave() => _unknownResult;
  bool leaveBlocked() => _saving;
  Object leaveToken() => (_revision, _baselineInvalidated);
  bool matchesLeaveToken(Object token) =>
      ref.mounted && !_finished && token == leaveToken();

  Future<bool> requestLeave(AccountLeaveChoice choice) async {
    if (_saving || _finished || choice == AccountLeaveChoice.cancel) {
      return false;
    }
    if (choice == AccountLeaveChoice.save) {
      if (_unknownResult || (_dirty && !await save())) return false;
    } else if (choice == AccountLeaveChoice.discard) {
      final loginId = _raw?.loginId;
      if (loginId != null) {
        await _cancelChatGptLogin(loginId);
      }
      final draft = _raw;
      if (draft?.loginId != null) {
        _raw = draft!.withAuthentication(draft.authentication);
        _releaseChatGptLogin();
        _revision++;
        _publish();
      }
    }
    return true;
  }

  /// Called only on actual entry removal or committed template replacement. It
  /// releases local retention, never domain preparation/authentication/writes.
  void finish() {
    if (_finished) return;
    final login = _raw?.loginId;
    if (login != null) {
      unawaited(_cancelChatGptLogin(login));
    }
    _releaseChatGptLogin();
    _finished = true;
    final key = _acpKey;
    if (key != null && ref.exists(acpAccountViewModelProvider(key))) {
      ref.read(acpAccountViewModelProvider(key).notifier).finish();
    }
    _closeRetention?.call();
    _closeRetention = null;
  }

  AccountEditorViewState presentation({
    AcpAccountPresentation? panel,
    AccountCatalogPresentation? catalog,
  }) {
    final value = _derive();
    if (value.native != null &&
        catalog != null &&
        (!_key.creating || _created)) {
      return value.copyWith(
        native: value.native!.copyWith(
          declaredModels: catalog.models
              .where((model) => model.origin != AccountModelOrigin.manual)
              .map((model) => model.copyWith(compact: null))
              .toList(),
        ),
      );
    }
    return value.acp == null || panel == null
        ? value
        : value.copyWith(acp: value.acp!.copyWith(preparation: panel));
  }

  AccountEditorViewState _derive() {
    final draft = _raw;
    final catalog = _accounts.state.value.templates;
    final template = draft?.templateId == null
        ? null
        : catalog.template(draft!.templateId!);
    final summary = _accounts.state.value.account(domainIdentity(_key.target));
    final unknownTemplate =
        draft?.templateId != null &&
        catalog.revision.isNotEmpty &&
        template == null;
    final validation =
        draft?.validate(_strings) ??
        (_acpName?.trim().isEmpty == true ? _strings['required'] : null);
    final login = _currentChatGptLogin;
    final keepsSavedChatGpt =
        (!_key.creating || _created) &&
        _baseline?.authentication ==
            account_domain.AccountAuthenticationMethod.chatGpt &&
        draft?.authentication ==
            account_domain.AccountAuthenticationMethod.chatGpt &&
        draft?.loginId == null;
    final chatGptLoginReady =
        login?.phase == account_domain.ChatGptLoginPhase.succeeded &&
        login?.account?.planUsageEnabled == true;
    final authenticationReady = draft == null
        ? true
        : draft.authentication ==
              account_domain.AccountAuthenticationMethod.apiKey
        ? !(draft.mustEnterApiKey && draft.credential.trim().isEmpty)
        : keepsSavedChatGpt || chatGptLoginReady;
    final authenticationValidation =
        !authenticationReady &&
            draft.authentication ==
                account_domain.AccountAuthenticationMethod.apiKey
        ? _strings['chatGptApiKeyRequired']
        : null;
    final isReady = draft != null || _acpName != null;
    final acpKey = _acpKey;
    final prepared =
        acpKey != null &&
        ref.exists(acpAccountViewModelProvider(acpKey)) &&
        ref
                .read(acpAccountViewModelProvider(acpKey))
                .asData
                ?.value
                .preparedForEditor ==
            true;
    final canSave =
        isReady &&
        _accounts.state.value.loaded &&
        (draft?.templateId == null || catalog.revision.isNotEmpty) &&
        _dirty &&
        !_saving &&
        !_unknownResult &&
        !_stale &&
        !unknownTemplate &&
        validation == null &&
        authenticationReady &&
        (acpKey == null || !_key.creating || _created || prepared);
    final current = _details?.value.value;
    final currentNative = current is NativeAccountDetails ? current : null;
    final configurationError = current is AcpAccountDetails
        ? visibleAcpCommandNotice(
            _configurationNotice,
            current.account,
            const AcpUncheckedState(),
          )?.summary
        : null;
    final error = _stale
        ? _strings['stale']
        : _error ??
              _authenticationError ??
              configurationError ??
              (unknownTemplate ? _strings['unknownTemplate'] : null) ??
              (_key.target.kind == AccountKind.native
                  ? _models
                        .state
                        .value
                        .configurations[NativeAccountIdentity(_key.target.id)]
                        ?.failure
                        ?.message
                  : null) ??
              (!isReady &&
                      _key.creating &&
                      (_key.target.kind == AccountKind.native
                          ? catalog.revision.isNotEmpty
                          : _acp.templates.value.isUsable)
                  ? _strings['unknownTemplate']
                  : null) ??
              _details?.value.failure?.message;
    return AccountEditorViewState(
      key: _key,
      acpKey: acpKey,
      loading: !isReady && error == null,
      dirty: _dirty,
      saving: _saving,
      canSave: canSave,
      draftRevision: _revision,
      stale: _stale,
      error: error,
      native: draft == null
          ? null
          : NativeAccountEditorPresentation(
              editorId: _key.editorId,
              accountKey: _key.creating && !_created ? null : _key.target,
              templateKey: AccountTemplateKey(
                kind: AccountKind.native,
                id: draft.templateId ?? '',
              ),
              templates: [
                for (final value in catalog.templates)
                  AccountTemplatePresentation(
                    key: AccountTemplateKey(
                      kind: AccountKind.native,
                      id: value.id,
                    ),
                    name: value.displayName,
                    content: AccountTemplateContent.native(
                      defaultBilling: displayBilling(value.defaultBillingKind),
                      protocolLabel: value.protocol,
                      defaultEndpoint: value.baseUrl,
                      supportsModelDiscovery: value.supportsModelDiscovery,
                      supportsUsageQuery: value.supportsUsageQuery,
                    ),
                    description: value.description,
                    iconKey: value.iconKey,
                  ),
              ],
              name: AccountTextPresentation(
                raw: draft.name,
                error: draft.name.trim().isEmpty ? _strings['required'] : null,
                helper: template?.description,
              ),
              endpoint: AccountTextPresentation(
                raw: draft.endpoint,
                error: draft.endpoint.trim().isEmpty
                    ? _strings['required']
                    : null,
              ),
              credential: AccountTextPresentation(
                raw: draft.credential,
                helper: [
                  if (template != null) template.credentialLabel,
                  if (template?.credentialEnv.isNotEmpty == true)
                    template!.credentialEnv,
                ].join(' · '),
              ),
              authentication:
                  draft.authentication ==
                      account_domain.AccountAuthenticationMethod.chatGpt
                  ? AccountAuthenticationMethod.chatGpt
                  : AccountAuthenticationMethod.apiKey,
              isOpenAiTemplate: draft.templateId == 'openai',
              chatGptLogin: _chatGptLoginPresentation(login),
              savedChatGptAccount: _chatGptAccountPresentation(
                _initialNative?.chatgptAccount ??
                    (_details?.value.value is NativeAccountDetails
                        ? (_details!.value.value as NativeAccountDetails)
                              .chatgptAccount
                        : null),
              ),
              protocolLabel: draft.protocol,
              setDefaultOnCreate: _setDefaultOnCreate,
              showSetDefaultOnCreate: _key.creating,
              canChangeTemplate: _key.creating && !_created && !_saving,
              hasStoredCredential:
                  currentNative?.hasBearerToken ??
                  (_initialNative?.hasBearerToken == true ||
                      (_created &&
                          _baseline?.credential.trim().isNotEmpty == true)),
              credentialRequired:
                  _initialNative?.credentialRequired ??
                  template?.credentialEnv.isNotEmpty ??
                  false,
              dirty: _dirty,
              saving: _saving,
              canSave: canSave,
              canAddModel: !_finished,
              manualModels: [
                for (final row in draft.rows)
                  row
                      .presentation(
                        _strings,
                        _models.state.value.model(
                          AccountModelIdentity(
                            account: NativeAccountIdentity(_key.target.id),
                            modelId: row.id,
                          ),
                        ),
                      )
                      .copyWith(canRemove: !_saving && !_unknownResult),
              ],
              declaredModels: [
                if (_key.creating && !_created && template != null)
                  for (final model in catalog.modelsFor(
                    template.modelCatalogId,
                  ))
                    AccountModelPresentation(
                      key: AccountModelKey(
                        account: _key.target,
                        modelId: model.modelId,
                      ),
                      name: model.displayName,
                      origin: AccountModelOrigin.bundled,
                      summary: model.description,
                    ),
              ],
              billing: AccountBillingPresentation(
                effective: draft.billing != null
                    ? displayBilling(draft.billing)
                    : summary != null
                    ? displayBilling(summary.billingKind)
                    : _key.creating &&
                          !_created &&
                          template != null &&
                          draft.endpoint == template.baseUrl
                    ? displayBilling(template.defaultBillingKind)
                    : AccountBilling.unknown,
                billingKindOverride: draft.billing == null
                    ? null
                    : displayBilling(draft.billing),
                allowedOverrides: AccountBilling.values,
              ),
              error: error ?? validation ?? authenticationValidation,
            ),
      acp: _acpName == null
          ? null
          : AcpAccountEditorPresentation(
              editorId: _key.editorId,
              accountKey: _key.creating && !_created ? null : _key.target,
              templateName: acpKey?.providerId == null
                  ? ''
                  : _acp.templates.value.templates
                            .where(
                              (value) =>
                                  value.provider.wire == acpKey!.providerId,
                            )
                            .firstOrNull
                            ?.displayName ??
                        _initialAcp?.provider.wire ??
                        '',
              name: AccountTextPresentation(raw: _acpName!, error: validation),
              preparation: AcpAccountPresentation(
                phase: AcpPresentationPhase.idle,
                status: _strings['acp.idle'],
              ),
              dirty: _dirty,
              saving: _saving,
              canSave: canSave,
              saveAndConnect: _key.creating && !_created,
              error: error,
            ),
    );
  }

  void acpChanged() => _publish();
  void _changed() {
    if (!ref.mounted || _finished) return;
    if (_raw != null || _acpName != null) {
      final source = _accounts.state.value;
      if (source.stale ||
          (source.stamp != null &&
              _baselineOwnerEpoch != null &&
              source.stamp!.ownerEpoch != _baselineOwnerEpoch)) {
        _baselineInvalidated = true;
      }
      _baselineOwnerEpoch ??= source.stamp?.ownerEpoch;
    }
    _initialize();
    _publish();
  }

  void _publish() {
    if (ref.mounted && !_finished) state = AsyncData(_derive());
  }
}

ChatGptAccountInfo? _chatGptAccountPresentation(
  account_domain.ChatGptAccountInfo? account,
) => account == null
    ? null
    : ChatGptAccountInfo(
        email: account.email,
        planUsageEnabled: account.planUsageEnabled,
      );

ChatGptLoginSnapshot? _chatGptLoginPresentation(
  account_domain.ChatGptLoginSnapshot? snapshot,
) => snapshot == null
    ? null
    : ChatGptLoginSnapshot(
        phase: switch (snapshot.phase) {
          account_domain.ChatGptLoginPhase.preparing =>
            ChatGptLoginPhase.preparing,
          account_domain.ChatGptLoginPhase.awaitingBrowser =>
            ChatGptLoginPhase.awaitingBrowser,
          account_domain.ChatGptLoginPhase.exchangingCode =>
            ChatGptLoginPhase.exchangingCode,
          account_domain.ChatGptLoginPhase.succeeded =>
            ChatGptLoginPhase.succeeded,
          account_domain.ChatGptLoginPhase.cancelled =>
            ChatGptLoginPhase.cancelled,
          account_domain.ChatGptLoginPhase.failed => ChatGptLoginPhase.failed,
        },
        account: _chatGptAccountPresentation(snapshot.account),
        failure: switch (snapshot.failure?.code) {
          account_domain.ChatGptLoginFailureCode.authorizationDenied =>
            ChatGptLoginFailureCode.authorizationDenied,
          account_domain.ChatGptLoginFailureCode.missingPlanPermission =>
            ChatGptLoginFailureCode.missingPlanPermission,
          account_domain.ChatGptLoginFailureCode.expired =>
            ChatGptLoginFailureCode.expired,
          null => null,
          _ => ChatGptLoginFailureCode.other,
        },
      );
