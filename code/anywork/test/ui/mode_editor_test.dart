import 'package:anywork/src/features/modes/mode_editor_dialogs.dart';
import 'package:anywork/src/features/modes/mode_editor_support.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart'
    show WorkflowTransition, workflowWith;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'Transition dialog requires an atomic source and accepts a final target',
    (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final workflow = workflowWith(
        minimalWorkflow(l10n),
        transitions: const [],
      );
      WorkflowTransition? submitted;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  submitted = await showTransitionDialog(
                    context,
                    workflow: workflow,
                    initialSourceId: 'done',
                  );
                },
                child: const Text('Open transition dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open transition dialog'));
      await tester.pumpAndSettle();

      final source = find.byKey(ModeEditorKeys.detailField('new-source'));
      final target = find.byKey(ModeEditorKeys.detailField('new-target'));
      final confirm = find.byKey(
        const ValueKey('mode-editor-transition-confirm'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text(l10n.modeEditorChooseSource), findsOneWidget);
      expect(submitted, isNull);

      await tester.tap(source);
      await tester.pumpAndSettle();
      expect(find.text(l10n.modeEditorDone).hitTestable(), findsNothing);
      await tester.tap(find.text(l10n.modeEditorStart).last);
      await tester.pumpAndSettle();

      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.modeEditorDone).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ModeEditorKeys.detailField('new-guard')),
        '  Finish after review  ',
      );

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(submitted?.sourceStateId, 'start');
      expect(submitted?.targetStateId, 'done');
      expect(submitted?.guard, 'Finish after review');
    },
  );
}
