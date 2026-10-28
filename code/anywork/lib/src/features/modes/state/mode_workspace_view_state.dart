import 'package:freezed_annotation/freezed_annotation.dart';

part 'mode_workspace_view_state.freezed.dart';

/// 工作区当前展示的内容分区。
enum ModeWorkspaceSection { flow, preview, json, settings }

/// 画布聚焦模式：全部转换可见，或仅聚焦所选节点相关路径。
enum ModeWorkflowFocus { all, focused }

/// 画布上被选中并要求展示详情的对象。
@freezed
sealed class ModeDetailSelection with _$ModeDetailSelection {
  const factory ModeDetailSelection.stage(String stateId) = ModeStageSelection;

  const factory ModeDetailSelection.transition({
    required String sourceStateId,
    required String targetStateId,
  }) = ModeTransitionSelection;
}

/// Mode 工作区的界面状态；文档草稿本体归 Client `ModeEditorOwner` 所有，
/// 这里只持有纯呈现状态（选中、分区、聚焦、校验请求与预演输入）。
@freezed
abstract class ModeWorkspaceViewState with _$ModeWorkspaceViewState {
  const factory ModeWorkspaceViewState({
    @Default(ModeWorkspaceSection.flow) ModeWorkspaceSection section,
    ModeDetailSelection? selection,
    @Default(ModeWorkflowFocus.all) ModeWorkflowFocus focus,
    @Default(false) bool validationRequested,
    @Default('') String previewReason,
  }) = _ModeWorkspaceViewState;
}
