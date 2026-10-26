import 'package:anywork/src/features/conversation/widgets/raw_text_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Shift+Enter delegates newline editing to the multiline platform client',
    (tester) async {
      final host = await _mountInput(tester, raw: '第一行');
      final controller = _input(tester).controller!;
      expect(_input(tester).maxLines, greaterThan(1));
      expect(
        tester.testTextInput.setClientArgs!['inputType'],
        TextInputType.multiline.toJson(),
      );
      expect(
        tester.testTextInput.setClientArgs!['inputAction'],
        TextInputAction.newline.toString(),
      );

      expect(await _shiftEnter(tester), isFalse);
      expect(host.submitted, isEmpty);
      // sendKeyEvent reaches the framework only. Native newline editing arrives
      // separately through TextInputClient.updateEditingState, not a key action.
      const nativeEdit = TextEditingValue(
        text: '第一行\n',
        selection: TextSelection.collapsed(offset: 4),
      );
      tester.testTextInput.updateEditingValue(nativeEdit);
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();

      expect(controller.value, nativeEdit);
      expect(host.raw, '第一行\n');
      expect(host.changed, ['第一行\n']);
      expect(host.submitted, isEmpty);
      expect(_input(tester).controller, same(controller));
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'Shift+Enter accepts native selection replacement without submitting',
    (tester) async {
      final host = await _mountInput(tester);
      final controller = _input(tester).controller!;
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'first',
          selection: TextSelection(baseOffset: 3, extentOffset: 0),
        ),
      );
      await tester.pump();

      expect(await _shiftEnter(tester), isFalse);
      const nativeEdit = TextEditingValue(
        text: '\nst',
        selection: TextSelection.collapsed(offset: 1),
      );
      tester.testTextInput.updateEditingValue(nativeEdit);
      await tester.pump();

      expect(controller.value, nativeEdit);
      expect(host.raw, '\nst');
      expect(host.changed, ['\nst']);
      expect(host.submitted, isEmpty);
      expect(_input(tester).controller, same(controller));
    },
  );

  testWidgets(
    'send and done actions reuse Enter submission without clearing or unfocusing',
    (tester) async {
      final host = await _mountInput(tester);
      final controller = _input(tester).controller!;

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(host.submitted, ['first']);
      expect(controller.text, 'first');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      expect(host.submitted, ['first', 'first', 'first', 'first']);
    },
  );

  testWidgets('IME composition blocks Enter and native submission actions', (
    tester,
  ) async {
    final host = await _mountInput(tester);
    const composing = TextEditingValue(
      text: 'pinyin',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(host.submitted, isEmpty);
    expect(_input(tester).controller!.value, composing);

    tester.testTextInput.updateEditingValue(
      composing.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(host.submitted, ['pinyin']);
  });

  testWidgets('disabled input ignores editing and submission events', (
    tester,
  ) async {
    final host = await _mountInput(tester);
    final controller = _input(tester).controller!;
    host.update(enabled: false);
    await tester.pump();
    final before = controller.value;

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await _shiftEnter(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'first\n',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(controller.value, before);
    expect(host.raw, 'first');
    expect(host.changed, isEmpty);
    expect(host.submitted, isEmpty);
  });

  testWidgets('canSubmit gates Enter and send without disabling text editing', (
    tester,
  ) async {
    final host = await _mountInput(tester);
    host.update(canSubmit: false);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(host.submitted, isEmpty);
    await tester.enterText(find.byType(TextField), 'still editable');
    await tester.pump();
    expect(host.raw, 'still editable');

    host.update(canSubmit: true);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(host.submitted, ['still editable']);
  });
}

TextField _input(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

Future<bool> _shiftEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  return handled;
}

Future<_InputHostState> _mountInput(
  WidgetTester tester, {
  String raw = 'first',
}) async {
  final key = GlobalKey<_InputHostState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux),
      home: Scaffold(
        body: _InputHost(key: key, raw: raw),
      ),
    ),
  );
  await tester.showKeyboard(find.byType(TextField));
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

class _InputHost extends StatefulWidget {
  const _InputHost({required this.raw, required super.key});

  final String raw;

  @override
  State<_InputHost> createState() => _InputHostState();
}

class _InputHostState extends State<_InputHost> {
  late String raw = widget.raw;
  bool enabled = true;
  bool canSubmit = true;
  final changed = <String>[];
  final submitted = <String>[];

  void update({bool? enabled, bool? canSubmit}) => setState(() {
    this.enabled = enabled ?? this.enabled;
    this.canSubmit = canSubmit ?? this.canSubmit;
  });

  @override
  Widget build(BuildContext context) => RawTextInput(
    raw: raw,
    enabled: enabled,
    canSubmit: canSubmit,
    onChanged: (value) => setState(() {
      raw = value;
      changed.add(value);
    }),
    onSubmit: () => submitted.add(raw),
  );
}
