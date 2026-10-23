import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../state/profile_editor_state.dart';
import 'profile_routes.dart';

part 'agent_profile_editor_view_model.g.dart';

@riverpod
class AgentProfileEditorViewModel extends _$AgentProfileEditorViewModel {
  late ConfigurationRepository _configuration;
  late ModelsRepository _models;
  final _observations = <Observation>[];
  Observation? _saveObservation;
  int _lifetime = 0;
  int _intent = 0;
  int _routeIntent = 0;
  bool _initialSuggestionStarted = false;
  bool _alive = true;
  bool _saving = false;

  @override
  Future<ProfileEditorViewState> build(ProfileEditorKey key) async {
    _alive = true;
    final lifetime = ++_lifetime;
    _routeIntent = 0;
    _initialSuggestionStarted = false;
    _saving = false;
    final profileId = key.profileId;
    final configuration = _configuration = ref.watch(configurationRepositoryProvider);
    final models = _models = ref.watch(modelsRepositoryProvider);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final observation in _observations) { observation.cancel(); }
      _observations.clear();
      _saveObservation?.cancel();
    });
    _observations.add(configuration.profiles.watchLatest((source) {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(source: source));
    }).observation);
    _observations.add(configuration.state.watchLatest((source) {
      if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(configurationSource: source));
    }).observation);
    _observations.add(models.state.watchLatest((source) {
      if (_owns(lifetime)) _modelSourceChanged(source);
    }).observation);
    AgentProfileSnapshot? profile;
    await Future.wait<void>([
      configuration.loadAccountsPage().then((_) {}),
      models.loadAccountsPage().then((_) {}),
      if (profileId != null) configuration.loadProfile(profileId).then((value) { profile = value; }),
    ]);
    if (!_alive || lifetime != _lifetime) throw const StudioFailure(code: StudioFailureCode.cancelled,
      message: 'The original profile editor is no longer active.', retryable: false, correlationId: 'settings-profile-editor');
    final current = profile;
    if (current?.system ?? false) throw const StudioFailure(code: StudioFailureCode.permissionDenied,
      message: 'System profiles are read-only; enabled is a separate command.', retryable: false, correlationId: 'settings-profile-editor');
    final catalogs = displayCollectionRows(models.state.value.accounts);
    return ProfileEditorViewState(key: key, source: configuration.profiles.value,
      configurationSource: configuration.state.value, modelSource: models.state.value,
      canonical: current, profileId: current?.profileId ?? '', displayName: current?.displayName ?? '',
      description: current?.description ?? '', whenToUse: current?.whenToUse ?? '', instructions: current?.systemInstructions ?? '',
      accountId: current?.accountId ?? '', modelId: current?.modelId ?? '', effort: current?.effort, enabled: current?.enabled ?? true,
      workspaceMode: current?.workspaceMode ?? AgentWorkspaceMode.directory, models: catalogs);
  }

  bool _owns(int lifetime) => _alive && lifetime == _lifetime && state.asData != null;
  int get lifetime => _lifetime;
  bool ownsEditor(int lifetime, ProfileEditorKey key) => _owns(lifetime) && state.requireValue.key == key;
  bool get _editable => _alive && !_saving && state.asData != null && !(state.requireValue.saveAction?.preventsResubmission ?? false);

  ModelCatalogReadTarget? _catalogTarget(ModelsState source) {
    final projection = source.projection;
    final origin = projection.stamp?.origin;
    final reference = projection.header?.reference;
    if (projection.sync.phase != ResourceSyncPhase.ready || origin == null || reference == null) return null;
    return ModelCatalogReadTarget(origin: origin, reference: reference);
  }

  static const _suggestionSuperseded = StudioFailure(code: StudioFailureCode.superseded,
    message: 'The model suggestion belongs to a previous catalog. Retry it explicitly.', retryable: true,
    correlationId: 'settings-profile-suggestion');

  void _modelSourceChanged(ModelsState source) {
    final current = state.requireValue;
    final target = _catalogTarget(source);
    var suggestion = current.routeSuggestion;
    if (suggestion != null && suggestion.pending && suggestion.catalog != target) {
      // Revoking UI eligibility does not cancel the Repository-owned read.
      _routeIntent++;
      suggestion = suggestion.copyWith(pending: false, error: source.projection.sync.error ?? _suggestionSuperseded);
    }
    state = AsyncData(current.copyWith(modelSource: source, models: displayCollectionRows(source.accounts),
      routeSuggestion: suggestion, routeModel: current.routeModel?.catalog == target ? current.routeModel : null));
  }

  /// Called once by the explicit new-editor Smart entry, never by build/save.
  Future<void> suggestInitialRoute() async {
    if (!_editable || _initialSuggestionStarted || _routeIntent != 0) return;
    final current = state.requireValue;
    if (current.key.profileId != null || current.canonical != null) return;
    _initialSuggestionStarted = true;
    await _suggestRoute(ProfileRouteSuggestionKind.newProfile);
  }

  Future<void> retryRouteSuggestion() async {
    if (!_editable) return;
    final current = state.requireValue;
    final suggestion = current.routeSuggestion;
    if (suggestion == null || suggestion.pending || suggestion.error == null) return;
    if (suggestion.kind == ProfileRouteSuggestionKind.newProfile) {
      if (current.key.profileId != null || current.canonical != null || current.accountId.isNotEmpty || current.modelId.isNotEmpty) return;
      await _suggestRoute(suggestion.kind);
    } else {
      if (suggestion.model != AccountModelKey(accountId: current.accountId, modelId: current.modelId)) return;
      await _suggestRoute(suggestion.kind, model: suggestion.model);
    }
  }

  Future<void> _suggestRoute(ProfileRouteSuggestionKind kind, {AccountModelKey? model, bool changeRoute = false}) async {
    final current = state.requireValue;
    final lifetime = _lifetime;
    final editor = current.key;
    final intent = ++_routeIntent;
    final repository = _models;
    final source = repository.state.value;
    final catalog = _catalogTarget(source);
    final request = ProfileRouteSuggestion(editor: editor, intent: intent, kind: kind, catalog: catalog, model: model, pending: true);
    // Publish the explicit new raw route and its request as one intent. A
    // reentrant newer selection must not be followed by this request's write.
    state = AsyncData(current.copyWith(modelSource: source, models: displayCollectionRows(source.accounts),
      routeSuggestion: request, routeModelError: null,
      accountId: changeRoute ? model!.accountId : current.accountId,
      modelId: changeRoute ? model!.modelId : current.modelId,
      effort: changeRoute ? null : current.effort,
      routeModel: changeRoute || current.routeModel?.catalog != catalog ? null : current.routeModel,
      dirty: changeRoute || current.dirty, revision: changeRoute ? current.revision + 1 : current.revision,
      validation: changeRoute ? ({...current.validation}..remove(ProfileField.route)) : current.validation));
    bool owns() => ownsEditor(lifetime, editor) && _routeIntent == intent && state.requireValue.routeSuggestion?.intent == intent;
    bool currentTarget() => catalog != null && _catalogTarget(repository.state.value) == catalog;
    if (!owns()) return;
    try {
      if (catalog == null) throw source.projection.sync.error ?? const StudioFailure(
        code: StudioFailureCode.unavailable, message: 'The model catalog has no current readable version.', retryable: true,
        correlationId: 'settings-profile-suggestion');
      final ModelSelection? selection;
      if (kind == ProfileRouteSuggestionKind.newProfile) {
        selection = await repository.firstTextModel(catalog: catalog);
      } else {
        final selectedModel = model!;
        selection = ModelSelection(model: selectedModel, effort: await repository.effortAfterModelSelection(
          catalog: catalog, model: selectedModel, candidate: null));
      }
      if (!owns()) return;
      if (!currentTarget()) throw _suggestionSuperseded;
      ModelDescriptor? descriptor;
      StudioFailure? modelError;
      if (selection != null) {
        if (selection.model.accountId.isEmpty || selection.model.modelId.isEmpty) throw const StudioFailure(
          code: StudioFailureCode.protocol, message: 'The model suggestion returned an empty model identity.', retryable: false,
          correlationId: 'settings-profile-suggestion');
        final account = currentCollectionRow(repository.state.value.accounts, catalog.origin,
          (value) => value.accountId == selection.model.accountId)?.value;
        descriptor = account?.effectiveModels.where((value) => value.modelId == selection.model.modelId).firstOrNull;
        if (descriptor == null) {
          // This exact-key read only supplies display details, not first/default
          // policy. loadModel freezes its current target synchronously; both
          // sides of its await must still match this original catalog.
          try { descriptor = await repository.loadModel(selection.model.accountId, selection.model.modelId); }
          on StudioFailure catch (error) { modelError = error; }
          if (!owns()) return;
          if (!currentTarget()) throw _suggestionSuperseded;
        }
      }
      final next = state.requireValue;
      final changed = selection != null && (next.accountId != selection.model.accountId ||
        next.modelId != selection.model.modelId || next.effort != selection.effort);
      state = AsyncData(next.copyWith(
        accountId: selection?.model.accountId ?? next.accountId, modelId: selection?.model.modelId ?? next.modelId,
        effort: selection == null ? next.effort : selection.effort,
        revision: changed ? next.revision + 1 : next.revision,
        // Text/raw/dirty may have changed while awaiting this route suggestion.
        // Only the route fields are handed over; dirty is never cleared here.
        routeSuggestion: request.copyWith(pending: false), routeModelError: modelError,
        routeModel: selection == null || descriptor == null ? null : ProfileRouteModel(
          model: selection.model, catalog: catalog, descriptor: descriptor),
        validation: selection == null ? next.validation : ({...next.validation}..remove(ProfileField.route))));
    } on StudioFailure catch (error) {
      if (owns()) state = AsyncData(state.requireValue.copyWith(routeSuggestion: request.copyWith(pending: false, error: error)));
    }
  }

  void setId(String value) {
    if (!_editable || state.requireValue.key.profileId != null) return;
    _text(ProfileField.id, value);
  }
  void setDisplayName(String value) => _text(ProfileField.displayName, value);
  void setDescription(String value) => _text(ProfileField.description, value);
  void setWhenToUse(String value) => _text(ProfileField.whenToUse, value);
  void setInstructions(String value) => _text(ProfileField.instructions, value);
  void _text(ProfileField field, String raw) {
    if (!_editable) return;
    final current = state.requireValue;
    final next = switch (field) {
      ProfileField.id => current.copyWith(profileId: raw),
      ProfileField.displayName => current.copyWith(displayName: raw),
      ProfileField.description => current.copyWith(description: raw),
      ProfileField.whenToUse => current.copyWith(whenToUse: raw),
      ProfileField.instructions => current.copyWith(instructions: raw),
      ProfileField.route => current,
    };
    if (next == current) return;
    state = AsyncData(next.copyWith(dirty: true, revision: current.revision + 1,
      validation: {...current.validation}..remove(field)));
  }
  Future<void> setRoute(String accountId, String modelId) async {
    if (!_editable) return;
    final current = state.requireValue;
    if (current.accountId == accountId && current.modelId == modelId) return;
    final account = currentCollectionRow(_models.state.value.accounts, _models.state.value.projection.stamp?.origin,
      (value) => value.accountId == accountId)?.value;
    final model = account?.effectiveModels.where((value) => value.modelId == modelId).firstOrNull;
    if (model == null || !supportsProfileText(model)) return;
    // A new model never inherits the previous model's effort. Null here is raw
    // pending input, not a successful suggestion or save-time default.
    await _suggestRoute(ProfileRouteSuggestionKind.selectedModel,
      model: AccountModelKey(accountId: accountId, modelId: modelId), changeRoute: true);
  }
  void setEffort(String? value) {
    if (!_editable) return;
    final current = state.requireValue;
    if (current.effort == value && current.routeSuggestion == null) return;
    final detail = current.routeModel;
    final descriptor = detail != null && detail.model == AccountModelKey(accountId: current.accountId, modelId: current.modelId) &&
      detail.catalog == _catalogTarget(_models.state.value) ? detail.descriptor : profileModel(current.models, current.accountId, current.modelId);
    if (value != null && !(descriptor?.reasoning?.candidates.contains(value) ?? false)) return;
    // Even an explicit null equal to the pending raw value supersedes a late
    // native default suggestion. No build/save will repair it afterwards.
    _routeIntent++;
    state = AsyncData(current.copyWith(effort: value, routeSuggestion: null, dirty: true, revision: current.revision + 1));
  }
  void setWorkspaceMode(AgentWorkspaceMode value) {
    if (!_editable || state.requireValue.workspaceMode == value) return;
    state = AsyncData(state.requireValue.copyWith(workspaceMode: value, dirty: true, revision: state.requireValue.revision + 1));
  }
  void setEnabled(bool value) {
    if (!_editable || state.requireValue.enabled == value) return;
    state = AsyncData(state.requireValue.copyWith(enabled: value, dirty: true, revision: state.requireValue.revision + 1));
  }

  Future<void> loadMoreModels() async {
    if (!_alive || state.asData == null || state.requireValue.loadingModels) return;
    final lifetime = _lifetime;
    state = AsyncData(state.requireValue.copyWith(loadingModels: true, sourceError: null));
    StudioFailure? failure;
    try { await Future.wait<void>([_configuration.loadAccountsPage(), _models.loadAccountsPage()]); }
    on StudioFailure catch (error) { failure = error; }
    if (_owns(lifetime)) state = AsyncData(state.requireValue.copyWith(loadingModels: false, sourceError: failure));
  }

  Future<bool> save() async {
    if (!_editable || state.requireValue.routeSuggestion?.pending == true) return false;
    final lifetime = _lifetime;
    _saving = true;
    try { return await _save(); }
    finally { if (lifetime == _lifetime) _saving = false; }
  }
  Future<bool> _save() async {
    final current = state.requireValue;
    final lifetime = _lifetime;
    final configuration = _configuration;
    final validation = <ProfileField, ProfileValidation>{
      if (current.profileId.trim().isEmpty) ProfileField.id: ProfileValidation.required,
      if (current.displayName.trim().isEmpty) ProfileField.displayName: ProfileValidation.required,
      if (current.description.trim().isEmpty) ProfileField.description: ProfileValidation.required,
      if (current.whenToUse.trim().isEmpty) ProfileField.whenToUse: ProfileValidation.required,
      if (current.instructions.trim().isEmpty) ProfileField.instructions: ProfileValidation.required,
      if (current.accountId.isEmpty || current.modelId.isEmpty) ProfileField.route: ProfileValidation.required,
    };
    state = AsyncData(current.copyWith(validation: validation));
    if (validation.isNotEmpty || !ownsEditor(lifetime, current.key)) return false;
    final revision = current.revision;
    final intent = ++_intent;
    final edit = AgentProfileEdit(profileId: current.profileId.trim(), displayName: current.displayName.trim(),
      description: current.description.trim(), whenToUse: current.whenToUse.trim(), systemInstructions: current.instructions.trim(),
      accountId: current.accountId, modelId: current.modelId, effort: current.effort,
      enabled: current.enabled, workspaceMode: current.workspaceMode);
    state = AsyncData(state.requireValue.copyWith(saveAction: SettingsAction(intent: intent, pending: true)));
    bool owns() => _owns(lifetime) && state.requireValue.saveAction?.intent == intent;
    if (!owns()) return false;
    OperationTicket<Unit> ticket;
    try { ticket = configuration.saveProfile(edit); }
    on StudioFailure catch (error) {
      if (owns()) state = AsyncData(state.requireValue.copyWith(saveAction: SettingsAction(intent: intent,
        outcome: SettingsActionOutcome.rejected, error: error)));
      return false;
    }
    StudioFailure? observationError;
    _saveObservation?.cancel();
    _saveObservation = null;
    if (owns()) {
      try {
        final observation = ticket.state.watchLatest((operation) {
          if (owns()) state = AsyncData(state.requireValue.copyWith(saveAction: state.requireValue.saveAction!.copyWith(operation: operation)));
        }).observation;
        if (owns()) { _saveObservation = observation; } else { observation.cancel(); }
      } on StudioFailure catch (error) { observationError = error; }
      state = AsyncData(state.requireValue.copyWith(saveAction: state.requireValue.saveAction!.copyWith(
        operation: ticket.state.value, observationError: observationError)));
    }
    final result = await ticket.result;
    if (!owns()) return false;
    final action = settledSettingsAction(intent, result, operation: ticket.state.value).copyWith(observationError: observationError);
    state = AsyncData(state.requireValue.copyWith(saveAction: action,
      dirty: action.succeeded && state.requireValue.revision == revision ? false : state.requireValue.dirty));
    return action.succeeded && state.requireValue.revision == revision;
  }
}
