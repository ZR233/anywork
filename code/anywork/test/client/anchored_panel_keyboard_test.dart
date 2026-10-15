import 'dart:ui' show PointerDeviceKind;

import 'package:anywork/src/shared/studio_anchored_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hover details preserves the active editor and IME composing', (
    tester,
  ) async {
    final input = FocusNode();
    final text = TextEditingController(text: 'draft');
    addTearDown(input.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: input, controller: text, autofocus: true),
              StudioAnchoredPanel(
                panelBuilder: (_) => const Text('Usage detail'),
                child: const Text('Usage'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(input.hasFocus, isTrue);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(find.text('Usage')));
    await tester.pumpAndSettle();
    expect(find.text('Usage detail'), findsOneWidget);
    expect(input.hasFocus, isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'draft ni',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 6, end: 8),
      ),
    );
    await tester.pump();
    expect(text.text, 'draft ni');
    expect(text.value.composing, const TextRange(start: 6, end: 8));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'details panel supports Tab, Enter and Escape focus restoration',
    (tester) async {
      final before = FocusNode(debugLabel: 'before-details');
      addTearDown(before.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  focusNode: before,
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('Before'),
                ),
                StudioAnchoredPanel(
                  panelBuilder: (_) => MenuItemButton(
                    onPressed: () {},
                    child: const Text('Panel action'),
                  ),
                  child: const Text('Details'),
                ),
                TextButton(onPressed: () {}, child: const Text('After')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(before.hasFocus, isTrue);
      expect(find.text('Panel action'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final trigger = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Details'),
      );
      expect(trigger.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Panel action'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Panel action'), findsNothing);
      expect(trigger.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(trigger.focusNode!.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
