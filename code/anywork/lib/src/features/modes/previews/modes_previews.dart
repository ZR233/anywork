import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        ModeEditorLayout,
        ModeDefinition,
        WorkflowDefinition,
        WorkflowState,
        WorkflowStateKind,
        WorkflowTransition;
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../app/theme/material3_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/mode_stage_detail_panel.dart';
import '../widgets/mode_transition_detail_panel.dart';

ModeDocument _fixtureDocument() => ModeDocument(
  definition: ModeDefinition(
    id: 'mode.preview',
    displayName: '预览模式',
    description: '合成数据',
    order: 10,
    prompt: '',
    workflow: WorkflowDefinition(
      title: '任务流程',
      goal: '完成预览',
      initialStateId: 'planning',
      states: [
        WorkflowState(
          id: 'planning',
          title: '规划',
          instructions: '拆解需求并确认边界，识别风险与依赖。',
          completionCriteria: ['范围确认', '风险清单'],
          kind: WorkflowStateKind.atomic,
        ),
        WorkflowState(
          id: 'working',
          title: '实现',
          instructions: '按计划推进实现并验证结果。',
          completionCriteria: ['实现完成', '自测通过'],
          kind: WorkflowStateKind.atomic,
        ),
        WorkflowState(
          id: 'completed',
          title: '完成',
          instructions: '',
          completionCriteria: const [],
          kind: WorkflowStateKind.finalState,
        ),
      ],
      transitions: [
        WorkflowTransition(
          sourceStateId: 'planning',
          targetStateId: 'working',
          guard: '计划已确认且风险可控，允许进入实现',
        ),
        WorkflowTransition(
          sourceStateId: 'working',
          targetStateId: 'completed',
          guard: '实现完成且验证通过，交付最终结果',
        ),
        WorkflowTransition(
          sourceStateId: 'working',
          targetStateId: 'planning',
          guard: '实现发现计划缺口，返回规划补充',
        ),
      ],
    ),
  ),
  editor: const ModeEditorLayout(nodes: []),
);

class _PanelHost extends StatelessWidget {
  const _PanelHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

Widget _stagePanel({required bool readOnly}) {
  final document = _fixtureDocument();
  final workflow = document.definition.workflow!;
  return _PanelHost(
    child: ModeStageDetailPanel(
      document: document,
      workflow: workflow,
      state: workflow.states.first,
      readOnly: readOnly,
      l10n: lookupAppLocalizations(const Locale('zh')),
      onDocumentChanged: (_) {},
      onSelectTransition: (_) {},
      onRenameState: (_) {},
      onDeleteState: (_) {},
      onDeleteTransition: (_) {},
      onAddTransitionFrom: (_) {},
    ),
  );
}

Widget _transitionPanel({required bool readOnly}) {
  final document = _fixtureDocument();
  final workflow = document.definition.workflow!;
  return _PanelHost(
    child: ModeTransitionDetailPanel(
      document: document,
      workflow: workflow,
      transition: workflow.transitions.first,
      readOnly: readOnly,
      l10n: lookupAppLocalizations(const Locale('zh')),
      onDocumentChanged: (_) {},
      onSelectStage: (_) {},
      onSelectTransition: (_) {},
      onDeleteTransition: (_) {},
    ),
  );
}

// 合成数据 · 动作仅本地记录；预览不装配 Client/Provider/FRB。
@Preview(name: '阶段详情 / 编辑态', group: 'Modes · 阶段详情', size: Size(360, 760))
Widget stageDetailEditablePreview() => _stagePanel(readOnly: false);

@Preview(name: '阶段详情 / 内置只读', group: 'Modes · 阶段详情', size: Size(360, 760))
Widget stageDetailReadOnlyPreview() => _stagePanel(readOnly: true);

@Preview(name: '转换详情 / 编辑态', group: 'Modes · 转换详情', size: Size(360, 760))
Widget transitionDetailEditablePreview() => _transitionPanel(readOnly: false);

@Preview(name: '转换详情 / 内置只读', group: 'Modes · 转换详情', size: Size(360, 760))
Widget transitionDetailReadOnlyPreview() => _transitionPanel(readOnly: true);
