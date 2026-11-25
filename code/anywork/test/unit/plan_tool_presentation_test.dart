import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/tools/items/plan/plan_transition_tool_item.dart';
import 'package:anywork/src/features/conversation/timeline/tools/support/tool_detail_values.dart';
import 'package:anywork/src/features/conversation/timeline/tools/tool_item_adapter.dart';
import 'package:anywork/src/l10n/app_localizations_zh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plan transition presents the target phase and forced transition', () {
    final l10n = AppLocalizationsZh();
    const adapter = PlanTransitionToolItem();
    const presentation = TimelineToolPresentation(
      id: 'plan-1',
      toolCallId: 'call-1',
      name: 'plan_transition',
      presentationContract: 'builtin.plan_transition@1',
      statusString: 'succeeded',
      arguments: '{"targetState":"awaitingConfirmation","force":true,"reason":"按计划推进","content":"# Plan"}',
      output: '{"state":"awaitingConfirmation","forced":true}',
    );
    expect(
      adapter.matcher.matches(
        TimelineToolMatchContext.fromPresentation(presentation),
      ),
      isTrue,
    );
    expect(
      adapter.displayName(l10n, presentation),
      l10n.timelineToolNamePlanTransition,
    );
    final inputs = adapter.input(l10n, presentation.arguments);
    expect(
      inputs.whereType<ToolDetailText>().any(
        (detail) => detail.title == l10n.timelineToolDetailTargetPhase,
      ),
      isTrue,
    );
    expect(
      inputs.whereType<ToolDetailText>().any(
        (detail) =>
            detail.title == l10n.timelineToolDetailForceTransition &&
            detail.text == 'true',
      ),
      isTrue,
    );
    final outputs = adapter.output(l10n, {
      'state': 'awaitingConfirmation',
      'forced': true,
    });
    expect(
      outputs.whereType<ToolDetailText>().any(
        (detail) => detail.title == l10n.timelineToolDetailForceTransition,
      ),
      isTrue,
    );
  });
}
