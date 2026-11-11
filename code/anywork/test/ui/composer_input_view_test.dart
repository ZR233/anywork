import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_input_state.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_actions.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/dropped_file.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final width in [320.0, 800.0]) {
    testWidgets('宽度 $width 的输入区仅整体外框反馈焦点', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(GlobalKey<_EditorHostState>()));
      final input = find.byKey(StudioDriverKeys.composerInput);
      final decorators = find.descendant(
        of: find.byType(PromptComposerView),
        matching: find.byType(InputDecorator),
      );
      final frame = decorators.evaluate().singleWhere(
        (element) =>
            (element.widget as InputDecorator).decoration.border
                is OutlineInputBorder,
      );
      final frameFinder = find.byElementPredicate(
        (element) => identical(element, frame),
      );
      final inner = find.descendant(
        of: input,
        matching: find.byType(InputDecorator),
      );
      void expectSingleFrame({required bool focused}) {
        expect(
          tester
              .widgetList<InputDecorator>(decorators)
              .where((view) => view.decoration.border is OutlineInputBorder),
          hasLength(1),
        );
        expect(tester.widget<InputDecorator>(frameFinder).isFocused, focused);
        final decoration = tester.widget<InputDecorator>(inner).decoration;
        expect(decoration.isCollapsed, isTrue);
        expect(decoration.enabledBorder, InputBorder.none);
        expect(decoration.focusedBorder, InputBorder.none);
        expect(decoration.disabledBorder, InputBorder.none);
        expect(
          tester.getRect(frameFinder).contains(tester.getCenter(input)),
          isTrue,
        );
        expect(
          find.descendant(
            of: frameFinder,
            matching: find.byKey(const ValueKey('composer-submit-disabled')),
          ),
          findsOneWidget,
          reason: '唯一外框同时包住编辑区与底部操作栏',
        );
        expect(tester.takeException(), isNull);
      }

      expectSingleFrame(focused: false);
      await tester.showKeyboard(input);
      await tester.pumpAndSettle();
      expectSingleFrame(focused: true);
      tester.widget<TextField>(input).focusNode!.unfocus();
      await tester.pumpAndSettle();
      expectSingleFrame(focused: false);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Shift Enter 由官方编辑动作替换选区、通知变更并可撤销', (tester) async {
    final key = GlobalKey<_EditorHostState>();
    await tester.pumpWidget(_host(key));
    final input = find.byKey(StudioDriverKeys.composerInput);
    await tester.enterText(input, 'abcd');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 600));
    final controller = tester.widget<TextField>(input).controller!;
    expect(controller.text, 'a\nd');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(key.currentState!.changes.last, 'a\nd');
    expect(key.currentState!.submits, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, 'abcd', reason: '换行进入 EditableText 原生 undo 历史');
    expect(key.currentState!.changes.last, 'abcd');
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('异步图片探测后默认文本粘贴仍走官方选区替换并保留焦点', (tester) async {
    final key = GlobalKey<_EditorHostState>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': 'pasted'},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_host(key));
    final input = find.byKey(StudioDriverKeys.composerInput);
    await tester.enterText(input, 'abcd');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      ),
    );
    await tester.pump();
    // The focus context is below EditableText's overridable Actions. Invoking
    // from its widget element instead would bypass the default paste delegate.
    Actions.invoke(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    final controller = tester.widget<TextField>(input).controller!;
    expect(controller.text, 'apastedd');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
    expect(key.currentState!.changes.last, 'apastedd');
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _host(GlobalKey<_EditorHostState> key) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('en'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: _EditorHost(key: key)),
  ),
);

class _EditorHost extends StatefulWidget {
  const _EditorHost({super.key});
  @override
  State<_EditorHost> createState() => _EditorHostState();
}

/// No Client substitute: this fixture only acknowledges View editing intents.
class _EditorHostState extends State<_EditorHost> implements ComposerActions {
  String text = '';
  final changes = <String>[];
  int submits = 0;
  @override
  Widget build(BuildContext context) => PromptComposerView(
    targetKey: 'editor-test',
    actions: this,
    state: ComposerInputState(
      composer: ComposerThreadState.idle(draft: text),
      enabled: true,
      nowMs: 0,
    ),
  );
  @override
  void updateText(String value) => setState(() {
    text = value;
    changes.add(value);
  });
  @override
  void submit() => submits++;
  @override
  void stop(String expectedExecutionId) {}
  @override
  void continueConversation() {}
  @override
  void addUrl(String url) {}
  @override
  void removeAttachment(String draftId) {}
  @override
  void pickAttachments(
    List<ModelInputCapabilityView> capabilities,
    bool Function() isCurrent,
  ) {}
  @override
  Future<void> dropAttachments(
    List<DroppedFileTransfer> files,
    bool Function() isCurrent,
  ) async {}
  @override
  void paste(ComposerTextPaste textPaste) => unawaited(_paste(textPaste));
  Future<void> _paste(ComposerTextPaste textPaste) async {
    await Future<void>.value();
    if (textPaste.isCurrent()) await textPaste.invoke();
  }
}
