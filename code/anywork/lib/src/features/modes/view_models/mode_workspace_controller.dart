import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../mode_editor_support.dart';
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

  void selectStage(String? stateId) =>
      _select(stateId == null ? null : ModeDetailSelection.stage(stateId));

  void selectTransition(String? edgeId) {
    if (edgeId == null) {
      closeDetail();
      return;
    }
    final selection = parseModeTransitionSelection(edgeId);
    if (selection != null) _select(selection);
  }

  void closeDetail() => _select(null);

  void _select(ModeDetailSelection? selection) {
    if (state.selection == selection) return;
    state = state.copyWith(selection: selection);
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
}
