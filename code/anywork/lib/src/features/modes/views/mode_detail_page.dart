import 'package:anywork_client/studio_client.dart'
    show ModeEditorState, WorkflowState, WorkflowTransition;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';

import 'package:go_router/go_router.dart';

import '../../../presentation/providers/client_provider.dart';
import '../../../presentation/providers/mode_editor_store.dart';
import '../state/mode_workspace_view_state.dart';
import '../view_models/mode_workspace_controller.dart';
import '../mode_editor_support.dart';
import '../widgets/mode_stage_detail_panel.dart';
import '../widgets/mode_transition_detail_panel.dart';
import '../connectors/mode_editor_actions.dart';

/// 窄屏下的详情子路由页（`mode-detail`）。
///
/// 消费工作区控制器的选中状态；返回时清除选中并回到流程画布。下层
/// 工作区页面保持 mounted，画布视口与缩放因此保留。
class ModeDetailPage extends ConsumerWidget {
  const ModeDetailPage({
    super.key,
    required this.modeId,
    this.stage,
    this.edge,
  });

  final String modeId;
  final String? stage;
  final String? edge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(modeEditorStateProvider);
    final selection = ref.watch(
      modeWorkspaceControllerProvider.select((state) => state.selection),
    );
    final isStage = _resolvedSelection(ref, selection) is ModeStageSelection;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(modeWorkspaceControllerProvider.notifier).closeDetail();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(key: ModeEditorKeys.detailBack),
          title: Text(
            isStage
                ? context.l10n.modeEditorDetailStage
                : context.l10n.modeEditorDetailTransition,
          ),
        ),
        body: _body(context, ref, editor: editor, liveSelection: selection),
      ),
    );
  }

  /// 状态恢复（selection 已丢失）时按路由 query 回退推断详情类型。
  ModeDetailSelection? _resolvedSelection(
    WidgetRef ref,
    ModeDetailSelection? selection,
  ) {
    if (selection != null) return selection;
    if (stage != null && stage!.isNotEmpty) {
      return ModeDetailSelection.stage(stage!);
    }
    final id = edge;
    if (id != null && id.startsWith('edge:')) {
      final body = id.substring(5);
      final arrow = body.indexOf('->');
      if (arrow > 0 && arrow + 2 < body.length) {
        return ModeDetailSelection.transition(
          sourceStateId: body.substring(0, arrow),
          targetStateId: body.substring(arrow + 2),
        );
      }
    }
    return null;
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref, {
    required ModeEditorState editor,
    required ModeDetailSelection? liveSelection,
  }) {
    final selection = _resolvedSelection(ref, liveSelection);
    final document = editor.document;
    final workflow = document?.definition.workflow;
    if (document == null || workflow == null || selection == null) {
      return Center(
        child: Text(
          context.l10n.modeEditorInspectorSelectHint,
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }
    final readOnly = editor.readOnly || editor.busy;
    final notifier = ref.read(modeWorkspaceControllerProvider.notifier);
    void replace(next) =>
        ref.read(anyworkClientProvider).modeEditor.replace(next);

    switch (selection) {
      case ModeStageSelection(:final stateId):
        WorkflowState? state;
        for (final candidate in workflow.states) {
          if (candidate.id == stateId) state = candidate;
        }
        if (state == null) break;
        return ModeStageDetailPanel(
          document: document,
          workflow: workflow,
          state: state,
          readOnly: readOnly,
          l10n: context.l10n,
          onDocumentChanged: replace,
          onSelectTransition: notifier.selectTransition,
          onRenameState: (state) =>
              renameWorkflowStageDialog(context, ref, state),
          onDeleteState: (state) async {
            if (await confirmRemoveWorkflowStage(context, ref, state.id)) {
              removeWorkflowStage(ref, state.id);
            }
          },
          onDeleteTransition: (target) => removeWorkflowTransition(ref, target),
          onAddTransitionFrom: (source) =>
              addWorkflowTransitionDialog(context, ref, sourceStateId: source),
        );
      case ModeTransitionSelection(:final sourceStateId, :final targetStateId):
        WorkflowTransition? transition;
        for (final candidate in workflow.transitions) {
          if (candidate.sourceStateId == sourceStateId &&
              candidate.targetStateId == targetStateId) {
            transition = candidate;
          }
        }
        if (transition == null) break;
        return ModeTransitionDetailPanel(
          document: document,
          workflow: workflow,
          transition: transition,
          readOnly: readOnly,
          l10n: context.l10n,
          onDocumentChanged: replace,
          onSelectStage: notifier.selectStage,
          onSelectTransition: notifier.selectTransition,
          onDeleteTransition: (target) {
            removeWorkflowTransition(ref, target);
            if (context.canPop()) context.pop();
          },
        );
    }
    return const SizedBox.shrink();
  }
}
