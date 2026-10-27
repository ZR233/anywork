import 'dart:async';

import 'package:anywork_client/accounts.dart';
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
  String? _baselineOwnerEpoch;
  bool _baselineInvalidated = false;
  int _revision = 0;
  int _rowSequence = 0;
  String? _error;
  AcpCommandNotice? _configurationNotice;
  void Function()? _closeRetention;
  ValueObservation<AccountResource<AccountDetails>>? _details;
  AccountAcpKey? _subscribedAcpKey;
  void Function()? _closeAcpListener;
  AccountDemand? _detailDemand;
  AccountDemand? _modelDemand;

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

  void changeName(String raw) {
    if (_finished) return;
    _acpName = raw;
    _revision++;
    _publish();
  }

  void changeTemplate(AccountTemplateKey key) {
    if (!_key.creating ||
        _created ||
        key.kind != AccountKind.native ||
        _saving) {
      return;
    }
    final template = _accounts.state.value.templates.template(key.id);
    if (template == null) {
      _error = _strings['unknownTemplate'];
      _publish();
      return;
    }
    _raw = NativeAccountDraft.fromTemplate(template);
    _revision++;
    _error = null;
    _publish();
  }

  void changeBilling(AccountBilling? value) {
    if (_raw == null || _finished) return;
    _raw = _raw!.withBilling(value == null ? null : domainBilling(value));
    _revision++;
    _publish();
  }

  void addModel() {
    if (_raw == null || _finished) return;
    _raw = _raw!.withRows([
      ..._raw!.rows,
      ManualModelDraft(editorKey: '${_key.editorId}-row-${++_rowSequence}'),
    ]);
    _revision++;
    _publish();
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
  Future<bool> removeModel(String editorKey) async {
    final row = _raw?.rows
        .where((row) => row.editorKey == editorKey)
        .firstOrNull;
    if (row == null || _saving || _finished) return false;
    if (row.savedId != null) {
      try {
        final result = await _models.removeManual(
          AccountModelIdentity(
            account: NativeAccountIdentity(_key.target.id),
            modelId: row.savedId!,
          ),
        );
        if (!ref.mounted || _finished) return false;
        final settled = await observeAccountOperation(ref, result);
        if (!ref.mounted || _finished || settled == null) return false;
        if (!operationSaved(settled)) {
          _error = operationMessage(settled, _strings);
          _publish();
          return false;
        }
        _baseline = _baseline?.withRows([
          for (final value in _baseline!.rows)
            if (value.savedId != row.savedId) value,
        ]);
      } catch (error) {
        if (ref.mounted && !_finished) {
          _error = safeAccountError(error, _strings);
          _publish();
        }
        return false;
      }
    }
    _raw = _raw?.withRows([
      for (final value in _raw!.rows)
        if (value.editorKey != editorKey) value,
    ]);
    _revision++;
    _publish();
    return true;
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
    final stamp = DraftStamp(draftId: _key.editorId, revision: revision);
    _saving = true;
    _error = null;
    _configurationNotice = null;
    _publish();
    try {
      if (raw != null && baseline != null) {
        final identity = NativeAccountIdentity(_key.target.id);
        final wasCreating = _key.creating && !_created;
        final result = wasCreating
            ? await _accounts.create(raw.create(identity), draft: stamp)
            : await _accounts.patch(
                raw.patch(identity, baseline),
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
        );
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
                AccountConnection.webSocket => const ModelConnectionIntent.set(
                  AccountConnectionMode.webSocket,
                ),
              },
            );
            if (!await _accept(connectionResult)) return false;
            _baseline = _baseline!.withRows([
              for (final value in _baseline!.rows)
                value.id == row.id ? value.change(mode: row.connection) : value,
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
        _baseline = raw.withRows(savedRows);
      } else if (acpKey != null && acpName != null) {
        final provider = AcpProviderView.fromWire(acpKey.providerId)!;
        final command = AcpAccountUpdateView(
          accountId: _key.target.id,
          name: acpName.trim(),
          provider: provider,
        );
        if (_key.creating && !_created) {
          final result = await _acp.saveAndConnect(command, draft: stamp);
          if (!ref.mounted || _finished || _baselineInvalidated) return false;
          _created = true;
          _baselineAcpName = acpName;
          _initialAcp = result.saved;
          _observeCreatedDetails();
          _acpKey = AccountAcpKey(
            target: _key.target,
            providerId: result.saved.provider.wire,
            connectionRevision: result.saved.connectionRevision,
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
          _error = safeAccountError(error, _strings);
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
    if (!ref.mounted || _finished || settled == null) return false;
    if (_baselineInvalidated) return false;
    _unknownResult =
        settled.failurePhase == OperationPhase.unknownOutcome ||
        settled.failurePhase == OperationPhase.syncFailed;
    _error = operationMessage(settled, _strings);
    return operationSaved(settled);
  }

  /// UI supplies only the user's choice. Saving, failure and revision checks
  /// remain with the same form owner on all internal and external exit paths.
  Future<bool> requestLeave(AccountLeaveChoice choice) async {
    if (_saving || _finished || choice == AccountLeaveChoice.cancel) {
      return false;
    }
    if (choice == AccountLeaveChoice.save && !await save()) return false;
    finish();
    return true;
  }

  /// Called only after a successful leave decision. It releases finite form
  /// retention; it never cancels preparation, authentication or a saved command.
  void finish() {
    if (_finished) return;
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
    final unknownTemplate =
        draft?.templateId != null &&
        catalog.revision.isNotEmpty &&
        template == null;
    final validation =
        draft?.validate(_strings) ??
        (_acpName?.trim().isEmpty == true ? _strings['required'] : null);
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
              accountKey: _key.target,
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
              protocolLabel: draft.protocol,
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
                      .copyWith(canRemove: !_saving),
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
                effective: displayBilling(
                  draft.billing ??
                      _accounts.state.value
                          .account(domainIdentity(_key.target))
                          ?.billingKind,
                ),
                billingKindOverride: draft.billing == null
                    ? null
                    : displayBilling(draft.billing),
                allowedOverrides: AccountBilling.values,
              ),
              error: error ?? validation,
            ),
      acp: _acpName == null
          ? null
          : AcpAccountEditorPresentation(
              editorId: _key.editorId,
              accountKey: _key.target,
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
