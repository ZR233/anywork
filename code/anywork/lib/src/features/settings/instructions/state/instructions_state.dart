import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'instructions_state.freezed.dart';

enum InstructionSection { base, developer, user }
enum InstructionsReadField { content, sourceStatus }

@Freezed(toStringOverride: false)
abstract class InstructionDraft with _$InstructionDraft {
  const factory InstructionDraft({
    required String raw,
    @Default(0) int revision,
    @Default(false) bool dirty,
    SettingsAction? action,
  }) = _InstructionDraft;
}

@Freezed(toStringOverride: false)
abstract class InstructionsViewState with _$InstructionsViewState {
  const factory InstructionsViewState({
    required ConfigurationState source,
    required InstructionsSettings canonical,
    required InstructionDraft base,
    required InstructionDraft developer,
    required InstructionDraft user,
    @Default(InstructionSection.base) InstructionSection section,
    @Default({}) Map<InstructionsReadField, StudioFailure> readIssues,
    @Default(false) bool readPending,
  }) = _InstructionsViewState;
}
