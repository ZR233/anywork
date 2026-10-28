import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        WorkflowDefinition,
        WorkflowState,
        WorkflowStateKind,
        completionCriteriaText,
        connectionId,
        documentWithWorkflow,
        parseCompletionCriteria,
        replaceState,
        stateTitle,
        stateWith,
        workflowWith;
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../mode_editor_support.dart';
import 'mode_editor_fields.dart';
import 'mode_detail_sections.dart';

/// 阶段详情面板：点击阶段卡片后展示的完整阶段信息。
///
/// 编辑态提供字段编辑；内置只读形态为纯展示（无禁用的编辑控件），
/// 并通过回调支持跳转到关联转换详情。
class ModeStageDetailPanel extends StatelessWidget {
  const ModeStageDetailPanel({
    super.key,
    required this.document,
    required this.workflow,
    required this.state,
    required this.readOnly,
    required this.l10n,
    required this.onDocumentChanged,
    required this.onSelectTransition,
    required this.onRenameState,
    required this.onDeleteState,
    required this.onDeleteTransition,
    required this.onAddTransitionFrom,
  });

  final ModeDocument document;
  final WorkflowDefinition workflow;
  final WorkflowState state;
  final bool readOnly;
  final AppLocalizations l10n;
  final ValueChanged<ModeDocument> onDocumentChanged;
  final ValueChanged<String> onSelectTransition;
  final ValueChanged<WorkflowState> onRenameState;
  final ValueChanged<WorkflowState> onDeleteState;
  final ValueChanged<WorkflowTransitionRef> onDeleteTransition;
  final ValueChanged<String> onAddTransitionFrom;

  void _update(WorkflowState next) {
    onDocumentChanged(replaceState(document, state.id, next));
  }

  @override
  Widget build(BuildContext context) {
    final initial = workflow.initialStateId == state.id;
    final finalStage = state.kind == WorkflowStateKind.finalState;
    final outgoing = workflow.transitions
        .where((transition) => transition.sourceStateId == state.id)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('mode-editor-detail-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            children: [
              Row(
                children: [
                  Icon(
                    finalStage
                        ? Icons.flag_outlined
                        : Icons.account_tree_outlined,
                    size: 18,
                    color: finalStage
                        ? context.colors.onSurfaceVariant
                        : context.colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.title.isEmpty ? state.id : state.title,
                      style: context.text.titleLarge?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Badge(
                    label: finalStage
                        ? l10n.modeEditorFinalState
                        : l10n.modeEditorAtomicStage,
                  ),
                  if (initial) _Badge(label: l10n.modeEditorInitialBadge),
                  Text(
                    state.id,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      fontFamily: studioCodeFontFamily,
                    ),
                  ),
                  if (!readOnly)
                    IconButton(
                      key: ModeEditorKeys.renameState,
                      tooltip: l10n.modeEditorRenameId,
                      onPressed: () => onRenameState(state),
                      icon: const Icon(Icons.link, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (readOnly) ...[
                ModeDetailSection(
                  title: l10n.modeEditorStageInstructions,
                  child: SelectableText(
                    state.instructions.isEmpty ? '—' : state.instructions,
                    style: context.text.bodyMedium?.copyWith(height: 1.65),
                  ),
                ),
                ModeDetailSection(
                  title: l10n.modeEditorCompletionCriteriaTitle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.completionCriteria.isEmpty) const Text('—'),
                      for (final criterion in state.completionCriteria)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 8, right: 10),
                                child: Icon(Icons.circle, size: 5),
                              ),
                              Expanded(
                                child: SelectableText(
                                  criterion,
                                  style: context.text.bodyMedium?.copyWith(
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ] else ...[
                ModeEditorTextField(
                  key: ModeEditorKeys.detailField('state-title'),
                  label: l10n.modeEditorStageTitle,
                  value: state.title,
                  onChanged: (value) => _update(stateWith(state, title: value)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'mode-editor-detail-kind-${state.id}-${state.kind.name}',
                  ),
                  initialValue: state.kind.name == 'finalState'
                      ? 'final'
                      : 'atomic',
                  decoration: InputDecoration(
                    labelText: l10n.modeEditorStageKind,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'atomic',
                      child: Text(l10n.modeEditorAtomicStage),
                    ),
                    DropdownMenuItem(
                      value: 'final',
                      child: Text(l10n.modeEditorFinalState),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _update(
                      stateWith(
                        state,
                        kind: value == 'final'
                            ? WorkflowStateKind.finalState
                            : WorkflowStateKind.atomic,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: ModeEditorKeys.initialSwitch,
                  contentPadding: EdgeInsets.zero,
                  value: initial,
                  onChanged: initial
                      ? null
                      : (value) {
                          if (!value) return;
                          onDocumentChanged(
                            documentWithWorkflow(
                              document,
                              workflowWith(workflow, initialStateId: state.id),
                            ),
                          );
                        },
                  title: Text(l10n.modeEditorInitialStateSwitch),
                  subtitle: Text(
                    initial
                        ? l10n.modeEditorInitialStateLockedHint
                        : l10n.modeEditorInitialStateHint,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ModeEditorTextField(
                  key: ModeEditorKeys.detailField('state-instructions'),
                  label: l10n.modeEditorStageInstructions,
                  value: state.instructions,
                  minLines: 4,
                  maxLines: 10,
                  onChanged: (value) =>
                      _update(stateWith(state, instructions: value)),
                ),
                const SizedBox(height: 12),
                ModeEditorTextField(
                  key: ModeEditorKeys.detailField('state-criteria'),
                  label: l10n.modeEditorCompletionCriteria,
                  value: completionCriteriaText(state),
                  minLines: 3,
                  maxLines: 8,
                  onChanged: (value) => _update(
                    stateWith(
                      state,
                      completionCriteria: parseCompletionCriteria(value),
                    ),
                  ),
                ),
              ],
              if (state.kind == WorkflowStateKind.atomic &&
                  state.completionCriteria.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.modeEditorAtomicCriteriaRequired,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Divider(height: 1, color: context.colors.outlineVariant),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.modeEditorOutgoingTransitions,
                      style: context.text.titleSmall?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!readOnly)
                    TextButton.icon(
                      key: ModeEditorKeys.inspectorAddTransition,
                      onPressed: () => onAddTransitionFrom(state.id),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(l10n.modeEditorAdd),
                    ),
                ],
              ),
              if (outgoing.isEmpty)
                Text(
                  l10n.modeEditorNoOutgoing,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 12),
              for (final transition in outgoing)
                ModeDetailStageLink(
                  key: ValueKey(
                    'mode-editor-outgoing-${connectionId(transition)}',
                  ),
                  title: stateTitle(workflow, transition.targetStateId),
                  subtitle: transition.guard.isEmpty
                      ? l10n.modeEditorGuardRequiredShort
                      : transition.guard,
                  onTap: () => onSelectTransition(connectionId(transition)),
                  trailing: readOnly
                      ? null
                      : IconButton(
                          tooltip: l10n.modeEditorDeleteTransition,
                          onPressed: () => onDeleteTransition((
                            sourceStateId: transition.sourceStateId,
                            targetStateId: transition.targetStateId,
                          )),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        if (readOnly)
          ModeDetailReadOnlyNotice(text: l10n.modeEditorCatalogReadOnlyHint),
        // 破坏性操作固定在面板底部，不随内容滚动。
        if (!readOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: OutlinedButton.icon(
              key: ModeEditorKeys.deleteState,
              onPressed: () => onDeleteState(state),
              icon: const Icon(Icons.delete_outline, size: 17),
              label: Text(l10n.modeEditorDeleteState),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// 转换引用：以端点标识一条工作流转换（与画布 edge id 同源）。
typedef WorkflowTransitionRef = ({String sourceStateId, String targetStateId});

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.primaryContainer,
        borderRadius: BorderRadius.circular(StudioRadii.pill),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: context.colors.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
