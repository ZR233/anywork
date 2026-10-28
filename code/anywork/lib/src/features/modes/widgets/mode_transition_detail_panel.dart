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
import '../../../l10n/studio_l10n.dart';
import '../mode_editor_support.dart';
import 'mode_editor_fields.dart';
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            children: [
              Row(
                children: [
                  const Icon(Icons.arrow_forward, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.modeEditorStateTransition,
                      style: context.text.titleMedium?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StageLink(
                    label: sourceTitle,
                    onTap: () => onSelectStage(transition.sourceStateId),
                  ),
                  Icon(
                    Icons.trending_flat,
                    size: 15,
                    color: context.colors.onSurfaceVariant,
                  ),
                  _StageLink(
                    label: targetTitle,
                    onTap: () => onSelectStage(transition.targetStateId),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (readOnly) ...[
                _ReadOnlyRow(
                  label: l10n.modeEditorSourceState,
                  text: sourceTitle,
                  onView: () => onSelectStage(transition.sourceStateId),
                ),
                _ReadOnlyRow(
                  label: l10n.modeEditorTargetState,
                  text: targetTitle,
                  onView: () => onSelectStage(transition.targetStateId),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.modeEditorTransitionGuard,
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        transition.guard.isEmpty
                            ? l10n.modeEditorGuardRequiredShort
                            : transition.guard,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  l10n.modeEditorTransitionRuleHint,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
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
        // 内置只读形态常驻提示，替代不可用的编辑控件。
        if (readOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              l10n.modeEditorCatalogReadOnlyHint,
              style: context.text.labelSmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
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

class _StageLink extends StatelessWidget {
  const _StageLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(StudioRadii.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.label,
    required this.text,
    required this.onView,
  });

  final String label;
  final String text;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: SelectableText(text)),
              TextButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: Text(context.l10n.modeEditorViewStage),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
