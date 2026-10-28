import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/mode_workspace_view_state.dart';

part 'mode_workspace_controller.g.dart';

/// Mode 工作区界面状态的唯一 owner。
///
/// 只管理呈现状态；文档草稿的读取、编辑与命令仍全部经 Client
/// `ModeEditorOwner`（见 design/25 §25.12），控制器不复制任何业务事实。
@riverpod
class ModeWorkspaceController extends _$ModeWorkspaceController {
  @override
  ModeWorkspaceViewState build() => const ModeWorkspaceViewState();

  void selectStage(String? stateId) {
    if (stateId == null) {
      if (state.selection == null) return;
      state = state.copyWith(selection: null);
      return;
    }
    final current = state.selection;
    if (current is ModeStageSelection && current.stateId == stateId) return;
    state = state.copyWith(
      selection: ModeDetailSelection.stage(stateId),
      section: state.section == ModeWorkspaceSection.flow
          ? state.section
          : state.section,
    );
  }

  void selectTransition(String? edgeId) {
    if (edgeId == null) {
      if (state.selection == null) return;
      state = state.copyWith(selection: null);
      return;
    }
    final parts = _parseEdgeId(edgeId);
    if (parts == null) return;
    final current = state.selection;
    if (current is ModeTransitionSelection &&
        current.sourceStateId == parts.$1 &&
        current.targetStateId == parts.$2) {
      return;
    }
    state = state.copyWith(
      selection: ModeDetailSelection.transition(
        sourceStateId: parts.$1,
        targetStateId: parts.$2,
      ),
    );
  }

  void closeDetail() {
    if (state.selection == null) return;
    state = state.copyWith(selection: null);
  }

  void setSection(ModeWorkspaceSection section) {
    if (state.section == section) return;
    state = state.copyWith(section: section);
  }

  void setFocus(ModeWorkflowFocus focus) {
    if (state.focus == focus) return;
    state = state.copyWith(focus: focus);
  }

  void requestValidation() {
    state = state.copyWith(validationRequested: true);
  }

  void clearValidationRequest() {
    if (!state.validationRequested) return;
    state = state.copyWith(validationRequested: false);
  }

  void setPreviewReason(String reason) {
    if (state.previewReason == reason) return;
    state = state.copyWith(previewReason: reason);
  }

  /// 文档切换后重置与旧文档绑定的呈现状态。
  void resetForDocument() {
    state = state.copyWith(
      selection: null,
      validationRequested: false,
      focus: ModeWorkflowFocus.all,
    );
  }

  (String, String)? _parseEdgeId(String edgeId) {
    if (!edgeId.startsWith('edge:')) return null;
    final body = edgeId.substring(5);
    final arrow = body.indexOf('->');
    if (arrow <= 0 || arrow + 2 >= body.length) return null;
    return (body.substring(0, arrow), body.substring(arrow + 2));
  }
}
