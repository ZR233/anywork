import 'package:freezed_annotation/freezed_annotation.dart';

part 'mode_dialog_state.freezed.dart';

enum ModeDialogKind { create, importJson, renameState, transition }

enum ModeTemplateKind { minimal, none }

enum ModeDialogValidation {
  nameRequired,
  invalidModeId,
  modeExists,
  invalidStateId,
  stateExists,
  sourceRequired,
  targetRequired,
  guardRequired,
  duplicateTransition,
}

@Freezed(toStringOverride: false)
abstract class ModeDialogDraft with _$ModeDialogDraft {
  const factory ModeDialogDraft({
    required int generation,
    required ModeDialogKind kind,
    @Default('') String id,
    @Default('') String name,
    @Default(ModeTemplateKind.minimal) ModeTemplateKind template,
    String? originalStateId,
    String? sourceId,
    String? targetId,
    @Default('') String guard,
    ModeDialogValidation? validation,
  }) = _ModeDialogDraft;
}
