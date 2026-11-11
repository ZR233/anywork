import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/interactions/views/plan_confirmation_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('计划反馈仅在输入框聚焦时以 Enter 提交，Shift+Enter 保留换行', (tester) async {
    var revisions = 0;
    var approvals = 0;
    String? submittedFeedback;
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
          body: PlanConfirmationView(
            interactionId: 'interaction-1',
            available: true,
            enabled: true,
            error: null,
            onSubmitRevision: (feedback) {
              submittedFeedback = feedback;
              revisions++;
            },
            onApprove: () => approvals++,
          ),
        ),
      ),
    );
    final input = find.byKey(StudioDriverKeys.planFeedbackInput);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(StudioDriverKeys.planSubmitRevision),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(input, '第一行');
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    expect(editor.textInputAction, TextInputAction.send);
    expect(editor.focusNode.hasFocus, isTrue);
    // Shift+Enter is a field-local newline action; it must not submit.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(revisions, 0);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '第一行\n',
    );
    // An active IME composing range must not submit.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '第一行\n第二行',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(revisions, 0);
    // Ordinary Enter comes through the platform's send action after composition ends.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '第一行\n第二行',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(revisions, 1);
    expect(submittedFeedback, '第一行\n第二行');
    expect(approvals, 0);
    await tester.tap(find.byKey(StudioDriverKeys.planSubmitRevision));
    await tester.pump();
    expect(revisions, 2);
    await tester.tap(find.byKey(StudioDriverKeys.planApprove));
    await tester.pump();
    expect(approvals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('失焦后 Enter 不劫持其他控件', (tester) async {
    var revisions = 0;
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
          body: Column(
            children: [
              PlanConfirmationView(
                interactionId: 'interaction-2',
                available: true,
                enabled: true,
                error: null,
                onSubmitRevision: (_) => revisions++,
                onApprove: () {},
              ),
              const TextField(key: ValueKey('other-input')),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(StudioDriverKeys.planFeedbackInput),
      'please revise',
    );
    await tester.tap(find.byKey(const ValueKey('other-input')));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(revisions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
