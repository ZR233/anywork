import 'dart:ui' show CheckedState;

import 'package:anywork/src/features/conversation/interactions/state/interaction_payload.dart';
import 'package:anywork/src/features/conversation/interactions/views/user_input_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('custom answers survive navigation and submit with choices', (
    tester,
  ) async {
    UserInputResolutionCommand? submitted;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UserInputView(
            payload: const InteractionPayloadSnapshot(
              rawBody: '',
              summary: '',
              toolName: '',
              formattedArguments: '',
              workingDirectory: '',
              questions: [
                UserQuestionView(
                  id: 'choices',
                  header: 'Choose',
                  question: '',
                  isSecret: false,
                  options: [
                    UserQuestionOptionView(label: 'Alpha', description: ''),
                  ],
                ),
                UserQuestionView(
                  id: 'secret',
                  header: 'Enter a secret',
                  question: '',
                  isSecret: true,
                  options: [],
                ),
              ],
            ),
            enabled: true,
            onSubmit: (value) => submitted = value,
          ),
        ),
      ),
    );

    final custom = find.byKey(StudioDriverKeys.userInputFirstText);
    final secret = find.byKey(StudioDriverKeys.userInputText('secret'));
    final next = find.byKey(StudioDriverKeys.userInputSubmit);
    expect(custom, findsOneWidget);
    await tester.tap(find.text('Alpha'));
    await tester.enterText(custom, '  Another answer  ');
    await tester.tap(next);
    await tester.pump();
    expect(tester.widget<TextField>(secret).obscureText, isTrue);
    await tester.enterText(secret, 'secret value');
    await tester.tap(find.widgetWithIcon(TextButton, Icons.chevron_left));
    await tester.pump();
    expect(find.text('  Another answer  '), findsOneWidget);
    await tester.tap(next);
    await tester.pump();
    await tester.tap(next);

    expect(submitted!.answers.map((answer) => answer.questionId), [
      'choices',
      'secret',
    ]);
    expect(submitted!.answers[0].answers, ['Alpha', 'Another answer']);
    expect(submitted!.answers[1].answers, ['secret value']);
  });

  testWidgets(
    'question choices support multiple answers and keyboard toggling',
    (tester) async {
      // testWidgets enables semantics and owns the handle's full lifetime.
      UserInputResolutionCommand? submitted;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: UserInputView(
              payload: const InteractionPayloadSnapshot(
                rawBody: '',
                summary: '',
                toolName: '',
                formattedArguments: '',
                workingDirectory: '',
                questions: [
                  UserQuestionView(
                    id: 'choices',
                    header: 'Choose',
                    question: '',
                    isSecret: false,
                    options: [
                      UserQuestionOptionView(label: 'Alpha', description: ''),
                      UserQuestionOptionView(label: 'Beta', description: ''),
                    ],
                  ),
                ],
              ),
              enabled: true,
              onSubmit: (value) => submitted = value,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Beta'));
      await tester.pump();
      expect(
        // CheckboxListTile exposes one merged node. Read its effective data,
        // including the child Checkbox's checked state, not its own flags.
        tester
            .getSemantics(find.text('Alpha'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      await tester.tap(find.byKey(StudioDriverKeys.userInputSubmit));
      expect(submitted!.answers.single.questionId, 'choices');
      expect(submitted!.answers.single.answers, ['Alpha', 'Beta']);

      Focus.of(tester.element(find.text('Alpha'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
        tester
            .getSemantics(find.text('Alpha'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isFalse,
      );
      expect(
        tester
            .getSemantics(find.text('Beta'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      await tester.tap(find.byKey(StudioDriverKeys.userInputSubmit));
      expect(submitted!.answers.single.answers, ['Beta']);
    },
  );

  testWidgets(
    'fallback answer freezes while unavailable and retains its draft',
    (tester) async {
      UserInputResolutionCommand? submitted;
      Widget host({required bool enabled}) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UserInputView(
            payload: const InteractionPayloadSnapshot(
              rawBody: 'Provide a value',
              summary: '',
              toolName: '',
              formattedArguments: '',
              workingDirectory: '',
              questions: [],
            ),
            enabled: enabled,
            onSubmit: (value) => submitted = value,
          ),
        ),
      );

      final input = find.byKey(StudioDriverKeys.fallbackUserInput);
      final submit = find.byKey(StudioDriverKeys.fallbackUserInputSubmit);
      await tester.pumpWidget(host(enabled: true));
      await tester.enterText(input, 'retained answer');
      await tester.pumpWidget(host(enabled: false));
      expect(tester.widget<TextField>(input).enabled, isFalse);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'retained answer',
      );
      await tester.tap(submit);
      expect(submitted, isNull);

      await tester.pumpWidget(host(enabled: true));
      await tester.tap(submit);
      expect(submitted!.answers.single.questionId, 'answer');
      expect(submitted!.answers.single.answers, ['retained answer']);
    },
  );
}
