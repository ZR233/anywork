import 'dart:async';

import 'package:anywork/src/shared/composer_action_button.dart';
import 'package:anywork/src/shared/composer_input_frame.dart';
import 'package:anywork/src/shared/conversation_composer.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('同身份且文本未变时保留选区与IME组词', (tester) async {
    var identity = 'first';
    late StateSetter rebuild;
    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _composer(identity: identity, text: '草稿');
          },
        ),
      ),
    );

    final initialController = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    initialController.value = const TextEditingValue(
      text: '草稿',
      selection: TextSelection(baseOffset: 0, extentOffset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    rebuild(() => identity = 'first');
    await tester.pump();

    expect(
      initialController.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    expect(
      initialController.value.composing,
      const TextRange(start: 0, end: 2),
    );
  });

  testWidgets('身份切换而文本相同时清理组词、重置选区并撤销旧粘贴资格', (tester) async {
    var identity = 'first';
    late StateSetter rebuild;
    late bool Function() oldEligibility;
    late Future<void> Function() delayedPaste;
    var pasteCalls = 0;
    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _composer(
              identity: identity,
              text: '相同草稿',
              onPaste: (paste, isCurrent) {
                oldEligibility = isCurrent;
                delayedPaste = () async {
                  if (!isCurrent()) return;
                  pasteCalls++;
                  await paste();
                };
              },
            );
          },
        ),
      ),
    );

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    controller.value = const TextEditingValue(
      text: '相同草稿',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 2),
    );
    Actions.invoke(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    rebuild(() => identity = 'second');
    await tester.pump();

    final currentController = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(currentController.text, '相同草稿');
    expect(
      currentController.selection,
      const TextSelection.collapsed(offset: 4),
    );
    expect(currentController.value.composing, TextRange.empty);
    expect(oldEligibility(), isFalse);
    await delayedPaste();
    expect(pasteCalls, 0);
    expect(currentController.text, '相同草稿');
  });

  testWidgets('卸载后捕获的粘贴资格失效', (tester) async {
    late bool Function() isCurrent;
    await tester.pumpWidget(
      _testApp(
        _composer(
          identity: 'first',
          text: '草稿',
          onPaste: (_, eligibility) => isCurrent = eligibility,
        ),
      ),
    );
    Actions.invoke(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    expect(isCurrent(), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(isCurrent(), isFalse);
  });

  testWidgets('已启动的官方异步粘贴在身份切换后不能写入新目标', (tester) async {
    final clipboardReadStarted = Completer<void>();
    final clipboardResult = Completer<Map<String, Object?>>();
    var identity = 'first';
    var text = '旧目标草稿';
    late StateSetter rebuild;
    final textChanges = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          if (!clipboardReadStarted.isCompleted) {
            clipboardReadStarted.complete();
          }
          return clipboardResult.future;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _composer(
              identity: identity,
              text: text,
              onTextChanged: textChanges.add,
            );
          },
        ),
      ),
    );
    final initialField = tester.widget<TextField>(find.byType(TextField));
    initialField.controller!.selection = const TextSelection.collapsed(
      offset: 3,
    );
    final oldEditable = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    final pendingPaste = oldEditable.pasteText(SelectionChangedCause.keyboard);
    await clipboardReadStarted.future;

    rebuild(() {
      identity = 'second';
      text = '新目标草稿';
    });
    await tester.pump();
    expect(oldEditable.mounted, isFalse);
    final currentField = tester.widget<TextField>(find.byType(TextField));
    final currentController = currentField.controller!;
    final selectionBeforeLatePaste = currentController.selection;
    final changesBeforeLatePaste = List<String>.of(textChanges);

    clipboardResult.complete({'text': '旧剪贴板内容'});
    await pendingPaste;
    await tester.pump();

    final updatedField = tester.widget<TextField>(find.byType(TextField));
    expect(updatedField.controller!.text, '新目标草稿');
    expect(updatedField.controller!.selection, selectionBeforeLatePaste);
    expect(textChanges, changesBeforeLatePaste);
  });

  testWidgets('IME组词期间Enter与发送主操作均不提交，结束组词后可正常提交', (tester) async {
    var submissions = 0;
    var primaryActions = 0;
    await tester.pumpWidget(
      _testApp(
        _composer(
          identity: 'first',
          text: '输入内容',
          onSubmit: () => submissions++,
          primaryAction: () => primaryActions++,
        ),
      ),
    );
    final input = find.byType(TextField);
    await tester.showKeyboard(input);
    final controller = tester.widget<TextField>(input).controller!;
    controller.value = const TextEditingValue(
      text: '输入内容',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('primary')));
    expect(submissions, 0);
    expect(primaryActions, 0);

    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.showKeyboard(input);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(submissions, 1);
    await tester.tap(find.byKey(const ValueKey('primary')));
    expect(primaryActions, 1);
  });

  testWidgets('Enter只提交发送状态，禁用编辑器时点击发送不派发', (tester) async {
    var state = ComposerActionButtonState.send;
    var enabled = true;
    var submissions = 0;
    var primaryActions = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _composer(
              identity: 'first',
              text: '可发送草稿',
              enabled: enabled,
              actionState: state,
              onSubmit: () => submissions++,
              primaryAction: () => primaryActions++,
            );
          },
        ),
      ),
    );
    final input = find.byType(TextField);
    await tester.showKeyboard(input);
    for (final actionState in ComposerActionButtonState.values) {
      rebuild(() => state = actionState);
      await tester.pump();
      final previousSubmissions = submissions;
      await tester.showKeyboard(input);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(
        submissions,
        previousSubmissions +
            (actionState == ComposerActionButtonState.send ||
                    actionState == ComposerActionButtonState.sendAndContinue
                ? 1
                : 0),
        reason: 'Enter提交资格应由当前主操作状态决定：$actionState',
      );
    }

    rebuild(() {
      state = ComposerActionButtonState.send;
      enabled = false;
    });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('primary')));
    expect(primaryActions, 0);
    expect(submissions, 2);
  });

  testWidgets('共享输入框使用统一装饰且只有一个编辑器和稳定主按钮', (tester) async {
    await tester.pumpWidget(_testApp(_composer(identity: 'first', text: '')));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ComposerInputFrame), findsOneWidget);
    expect(find.byKey(const ValueKey('input')), findsOneWidget);
    expect(find.byKey(const ValueKey('primary')), findsOneWidget);
    final decoration = tester
        .widget<TextField>(find.byKey(const ValueKey('input')))
        .decoration!;
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
    expect(decoration.disabledBorder, InputBorder.none);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('primary')))
          .onPressed,
      isNull,
    );
  });
}

Widget _composer({
  required Object identity,
  required String text,
  bool enabled = true,
  ComposerActionButtonState actionState = ComposerActionButtonState.send,
  ValueChanged<String>? onTextChanged,
  VoidCallback? onSubmit,
  VoidCallback? primaryAction,
  void Function(Future<void> Function(), bool Function())? onPaste,
}) {
  return ConversationComposer(
    identity: identity,
    text: text,
    inputKey: const ValueKey('input'),
    onTextChanged: onTextChanged ?? (_) {},
    enabled: enabled,
    onSubmit: onSubmit,
    onPaste: onPaste,
    primaryAction: ComposerActionPresentation(
      state: actionState,
      tooltip: '发送',
      buttonKey: const ValueKey('primary'),
      onPressed: primaryAction,
    ),
  );
}

Widget _testApp(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
