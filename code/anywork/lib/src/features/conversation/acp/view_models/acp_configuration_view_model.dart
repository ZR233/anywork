import 'package:anywork_client/acp_sessions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../state/acp_view_state.dart';
import 'acp_session_view_model.dart';

part 'acp_configuration_view_model.g.dart';

AcpConfigCategoryKind _mapCategory(AcpConfigCategoryView? category) {
  if (category == null) return AcpConfigCategoryKind.unspecified;
  return switch (category.kind) {
    AcpConfigCategoryKindView.mode => AcpConfigCategoryKind.mode,
    AcpConfigCategoryKindView.model => AcpConfigCategoryKind.model,
    AcpConfigCategoryKindView.modelConfig => AcpConfigCategoryKind.modelConfig,
    AcpConfigCategoryKindView.thoughtLevel =>
      AcpConfigCategoryKind.thoughtLevel,
    AcpConfigCategoryKindView.other => AcpConfigCategoryKind.other,
  };
}

AcpSelectChoicePresentation _mapChoice(AcpSelectOptionView option) =>
    AcpSelectChoicePresentation(
      value: option.value.value,
      name: option.name,
      description: option.description,
    );

/// Pure mapping of server-owned configuration or legacy modes into immutable
/// presentation controls. Preserves exact server array order and never falls
/// back to `modes` when `options` is non-null (even if empty).
List<AcpConfigControlPresentation> mapAcpConfigControls({
  required List<AcpSessionConfigOptionView>? options,
  required AcpSessionModeStateView? modes,
}) {
  if (options != null) {
    return [
      for (final option in options)
        switch (option.kind) {
          AcpSelectConfigView(:final currentValue, options: final choices) =>
            () {
              final current = currentValue.value;
              var currentLabel = current;
              final flat = <AcpSelectChoicePresentation>[];
              final groups = <AcpSelectGroupPresentation>[];
              switch (choices) {
                case AcpUngroupedOptionsView(options: final items):
                  for (final item in items) {
                    if (item.value.value == current) {
                      currentLabel = item.name;
                    }
                    flat.add(_mapChoice(item));
                  }
                case AcpGroupedOptionsView(groups: final groupItems):
                  for (final group in groupItems) {
                    final groupChoices = <AcpSelectChoicePresentation>[];
                    for (final item in group.options) {
                      if (item.value.value == current) {
                        currentLabel = item.name;
                      }
                      groupChoices.add(_mapChoice(item));
                    }
                    groups.add(
                      AcpSelectGroupPresentation(
                        id: group.group.value,
                        name: group.name,
                        options: groupChoices,
                      ),
                    );
                  }
              }
              return AcpConfigControlPresentation.select(
                id: option.id.value,
                name: option.name,
                description: option.description,
                category: _mapCategory(option.category),
                currentValue: current,
                currentLabel: currentLabel,
                flatOptions: flat,
                groups: groups,
              );
            }(),
          AcpBooleanConfigView(:final currentValue) =>
            AcpConfigControlPresentation.boolean(
              id: option.id.value,
              name: option.name,
              description: option.description,
              category: _mapCategory(option.category),
              currentValue: currentValue,
            ),
        },
    ];
  }

  if (modes != null && modes.availableModes.isNotEmpty) {
    final currentId = modes.currentModeId.value;
    var currentLabel = currentId;
    String? currentDescription;
    final choices = <AcpSelectChoicePresentation>[];
    for (final mode in modes.availableModes) {
      if (mode.id.value == currentId) {
        currentLabel = mode.name;
        currentDescription = mode.description;
      }
      choices.add(
        AcpSelectChoicePresentation(
          value: mode.id.value,
          name: mode.name,
          description: mode.description,
        ),
      );
    }
    return [
      AcpConfigControlPresentation.legacyMode(
        id: AcpViewKeyValues.configLegacyMode,
        description: currentDescription,
        currentModeId: currentId,
        currentModeLabel: currentLabel,
        modes: choices,
      ),
    ];
  }

  return const [];
}

@riverpod
class AcpConfigurationViewModel extends _$AcpConfigurationViewModel {
  @override
  AcpConfigurationViewState build(String threadId) {
    final asyncState = ref.watch(acpConversationStateProvider(threadId));
    final state = asyncState.value;
    final error = state?.configError;
    return AcpConfigurationViewState(
      controls: mapAcpConfigControls(
        options: state?.configOptions,
        modes: state?.modes,
      ),
      pending: state?.configPending ?? false,
      enabled:
          state != null &&
          state.ready &&
          !state.openPending &&
          !state.disconnected &&
          !state.observationEnded,
      errorMessage: error == null ? null : formatAcpError(error),
    );
  }

  Future<void> selectValue(String configId, String valueId) =>
      coordinateAcpSessionCommand(
        ref.read(anyworkClientProvider),
        threadId,
        (owner) => owner.configure(
          AcpConfigId(configId),
          AcpSelectConfigValueView(AcpConfigValueId(valueId)),
        ),
      );

  Future<void> setBoolean(String configId, bool value) =>
      coordinateAcpSessionCommand(
        ref.read(anyworkClientProvider),
        threadId,
        (owner) => owner.configure(
          AcpConfigId(configId),
          AcpBooleanConfigValueView(value),
        ),
      );

  Future<void> selectLegacyMode(String modeId) => coordinateAcpSessionCommand(
    ref.read(anyworkClientProvider),
    threadId,
    (owner) => owner.setMode(AcpModeId(modeId)),
  );
}
