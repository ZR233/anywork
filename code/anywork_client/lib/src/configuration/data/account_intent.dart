import '../../../resources.dart';
import '../domain/account_edits.dart';
import '../domain/configuration_values.dart';
import '../domain/settings_updates.dart';
import 'configuration_commands.dart';

/// Called synchronously before operation admission or any await. Freezed's
/// unmodifiable views alone do not sever the caller's mutable list aliases.
AccountEdit freezeAccountEdit(AccountEdit intent) {
  if (intent.secret case ReplaceAccountSecret(:final value)) {
    if (value.trim().isEmpty)
      throw _invalid('A replacement credential cannot be empty.');
  }
  if (intent.rebuildModelConfiguration &&
      intent.templateId is! SetField<String?>) {
    throw _invalid(
      'Rebuilding model configuration requires an explicit template.',
    );
  }
  for (final change in intent.autoCompactLimits) {
    if (change.overrideLimit != null && change.overrideLimit! <= 0) {
      throw _invalid(
        'An auto-compact override must be a positive token count.',
      );
    }
  }
  if (intent.create &&
      (intent.templateId is! SetField<String?> ||
          intent.protocol is! SetField<String> ||
          intent.name is! SetField<String> ||
          intent.baseUrl is! SetField<String> ||
          intent.pricingEnabled is! SetField<bool>)) {
    throw _invalid(
      'Account creation requires explicit template, protocol, name, URL and pricing fields.',
    );
  }
  return intent.copyWith(
    customModels: List.unmodifiable(intent.customModels),
    connections: List.unmodifiable(intent.connections),
    autoCompactLimits: List.unmodifiable(intent.autoCompactLimits),
  );
}

/// Runs inside the single Settings write lane on *every* dispatch attempt.
/// The source must be the current complete account, not the UI edit baseline.
AccountSettingsUpdate buildAccountUpdate(
  AccountEdit intent,
  AccountConfiguration? canonical,
) {
  if (intent.create) {
    if (canonical != null) throw _conflict('The account already exists.');
  } else if (canonical == null || canonical.accountId != intent.accountId) {
    throw const StudioFailure(
      code: StudioFailureCode.notFound,
      message: 'The account is unavailable.',
      retryable: false,
      correlationId: 'account-intent',
    );
  }

  // Rebuilding is an explicit form intent, even after template A -> B -> A.
  // It resets only these three merge bases, not account identity or credentials.
  final preserveModels = !intent.rebuildModelConfiguration;
  final models = <AccountModelUpdate>[
    for (final model
        in preserveModels
            ? canonical?.customModels ?? const <CustomModelConfiguration>[]
            : const <CustomModelConfiguration>[])
      AccountModelUpdate(
        modelId: model.modelId,
        displayName: model.displayName,
        wireApi: model.wireApi,
        contextWindow: model.contextWindow,
        maxOutputTokens: model.maxOutputTokens,
      ),
  ];
  final connections = <AccountModelConnectionUpdate>[
    for (final item
        in preserveModels
            ? canonical?.modelConnectionModes ?? const <ModelConnection>[]
            : const <ModelConnection>[])
      AccountModelConnectionUpdate(
        modelId: item.modelId,
        connectionMode: item.connectionMode,
      ),
  ];
  final limits = <AccountModelAutoCompactUpdate>[];
  if (preserveModels) {
    for (final item
        in canonical?.modelAutoCompactLimits ?? const <ModelAutoCompact>[]) {
      final limit = item.overrideLimit;
      if (limit == null) continue;
      if (limit <= 0) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'The canonical account contains an invalid token override.',
          retryable: false,
          correlationId: 'account-intent',
        );
      }
      limits.add(
        AccountModelAutoCompactUpdate(modelId: item.modelId, limit: limit),
      );
    }
  }
  for (final change in intent.customModels) {
    switch (change) {
      case RemoveCustomModel(:final modelId):
        models.removeWhere((model) => model.modelId == modelId);
        connections.removeWhere((item) => item.modelId == modelId);
        limits.removeWhere((item) => item.modelId == modelId);
      case UpsertCustomModel(:final originalModelId, :final value):
        // null identifies a new declaration. Do not silently overwrite an
        // existing sibling with the same proposed ID; native validates it.
        final index = originalModelId == null
            ? -1
            : models.indexWhere((model) => model.modelId == originalModelId);
        if (originalModelId != null && index < 0) {
          throw const StudioFailure(
            code: StudioFailureCode.notFound,
            message: 'The original custom model is unavailable.',
            retryable: false,
            correlationId: 'account-model-intent',
          );
        }
        if (index < 0) {
          models.add(value);
        } else {
          final previous = models[index];
          if (previous.modelId != value.modelId) {
            final inherited = [
              for (final item in limits)
                if (item.modelId == previous.modelId)
                  AccountModelAutoCompactUpdate(
                    modelId: value.modelId,
                    limit: item.limit,
                  ),
            ];
            // The destination inherits exactly the original explicit override.
            // No original override means no inherited override at the new ID.
            limits.removeWhere(
              (item) =>
                  item.modelId == previous.modelId ||
                  item.modelId == value.modelId,
            );
            limits.addAll(inherited);
          }
          if (previous.modelId != value.modelId ||
              previous.wireApi != value.wireApi) {
            connections.removeWhere((item) => item.modelId == previous.modelId);
          }
          // A renamed ID remains an explicit replacement of this one entry;
          // collisions with siblings remain visible to native validation.
          models[index] = value;
        }
    }
  }
  // Later explicit user edits win over automatic cleanup/migration. Unrelated
  // members, including offline catalog overrides, were never filtered out.
  for (final change in intent.connections) {
    final index = connections.indexWhere(
      (item) => item.modelId == change.modelId,
    );
    final next = AccountModelConnectionUpdate(
      modelId: change.modelId,
      connectionMode: change.connectionMode,
    );
    if (index < 0) {
      connections.add(next);
    } else {
      connections[index] = next;
    }
  }
  for (final change in intent.autoCompactLimits) {
    limits.removeWhere((item) => item.modelId == change.modelId);
    if (change.overrideLimit case final limit?) {
      if (limit <= 0)
        throw _invalid('An auto-compact override must be positive.');
      limits.add(
        AccountModelAutoCompactUpdate(modelId: change.modelId, limit: limit),
      );
    }
  }
  return AccountSettingsUpdate(
    accountId: intent.accountId,
    templateId: _field(intent.templateId, canonical?.templateId, intent.create),
    protocol: _requiredField(intent.protocol, canonical?.protocol),
    name: _requiredField(intent.name, canonical?.name),
    baseUrl: _requiredField(intent.baseUrl, canonical?.baseUrl),
    secret: intent.secret,
    pricingEnabled: _requiredField(
      intent.pricingEnabled,
      canonical?.pricingEnabled,
    ),
    customModels: List.unmodifiable(models),
    modelConnectionModes: List.unmodifiable(connections),
    modelAutoCompactLimits: List.unmodifiable(limits),
  );
}

T _requiredField<T>(FieldEdit<T> field, T? canonical) => switch (field) {
  SetField<T>(:final value) => value,
  KeepField<T>() =>
    canonical ??
        (throw _invalid('Account creation requires an explicit field.')),
};

T? _field<T>(FieldEdit<T?> field, T? canonical, bool creating) =>
    switch (field) {
      SetField<T?>(:final value) => value,
      KeepField<T?>() =>
        creating
            ? (throw _invalid(
                'Account creation requires an explicit template.',
              ))
            : canonical,
    };

SettingsFieldUpdate freezeSettingsUpdate(SettingsFieldUpdate update) =>
    switch (update) {
      ProjectDocFallbackFilenames(:final value) =>
        SettingsFieldUpdate.projectDocFallbackFilenames(
          value: List.unmodifiable(value),
        ),
      SkillsExternalDirs(:final value) =>
        SettingsFieldUpdate.skillsExternalDirs(value: List.unmodifiable(value)),
      SkillsDisabled(:final value) => SettingsFieldUpdate.skillsDisabled(
        value: List.unmodifiable(value),
      ),
      GeneralPinnedThreadIds(:final value) =>
        SettingsFieldUpdate.generalPinnedThreadIds(
          value: List.unmodifiable(value),
        ),
      GeneralPinnedProjectIds(:final value) =>
        SettingsFieldUpdate.generalPinnedProjectIds(
          value: List.unmodifiable(value),
        ),
      WebSearchAllowedDomains(:final value) =>
        SettingsFieldUpdate.webSearchAllowedDomains(
          value: List.unmodifiable(value),
        ),
      _ => update,
    };

StudioFailure _invalid(String message) => StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: message,
  retryable: false,
  correlationId: 'account-intent',
);
StudioFailure _conflict(String message) => StudioFailure(
  code: StudioFailureCode.conflict,
  message: message,
  retryable: false,
  correlationId: 'account-intent',
);
