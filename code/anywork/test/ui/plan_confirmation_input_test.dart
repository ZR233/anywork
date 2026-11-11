import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/interactions/views/plan_confirmation_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('计划反馈使用默认多行编辑，只有明确按钮提交决定', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var revisions = 0;
    var approvals = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlanConfirmationView(
              controller: controller,
              available: true,
              enabled: true,
              error: null,
              onFeedbackChanged: (_) => setState(() {}),
              onSubmitRevision: () => revisions++,
              onApprove: () => approvals++,
            ),
          ),
        ),
      ),
    );
    final input = find.byKey(StudioDriverKeys.planFeedbackInput);
    await tester.enterText(input, '第一行');
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    expect(editor.textInputAction, TextInputAction.newline);
    // 平台输入通道传入换行和文本编辑动作，不应变成业务提交。
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '第一行\n第二行',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(controller.text, '第一行\n第二行');
    expect(revisions, 0);
    expect(approvals, 0);
    await tester.tap(find.byKey(StudioDriverKeys.planSubmitRevision));
    await tester.pump();
    expect(revisions, 1);
    await tester.tap(find.byKey(StudioDriverKeys.planApprove));
    await tester.pump();
    expect(approvals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
