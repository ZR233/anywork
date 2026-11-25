import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/accounts_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_previews/src/features/settings/accounts/previews/account_preview_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'model focus follows its row while input geometry survives reorder',
    (tester) async {
      final scene = _EditorScene();
      await scene.mount(tester);
      scene.update(() => scene.target = 'last');
      await tester.pumpAndSettle();
      _expectFocusedAndVisible(tester, 'last', 'name');

      const editing = TextEditingValue(
        text: 'composing model name',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 0, end: 9),
      );
      tester.testTextInput.updateEditingValue(editing);
      await tester.pump();
      expect(scene.value.manualModels.last.name.raw, editing.text);

      scene.update(() {
        scene.value = scene.value.copyWith(
          manualModels: scene.value.manualModels.reversed.toList(),
          error: 'An unrelated observation changed',
        );
      });
      await tester.pumpAndSettle();
      expect(_editable(tester, 'last', 'name').controller.value, editing);
      expect(_editable(tester, 'last', 'name').focusNode.hasFocus, isTrue);

      scene.update(() => scene.target = 'first');
      await tester.pumpAndSettle();
      _expectFocusedAndVisible(tester, 'first', 'name');
      scene.update(() => scene.focusId = true);
      await tester.pumpAndSettle();
      _expectFocusedAndVisible(tester, 'first', 'id');
      expect(_editable(tester, 'first', 'name').focusNode.hasFocus, isFalse);
      expect(_editable(tester, 'last', 'name').controller.text, editing.text);
    },
  );

  testWidgets(
    'focus waits for a target row and does not repeat on raw updates',
    (tester) async {
      final scene = _EditorScene()
        ..target = 'new'
        ..focusId = true;
      await scene.mount(tester);
      expect(_editable(tester, 'first', 'id').focusNode.hasFocus, isFalse);

      scene.update(() {
        scene.value = scene.value.copyWith(
          manualModels: [...scene.value.manualModels, _model('new')],
        );
      });
      await tester.pumpAndSettle();
      _expectFocusedAndVisible(tester, 'new', 'id');

      final name = _input('new', 'name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'User chose this input');
      await tester.pumpAndSettle();
      expect(_editable(tester, 'new', 'name').focusNode.hasFocus, isTrue);
      expect(_editable(tester, 'new', 'id').focusNode.hasFocus, isFalse);

      scene.update(
        () => scene.value = scene.value.copyWith(error: 'Refreshed'),
      );
      await tester.pumpAndSettle();
      expect(_editable(tester, 'new', 'name').focusNode.hasFocus, isTrue);
      expect(
        _editable(tester, 'new', 'name').controller.text,
        'User chose this input',
      );

      scene.update(() {
        scene.value = scene.value.copyWith(
          manualModels: scene.value.manualModels
              .where((row) => row.editorKey != 'new')
              .toList(),
        );
      });
      await tester.pumpAndSettle();
      final first = _input('first', 'name');
      await tester.ensureVisible(first);
      await tester.enterText(first, 'Retained row');
      await tester.pumpAndSettle();
      expect(_editable(tester, 'first', 'name').focusNode.hasFocus, isTrue);
      expect(_input('new', 'id'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a replacement editor gets new local fields for reused model keys',
    (tester) async {
      final scene = _EditorScene()..target = 'last';
      await scene.mount(tester);
      _expectFocusedAndVisible(tester, 'last', 'name');
      final previous = _editable(tester, 'last', 'name').controller;
      scene.update(() {
        scene.value = scene.value.copyWith(
          editorId: 'replacement-editor',
          manualModels: [
            _model(
              'last',
            ).copyWith(name: const AccountTextPresentation(raw: 'Replacement')),
          ],
        );
        scene.focusId = true;
      });
      await tester.pumpAndSettle();
      _expectFocusedAndVisible(tester, 'last', 'id');
      expect(
        _editable(tester, 'last', 'name').controller,
        isNot(same(previous)),
      );
      expect(_editable(tester, 'last', 'name').controller.text, 'Replacement');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _input(String row, String field) => find.descendant(
  of: find.byKey(ValueKey(AccountViewKeyValues.manualField(row, field))),
  matching: find.byType(EditableText),
);

EditableText _editable(WidgetTester tester, String row, String field) =>
    tester.widget<EditableText>(_input(row, field));

void _expectFocusedAndVisible(WidgetTester tester, String row, String field) {
  final input = _input(row, field);
  expect(_editable(tester, row, field).focusNode.hasFocus, isTrue);
  final viewport = find
      .ancestor(of: input, matching: find.byType(SingleChildScrollView))
      .last;
  expect(tester.getRect(viewport).contains(tester.getCenter(input)), isTrue);
}

ManualAccountModelPresentation _model(String key) =>
    AccountPreviewFixtures.editor.manualModels.first.copyWith(
      editorKey: key,
      id: AccountTextPresentation(raw: key),
      name: AccountTextPresentation(raw: '$key model'),
    );

class _EditorScene {
  NativeAccountEditorPresentation value = AccountPreviewFixtures.editor
      .copyWith(
        manualModels: [_model('first'), _model('middle'), _model('last')],
      );
  String? target;
  bool focusId = false;
  late StateSetter _setState;

  void update(VoidCallback change) => _setState(change);

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              _setState = setState;
              return NativeAccountEditorView(
                value: value,
                templateSelector: const SizedBox.shrink(),
                focusManualModelEditorKey: target,
                focusManualModelId: focusId,
                onFieldChanged: (_, _) {},
                onTemplateChanged: (_) {},
                onBillingChanged: (_) {},
                onResetBilling: () {},
                onAddModel: () {},
                onManualModelFieldChanged: (key, field, raw) => update(() {
                  value = value.copyWith(
                    manualModels: [
                      for (final row in value.manualModels)
                        if (row.editorKey != key)
                          row
                        else
                          switch (field) {
                            ManualModelField.id => row.copyWith(
                              id: AccountTextPresentation(raw: raw),
                            ),
                            ManualModelField.name => row.copyWith(
                              name: AccountTextPresentation(raw: raw),
                            ),
                            ManualModelField.contextWindow => row.copyWith(
                              contextWindow: AccountTextPresentation(raw: raw),
                            ),
                            ManualModelField.maxOutputTokens => row.copyWith(
                              maxOutputTokens: AccountTextPresentation(
                                raw: raw,
                              ),
                            ),
                          },
                    ],
                  );
                }),
                onManualModelConnectionChanged: (_, _) {},
                onManualModelWireApiChanged: (_, _) {},
                onRemoveManualModel: (_) {},
                modelActions: AccountModelActions(
                  onEnabledChanged: (_, _) {},
                  onConnectionChanged: (_, _) {},
                  onCompactChanged: (_, _) {},
                  onCompactPreset: (_, _) {},
                  onAction: (_, _) {},
                ),
                onSave: () {},
                onCancel: () {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
