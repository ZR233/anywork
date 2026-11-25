import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/modes/mode_editor_support.dart';
import 'package:anywork/src/features/modes/widgets/mode_workflow_canvas.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart'
    show ModeDocument, setNodePosition;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

void main() {
  testWidgets(
    'Selection projection preserves current and pending editor focus',
    (tester) async {
      final titleFocus = FocusNode();
      final guardFocus = FocusNode();
      addTearDown(titleFocus.dispose);
      addTearDown(guardFocus.dispose);
      final l10n = lookupAppLocalizations(const Locale('en'));
      var document = ModeDocument(
        definition: newModeDefinition(
          id: 'mode.focus-test',
          displayName: 'Focus test',
          order: 10,
          template: ModeTemplateKind.minimal,
          l10n: l10n,
        ),
      );
      String? selectedStateId;
      String? selectedEdgeId;
      final selections = <String?>[];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: pureStudioTheme(locale: const Locale('en')),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Row(
                  children: [
                    Expanded(
                      child: ModeWorkflowCanvas(
                        document: document,
                        readOnly: false,
                        l10n: l10n,
                        dimmedStateIds: const {},
                        selectedStateId: selectedStateId,
                        selectedEdgeId: selectedEdgeId,
                        onSelectStage: selections.add,
                        onSelectTransition: selections.add,
                        onDocumentChanged: (_) {},
                        onAddStage: () {},
                        onAddFinalStage: () {},
                        onAddTransition: () {},
                        onConfirmRemoveStage: (_) async => false,
                        onRemoveStage: (_) {},
                        onRemoveTransition: (_, _) {},
                        onCreateTransition: (_, _) {},
                        onAutoLayout: () {},
                        onEnableWorkflow: () {},
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: Column(
                        children: [
                          TextField(focusNode: titleFocus),
                          TextField(focusNode: guardFocus),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = tester
          .widget<NodeFlowEditor<dynamic, Object?>>(
            find.byKey(ModeEditorKeys.canvas),
          )
          .controller;
      titleFocus.requestFocus();
      await tester.pump();
      expect(titleFocus.hasPrimaryFocus, isTrue);

      update(() => selectedStateId = 'start');
      await tester.pump();
      await tester.pump();
      expect(controller.selectedNodeIds, {'start'});
      expect(titleFocus.hasPrimaryFocus, isTrue);

      update(() {
        document = setNodePosition(document, 'start', (x: 64.0, y: 48.0));
        selectedStateId = null;
        selectedEdgeId = 'edge:start->done';
      });
      // This callback is queued before the canvas schedules its own projection.
      // A request is pending until Flutter commits the focus change in a microtask.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => guardFocus.requestFocus(),
      );
      await tester.pump();
      await tester.pump();
      expect(controller.selectedConnectionIds, {'edge:start->done'});
      expect(controller.selectedNodeIds, isEmpty);
      expect(guardFocus.hasPrimaryFocus, isTrue);
      expect(selections, isEmpty);

      await tester.tap(find.byKey(ModeEditorKeys.node('start')));
      await tester.pumpAndSettle();
      expect(selections.whereType<String>(), ['start']);
      expect(controller.canvasFocusNode.hasPrimaryFocus, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
