import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        WorkflowDefinition,
        WorkflowStateKind,
        WorkflowTransition,
        connectionId,
        replaceTransition,
        stateTitle,
        transitionWith;
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../mode_editor_support.dart';
import 'mode_editor_fields.dart';
import 'mode_detail_sections.dart';
import 'mode_stage_detail_panel.dart' show WorkflowTransitionRef;

/// 转换详情面板：点击连线后展示来源、目标与完整转换条件。
///
/// 来源/目标阶段均可点击跳转到对应阶段详情；编辑态提供端点与条件编辑。
class ModeTransitionDetailPanel extends StatelessWidget {
  const ModeTransitionDetailPanel({
    super.key,
    required this.document,
    required this.workflow,
    required this.transition,
    required this.readOnly,
    required this.l10n,
    required this.onDocumentChanged,
    required this.onSelectStage,
    required this.onSelectTransition,
    required this.onDeleteTransition,
  });

  final ModeDocument document;
  final WorkflowDefinition workflow;
  final WorkflowTransition transition;
  final bool readOnly;
  final AppLocalizations l10n;
  final ValueChanged<ModeDocument> onDocumentChanged;
  final ValueChanged<String> onSelectStage;
  final ValueChanged<String> onSelectTransition;
  final ValueChanged<WorkflowTransitionRef> onDeleteTransition;

  void _updateEndpoints(
    BuildContext context, {
    String? source,
    String? target,
  }) {
    final nextSource = source ?? transition.sourceStateId;
    final nextTarget = target ?? transition.targetStateId;
    final duplicate = workflow.transitions.any(
      (existing) =>
          !identical(existing, transition) &&
          existing.sourceStateId == nextSource &&
          existing.targetStateId == nextTarget,
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.modeEditorDuplicateTransition)),
      );
      return;
    }
    final next = transitionWith(
      transition,
      sourceStateId: nextSource,
      targetStateId: nextTarget,
    );
    onDocumentChanged(replaceTransition(document, transition, next));
    onSelectTransition(connectionId(next));
  }

  @override
  Widget build(BuildContext context) {
    final atomic = workflow.states
        .where((state) => state.kind == WorkflowStateKind.atomic)
        .toList(growable: false);
    final sourceTitle = stateTitle(workflow, transition.sourceStateId);
    final targetTitle = stateTitle(workflow, transition.targetStateId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('mode-editor-detail-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            children: [
              Text(
                '$sourceTitle → $targetTitle',
                style: context.text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              if (readOnly) ...[
                ModeDetailSection(
                  title: l10n.modeEditorSourceState,
                  child: ModeDetailStageLink(
                    title: sourceTitle,
                    subtitle: transition.sourceStateId,
                    onTap: () => onSelectStage(transition.sourceStateId),
                  ),
                ),
                Center(
                  child: Icon(
                    Icons.south,
                    size: 18,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.modeEditorTargetState,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 12),
                ModeDetailStageLink(
                  title: targetTitle,
                  subtitle: transition.targetStateId,
                  onTap: () => onSelectStage(transition.targetStateId),
                ),
                ModeDetailSection(
                  title: l10n.modeEditorTransitionGuard,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(StudioRadii.sm),
                    ),
                    child: SelectableText(
                      transition.guard.isEmpty
                          ? l10n.modeEditorGuardRequiredShort
                          : transition.guard,
                      style: context.text.bodyMedium?.copyWith(height: 1.65),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.modeEditorTransitionRuleHint,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'mode-editor-detail-edge-source-'
                    '${transition.sourceStateId}-${transition.targetStateId}',
                  ),
                  initialValue:
                      atomic.any(
                        (state) => state.id == transition.sourceStateId,
                      )
                      ? transition.sourceStateId
                      : null,
                  decoration: InputDecoration(
                    labelText: l10n.modeEditorSourceState,
                  ),
                  items: [
                    for (final state in atomic)
                      DropdownMenuItem(
                        value: state.id,
                        child: Text(state.title),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _updateEndpoints(context, source: value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'mode-editor-detail-edge-target-'
                    '${transition.sourceStateId}-${transition.targetStateId}',
                  ),
                  initialValue:
                      workflow.states.any(
                        (state) => state.id == transition.targetStateId,
                      )
                      ? transition.targetStateId
                      : null,
                  decoration: InputDecoration(
                    labelText: l10n.modeEditorTargetState,
                  ),
                  items: [
                    for (final state in workflow.states)
                      DropdownMenuItem(
                        value: state.id,
                        child: Text(state.title),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _updateEndpoints(context, target: value);
                  },
                ),
                const SizedBox(height: 12),
                ModeEditorTextField(
                  key: ModeEditorKeys.detailField('edge-guard'),
                  label: l10n.modeEditorTransitionGuard,
                  value: transition.guard,
                  minLines: 4,
                  maxLines: 10,
                  onChanged: (value) {
                    final next = transitionWith(transition, guard: value);
                    onDocumentChanged(
                      replaceTransition(document, transition, next),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.modeEditorTransitionRuleHint,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
        if (readOnly)
          ModeDetailReadOnlyNotice(text: l10n.modeEditorCatalogReadOnlyHint),
        if (!readOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: OutlinedButton.icon(
              key: ModeEditorKeys.deleteTransition,
              onPressed: () => onDeleteTransition((
                sourceStateId: transition.sourceStateId,
                targetStateId: transition.targetStateId,
              )),
              icon: const Icon(Icons.delete_outline, size: 17),
              label: Text(l10n.modeEditorDeleteTransition),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
              ),
            ),
          ),
      ],
    );
  }
}
