import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/coalesced_publish.dart';
import '../../view_models/read_values.dart';
import '../state/account_editor_state.dart';
import 'account_selectors.dart';
import 'accounts_view_model.dart';

part 'account_editor_view_model.g.dart';

@riverpod
class AccountEditorViewModel extends _$AccountEditorViewModel {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  final _observations = <Observation>[];
  Observation? _saveObservation;
  Observation? _defaultObservation;
  Observation? _billingObservation;
  int _lifetime = 0;
  int _rowId = 0;
  int _intent = 0;
  bool _alive = true;
  bool _makeDefault = false;
  bool _saving = false;
  void Function()? _releaseRetention;

  @override
  Future<AccountEditorViewState> build(AccountEditorKey key) async {
    _alive = true;
    final lifetime = ++_lifetime;
    // Freeze the synchronous list-owned identity before any reads. The list
    // owns no raw fields and a later editor cannot supply this one's target.
    final accountId = ref
        .read(accountsViewModelProvider.notifier)
        .accountIdForEditor(key);
    _configuration = ref.watch(configurationRepositoryProvider);
    _models = ref.watch(modelsRepositoryProvider);
    _releaseRetention = ref.keepAlive().close;
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final observation in _observations) {
        observation.cancel();
      }
      _observations.clear();
      _saveObservation?.cancel();
      _defaultObservation?.cancel();
      _billingObservation?.cancel();
      // Manual forms are never auto-saved or business-cancelled on disposal.
    });
    // Sources can publish while another provider is still building; one trailing
    // microtask applies the latest account/catalog/templates in a single write.
    final sourcePublish = CoalescedPublish(() {
      if (_owns(lifetime)) _publishSources(lifetime, accountId);
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
    await Future.wait<void>([
      _models.loadTemplates().then((_) {}),
      _configuration.loadDefaultAccountId().then((_) {}),
      if (key.accountId != null) ...[
        _configuration.loadAccount(accountId).then((_) {}),
        _models.loadAccount(accountId).then((_) {}),
      ],
    ]);
    final source = _configuration.state.value;
    final modelSource = _models.state.value;
    final templateSource = _models.templates.value;
    final templates = currentTemplatesValue(templateSource);
    if (templates == null) {
      throw _failure(
        StudioFailureCode.unavailable,
        'Account templates have no current materialized value.',
      );
    }
    if (key.accountId == null) {
      final template = templates.templates
          .where((value) => value.id == key.initialTemplateId)
          .firstOrNull;
      if (template == null) {
        throw _failure(
          StudioFailureCode.notFound,
          'The chosen account template is unavailable.',
        );
      }
      return AccountEditorViewState(
        key: key,
        accountId: accountId,
        source: source,
        modelSource: modelSource,
        templateSource: templateSource,
        templates: templates,
        templateId: template.id,
        templatePreview: true,
        protocol: template.protocol,
        name: template.displayName,
        baseUrl: template.baseUrl,
      );
    }
    final account = currentCollectionRow(
      source.accounts,
      source.projection.stamp?.origin,
      (value) => value.accountId == accountId,
    )?.value;
    final catalog = currentCollectionRow(
      modelSource.accounts,
      modelSource.projection.stamp?.origin,
      (value) => value.accountId == accountId,
    )?.value;
    if (account == null || catalog == null) {
      throw _failure(
        StudioFailureCode.superseded,
        'The account changed while its editor was loading.',
      );
    }
    return AccountEditorViewState(
      key: key,
      accountId: accountId,
      source: source,
      modelSource: modelSource,
      templateSource: templateSource,
      templates: templates,
      canonical: account,
      catalog: catalog,
      templateId: account.templateId,
      protocol: account.protocol,
      name: account.name,
      baseUrl: account.baseUrl,
      customModels: [
        for (final model in account.customModels)
          CustomModelDraft(
            rowId: ++_rowId,
            originalModelId: model.modelId,
            modelId: model.modelId,
            displayName: model.displayName,
            wireApi: model.wireApi,
            contextWindowRaw: model.contextWindow?.toString() ?? '',
            maxOutputTokensRaw: model.maxOutputTokens?.toString() ?? '',
          ),
      ],
    );
  }

  bool _owns(int lifetime) =>
      _alive && lifetime == _lifetime && state.asData != null;

  /// Publishes the latest account, catalog and template sources at once.
  void _publishSources(int lifetime, String accountId) {
    final source = _configuration.state.value;
    final modelSource = _models.state.value;
    final templateSource = _models.templates.value;
    final canonical = currentCollectionRow(
      source.accounts,
      source.projection.stamp?.origin,
      (account) => account.accountId == accountId,
    )?.value;
    final catalog = currentCollectionRow(
      modelSource.accounts,
      modelSource.projection.stamp?.origin,
      (account) => account.accountId == accountId,
    )?.value;
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        source: source,
        canonical: canonical ?? current.canonical,
        modelSource: modelSource,
        catalog: catalog ?? current.catalog,
        templateSource: templateSource,
        templates: currentTemplatesValue(templateSource) ?? current.templates,
        templatePreview:
            catalog != null &&
                current.saved &&
                current.canonical?.templateId == current.templateId
            ? false
            : current.templatePreview,
      ),
    );
  }

  void endEditing() {
    _alive = false;
    _releaseRetention?.call();
    _releaseRetention = null;
  }

  bool get _editable =>
      _alive &&
      !_saving &&
      state.asData != null &&
      !state.requireValue.saving &&
      !(state.requireValue.saveAction?.preventsResubmission ?? false) &&
      !(state.requireValue.defaultAction?.preventsResubmission ?? false);

  void setName(String value) => _field(AccountEditorField.name, value);
  void setBaseUrl(String value) => _field(AccountEditorField.baseUrl, value);

  /// 免计费（noCharge）开关。
  ///
  /// 新建时它只是表单草稿（随保存作为 `initialBillingKind` 提交，`unknown` = 未指定）；
  /// 编辑已有账号时它是 canonical 窄命令：开启写 `noCharge`，关闭写 `null`（清除覆盖，
  /// 回到自动推导）——因此**未触碰开关不会改动**既有的显式 metered/subscription 覆盖。
  Future<void> setNoCharge(bool enabled) async {
    if (!_editable) return;
    final current = state.requireValue;
    if (current.create) {
      final next = enabled ? BillingKind.noCharge : BillingKind.unknown;
      if (current.initialBillingKind == next) return;
      state = AsyncData(
        current.copyWith(
          initialBillingKind: next,
          draftRevision: current.draftRevision + 1,
        ),
      );
      return;
    }
    if (current.billingAction?.preventsResubmission ?? false) return;
    final lifetime = _lifetime;
    final intent = ++_intent;
    state = AsyncData(
      current.copyWith(
        billingAction: SettingsAction(intent: intent, pending: true),
      ),
    );
    bool owns() =>
        _owns(lifetime) && state.requireValue.billingAction?.intent == intent;
    void update(SettingsAction action) {
      if (!owns()) return;
      state = AsyncData(state.requireValue.copyWith(billingAction: action));
    }

    OperationTicket<Unit> ticket;
    try {
      // 只提交显式意图：关闭 = 清除覆盖（null），不是写 unknown。
      ticket = _configuration.setAccountBillingKind(
        current.accountId,
        enabled ? BillingKind.noCharge : null,
      );
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
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          final action = state.requireValue.billingAction;
          if (action == null) return;
          update(action.copyWith(operation: operation));
        });
        if (owns()) {
          _billingObservation?.cancel();
          _billingObservation = watch.observation;
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
    }
    final result = await ticket.result;
    update(
      settledSettingsAction(
        intent,
        result,
        operation: ticket.state.value,
      ).copyWith(observationError: observationError),
    );
  }

  void _field(AccountEditorField field, String value) {
    if (!_editable) return;
    final current = state.requireValue;
    if (field == AccountEditorField.name && current.name != value) {
      _changed(current.copyWith(name: value), field);
    }
    if (field == AccountEditorField.baseUrl && current.baseUrl != value) {
      _changed(current.copyWith(baseUrl: value), field);
    }
  }

  void _changed(AccountEditorViewState value, AccountEditorField field) =>
      state = AsyncData(
        value.copyWith(
          dirtyFields: {...value.dirtyFields, field},
          validation: {...value.validation}..remove(field),
          draftRevision: value.draftRevision + 1,
        ),
      );

  void setSecret(String raw) {
    if (!_editable || state.requireValue.secretRaw == raw) return;
    final current = state.requireValue;
    _changed(
      current.copyWith(
        secretRaw: raw,
        secretIntent: raw.trim().isEmpty
            ? AccountSecretIntent.preserve
            : AccountSecretIntent.replace,
      ),
      AccountEditorField.secret,
    );
  }

  void setSecretIntent(AccountSecretIntent intent) {
    if (!_editable || state.requireValue.secretIntent == intent) return;
    _changed(
      state.requireValue.copyWith(
        secretIntent: intent,
        secretRaw: intent == AccountSecretIntent.replace
            ? state.requireValue.secretRaw
            : '',
      ),
      AccountEditorField.secret,
    );
  }

  void setTemplate(String templateId) {
    if (!_editable || state.requireValue.templateId == templateId) return;
    final current = state.requireValue;
    final template = current.templates.templates
        .where((value) => value.id == templateId)
        .firstOrNull;
    if (template == null) {
      return; // An unresolved template never becomes the first option.
    }
    state = AsyncData(
      current.copyWith(
        templateId: template.id,
        templatePreview: true,
        rebuildModelConfiguration: true,
        protocol: template.protocol,
        name: template.displayName,
        baseUrl: template.baseUrl,
        secretIntent: AccountSecretIntent.preserve,
        secretRaw: '',
        customModels: [],
        connectionEdits: {},
        removedCustomModelIds:
            current.canonical?.customModels
                .map((model) => model.modelId)
                .toList() ??
            [],
        dirtyFields: {
          AccountEditorField.template,
          AccountEditorField.name,
          AccountEditorField.baseUrl,
          AccountEditorField.secret,
        },
        validation: {},
        formGeneration: current.formGeneration + 1,
        draftRevision: current.draftRevision + 1,
      ),
    );
  }

  void addCustomModel() {
    if (!_editable) return;
    final current = state.requireValue;
    final ids = {
      for (final model in _descriptors(current)) model.modelId,
      for (final model in current.customModels) model.modelId,
    };
    var id = 'custom-model';
    for (var index = 2; ids.contains(id); index++) {
      id = 'custom-model-$index';
    }
    state = AsyncData(
      current.copyWith(
        draftRevision: current.draftRevision + 1,
        customModels: [
          ...current.customModels,
          CustomModelDraft(
            rowId: ++_rowId,
            originalModelId: null,
            modelId: id,
            displayName: id,
            wireApi: 'chat_completions',
            contextWindowRaw: '32000',
            maxOutputTokensRaw: '4096',
            dirty: true,
          ),
        ],
      ),
    );
  }

  void setCustomModel(int rowId, CustomModelField field, String raw) {
    if (!_editable) return;
    final current = state.requireValue;
    final previous = current.customModels
        .where((model) => model.rowId == rowId)
        .firstOrNull;
    if (previous == null) return;
    final next = switch (field) {
      CustomModelField.modelId => previous.copyWith(
        modelId: raw,
        displayName:
            previous.displayName == previous.modelId ||
                previous.displayName == 'Custom model'
            ? raw
            : previous.displayName,
      ),
      CustomModelField.displayName => previous.copyWith(displayName: raw),
      CustomModelField.wireApi =>
        raw == 'chat_completions' || raw == 'responses'
            ? previous.copyWith(wireApi: raw)
            : previous,
      CustomModelField.contextWindow => previous.copyWith(
        contextWindowRaw: raw,
      ),
      CustomModelField.maxOutputTokens => previous.copyWith(
        maxOutputTokensRaw: raw,
      ),
    };
    if (next == previous) return;
    final connections = {...current.connectionEdits};
    if (next.modelId.trim() != previous.modelId.trim() ||
        next.wireApi != previous.wireApi) {
      connections.remove(previous.modelId);
      connections.remove(previous.modelId.trim());
      connections.remove(previous.originalModelId);
    }
    state = AsyncData(
      _validate(
        current.copyWith(
          draftRevision: current.draftRevision + 1,
          connectionEdits: connections,
          customModels: [
            for (final model in current.customModels)
              if (model.rowId == rowId)
                next.copyWith(
                  dirty: true,
                  dirtyFields: {...next.dirtyFields, field},
                )
              else
                model,
          ],
        ),
      ),
    );
  }

  void removeCustomModel(int rowId) {
    if (!_editable) return;
    final current = state.requireValue;
    final model = current.customModels
        .where((model) => model.rowId == rowId)
        .firstOrNull;
    if (model == null) return;
    final connections = {...current.connectionEdits}
      ..remove(model.modelId)
      ..remove(model.modelId.trim())
      ..remove(model.originalModelId);
    state = AsyncData(
      _validate(
        current.copyWith(
          draftRevision: current.draftRevision + 1,
          customModels: current.customModels
              .where((item) => item.rowId != rowId)
              .toList(),
          connectionEdits: connections,
          removedCustomModelIds: [
            ...current.removedCustomModelIds,
            ?model.originalModelId,
          ],
        ),
      ),
    );
  }

  void setConnection(String modelId, String connection) {
    if (!_editable) return;
    final current = state.requireValue;
    final model = _descriptors(current)
        .where((model) => model.modelId == modelId)
        .firstOrNull;
    if (model == null ||
        !model.transport.connectionModes.any(
          (value) => value.id == connection,
        )) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        draftRevision: current.draftRevision + 1,
        connectionEdits: {...current.connectionEdits, modelId: connection},
      ),
    );
  }

  AccountEditorViewState _validate(AccountEditorViewState value) {
    final fields = <AccountEditorField, AccountValidation>{};
    if (value.secretIntent == AccountSecretIntent.replace &&
        value.secretRaw.trim().isEmpty) {
      fields[AccountEditorField.secret] = AccountValidation.required;
    }
    final models = [
      for (final model in value.customModels)
        model.copyWith(
          validation: {
            if (model.modelId.trim().isNotEmpty &&
                value.customModels
                        .where(
                          (other) =>
                              other.modelId.trim() == model.modelId.trim(),
                        )
                        .length >
                    1)
              CustomModelField.modelId: AccountValidation.duplicateModel,
            if (model.modelId.trim().isNotEmpty &&
                _descriptors(value).any(
                  (other) =>
                      other.origin != ModelOrigin.manual &&
                      other.modelId == model.modelId.trim(),
                ))
              CustomModelField.modelId: AccountValidation.onlineModelConflict,
            if ((model.originalModelId == null ||
                    model.dirtyFields.contains(
                      CustomModelField.contextWindow,
                    )) &&
                int.tryParse(model.contextWindowRaw) == null)
              CustomModelField.contextWindow: AccountValidation.integer,
            if ((model.originalModelId == null ||
                    model.dirtyFields.contains(
                      CustomModelField.maxOutputTokens,
                    )) &&
                int.tryParse(model.maxOutputTokensRaw) == null)
              CustomModelField.maxOutputTokens: AccountValidation.integer,
          },
        ),
    ];
    return value.copyWith(validation: fields, customModels: models);
  }

  List<ModelDescriptor> _descriptors(AccountEditorViewState value) =>
      !value.templatePreview && value.catalog != null
      ? value.catalog!.effectiveModels
      : value
                .templates
                .modelCatalogs[value.templates.templates
                    .where((item) => item.id == value.templateId)
                    .firstOrNull
                    ?.modelCatalogId]
                ?.models ??
            [];

  Future<bool> save() async {
    if (!_editable) return false;
    _saving = true;
    try {
      return await _save();
    } finally {
      _saving = false;
    }
  }

  Future<bool> _save() async {
    final validated = _validate(state.requireValue);
    state = AsyncData(validated);
    if (validated.validation.isNotEmpty ||
        validated.customModels.any(
          (model) =>
              model.modelId.trim().isNotEmpty && model.validation.isNotEmpty,
        )) {
      return false;
    }
    final lifetime = _lifetime;
    final intent = ++_intent;
    final frozen = validated;
    if (!frozen.saved || frozen.dirty) {
      state = AsyncData(
        frozen.copyWith(
          saveAction: SettingsAction(intent: intent, pending: true),
          defaultAction: null,
          sourceError: null,
        ),
      );
      _makeDefault =
          frozen.create ||
          (frozen.saved &&
              _makeDefault &&
              !(frozen.defaultAction?.succeeded ?? false));
      try {
        if (!isCurrentRead(
          _configuration.state.value.defaultAccountId,
          _configuration.state.value.projection.header?.reference,
          _configuration.state.value.projection.stamp?.origin,
        )) {
          await _configuration.loadDefaultAccountId();
        }
        _makeDefault =
            _makeDefault ||
            displayReadValue(_configuration.state.value.defaultAccountId) ==
                frozen.accountId;
      } on StudioFailure catch (error) {
        if (_owns(lifetime) &&
            state.requireValue.saveAction?.intent == intent) {
          state = AsyncData(
            state.requireValue.copyWith(
              saveAction: SettingsAction(
                intent: intent,
                outcome: SettingsActionOutcome.rejected,
                error: error,
              ),
            ),
          );
        }
        return false;
      }
      if (!_owns(lifetime) || state.requireValue.saveAction?.intent != intent) {
        return false;
      }
      final edit = AccountEdit(
        accountId: frozen.accountId,
        create: frozen.create,
        rebuildModelConfiguration: frozen.rebuildModelConfiguration,
        templateId:
            frozen.create ||
                frozen.rebuildModelConfiguration ||
                frozen.dirtyFields.contains(AccountEditorField.template)
            ? FieldEdit.set(frozen.templateId)
            : const FieldEdit.keep(),
        protocol:
            frozen.create ||
                frozen.dirtyFields.contains(AccountEditorField.template)
            ? FieldEdit.set(frozen.protocol)
            : const FieldEdit.keep(),
        name:
            frozen.create ||
                frozen.dirtyFields.contains(AccountEditorField.name)
            ? FieldEdit.set(frozen.name.trim())
            : const FieldEdit.keep(),
        baseUrl:
            frozen.create ||
                frozen.dirtyFields.contains(AccountEditorField.baseUrl)
            ? FieldEdit.set(frozen.baseUrl.trim())
            : const FieldEdit.keep(),
        secret: switch (frozen.secretIntent) {
          AccountSecretIntent.preserve => const AccountSecretUpdate.preserve(),
          AccountSecretIntent.replace => AccountSecretUpdate.replace(
            frozen.secretRaw.trim(),
          ),
          AccountSecretIntent.clear => const AccountSecretUpdate.clear(),
        },
        // 新建时提交表单上的初始计费类别草稿（unknown = 未指定 → null，交给后端推导）；
        // 编辑已有账号不得改写类别：一律 null，显式改写只经 setAccountBillingKind 窄命令。
        initialBillingKind:
            frozen.create && frozen.initialBillingKind != BillingKind.unknown
            ? frozen.initialBillingKind
            : null,
        customModels: [
          for (final id in frozen.removedCustomModelIds)
            CustomModelChange.remove(modelId: id),
          for (final model in frozen.customModels)
            if (model.modelId.trim().isEmpty) ...[
              if (model.originalModelId case final id?)
                CustomModelChange.remove(modelId: id),
            ] else if (model.dirty)
              CustomModelChange.upsert(
                originalModelId: model.originalModelId,
                value: AccountModelUpdate(
                  modelId: model.modelId.trim(),
                  displayName: model.displayName.trim(),
                  wireApi: model.wireApi,
                  contextWindow: int.tryParse(model.contextWindowRaw),
                  maxOutputTokens: int.tryParse(model.maxOutputTokensRaw),
                ),
              ),
        ],
        connections: [
          for (final entry in frozen.connectionEdits.entries)
            ModelConnectionChange(
              modelId: entry.key,
              connectionMode: entry.value,
            ),
        ],
        autoCompactLimits: [],
      );
      final action = await _run(
        () => _configuration.saveAccount(edit),
        intent,
        lifetime,
        false,
      );
      if (!_owns(lifetime) ||
          state.requireValue.saveAction?.intent != intent ||
          !action.succeeded) {
        return false;
      }
      final current = state.requireValue;
      // Successful account creation is never repeated because setDefault fails.
      if (current.draftRevision != frozen.draftRevision) {
        state = AsyncData(current.copyWith(saved: true));
        return false;
      }
      state = AsyncData(
        current.copyWith(
          saved: true,
          rebuildModelConfiguration: false,
          dirtyFields: {},
          removedCustomModelIds: [],
          connectionEdits: {},
          secretRaw: '',
          secretIntent: AccountSecretIntent.preserve,
          customModels: [
            for (final model in current.customModels)
              if (model.modelId.trim().isNotEmpty)
                model.copyWith(
                  originalModelId: model.modelId.trim(),
                  dirty: false,
                  dirtyFields: {},
                ),
          ],
        ),
      );
    }
    if (!_owns(lifetime)) return false;
    if (_makeDefault &&
        !(state.requireValue.defaultAction?.succeeded ?? false)) {
      final defaultIntent = ++_intent;
      state = AsyncData(
        state.requireValue.copyWith(
          defaultAction: SettingsAction(intent: defaultIntent, pending: true),
        ),
      );
      final action = await _run(
        () => _configuration.setDefaultAccount(frozen.accountId),
        defaultIntent,
        lifetime,
        true,
      );
      if (!_owns(lifetime) || !action.succeeded) return false;
    }
    if (!_owns(lifetime)) return false;
    state = AsyncData(
      state.requireValue.copyWith(verifying: true, sourceError: null),
    );
    StudioFailure? readError;
    try {
      await Future.wait<void>([
        _configuration.loadAccount(frozen.accountId).then((_) {}),
        _models.loadAccount(frozen.accountId).then((_) {}),
      ]);
    } on StudioFailure catch (error) {
      readError = error;
    }
    if (!_owns(lifetime)) return false;
    state = AsyncData(
      state.requireValue.copyWith(
        verifying: false,
        sourceError: readError,
        templatePreview: readError == null
            ? false
            : state.requireValue.templatePreview,
      ),
    );
    return readError == null &&
        !state.requireValue.dirty &&
        state.requireValue.saved &&
        (state.requireValue.saveAction?.succeeded ?? false);
  }

  Future<SettingsAction> _run(
    OperationTicket<Unit> Function() admit,
    int intent,
    int lifetime,
    bool isDefault,
  ) async {
    bool owns() =>
        _owns(lifetime) &&
        (isDefault
                    ? state.requireValue.defaultAction
                    : state.requireValue.saveAction)
                ?.intent ==
            intent;
    void update(SettingsAction action) {
      if (owns()) {
        state = AsyncData(
          isDefault
              ? state.requireValue.copyWith(defaultAction: action)
              : state.requireValue.copyWith(saveAction: action),
        );
      }
    }

    OperationTicket<Unit> ticket;
    try {
      ticket = admit();
    } on StudioFailure catch (error) {
      final action = SettingsAction(
        intent: intent,
        outcome: SettingsActionOutcome.rejected,
        error: error,
      );
      update(action);
      return action;
    }
    if (isDefault) {
      _defaultObservation?.cancel();
      _defaultObservation = null;
    } else {
      _saveObservation?.cancel();
      _saveObservation = null;
    }
    StudioFailure? observationError;
    if (owns()) {
      try {
        final observation = ticket.state.watchLatest((operation) {
          if (!owns()) return;
          final previous = isDefault
              ? state.requireValue.defaultAction
              : state.requireValue.saveAction;
          update(previous!.copyWith(operation: operation));
        }).observation;
        if (!owns()) {
          observation.cancel();
        } else if (isDefault) {
          _defaultObservation = observation;
        } else {
          _saveObservation = observation;
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
      update(
        SettingsAction(
          intent: intent,
          pending: true,
          operation: ticket.state.value,
          observationError: observationError,
        ),
      );
    }
    final result = await ticket.result;
    final action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    update(action);
    return action;
  }

  static StudioFailure _failure(StudioFailureCode code, String message) =>
      StudioFailure(
        code: code,
        message: message,
        retryable: true,
        correlationId: 'settings-account-editor',
      );
}
