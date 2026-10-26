import 'dart:ui' show PointerDeviceKind;

import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/ui/selectors/mode_selector.dart';
import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/selector_values.dart';

void main() {
  for (final backwards in [false, true]) {
    testWidgets(
      'mouse-open mode menu handles Escape then ${backwards ? 'Shift+Tab' : 'Tab'}',
      (tester) async {
        final inputFocus = FocusNode(debugLabel: 'composer-input');
        final afterFocus = FocusNode(debugLabel: 'after-selector');
        final text = TextEditingController(text: 'Keep this draft');
        addTearDown(inputFocus.dispose);
        addTearDown(afterFocus.dispose);
        addTearDown(text.dispose);
        final selected = <ThreadModeId>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.linux),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  TextField(
                    key: StudioDriverKeys.composerInput,
                    controller: text,
                    focusNode: inputFocus,
                  ),
                  ModeSelector(
                    modes: selectorModes,
                    selected: ThreadModeId.simple,
                    onSelected: selected.add,
                  ),
                  TextButton(
                    focusNode: afterFocus,
                    onPressed: () {},
                    child: const Text('After selector'),
                  ),
                ],
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(
          location: tester.getCenter(
            find.byKey(StudioDriverKeys.composerInput),
          ),
        );
        await mouse.down(
          tester.getCenter(find.byKey(StudioDriverKeys.composerInput)),
        );
        await mouse.up();
        await tester.pump();
        expect(inputFocus.hasFocus, isTrue);

        final triggerFinder = find.descendant(
          of: find.byKey(StudioDriverKeys.sessionMode),
          matching: find.byType(TextButton),
        );
        final trigger = tester.widget<TextButton>(triggerFinder);
        await mouse.moveTo(tester.getCenter(triggerFinder));
        await mouse.down(tester.getCenter(triggerFinder));
        await mouse.up();
        await tester.pumpAndSettle();
        final anchor = tester.widget<MenuAnchor>(
          find.descendant(
            of: find.byKey(StudioDriverKeys.sessionMode),
            matching: find.byType(MenuAnchor),
          ),
        );
        expect(anchor.controller!.isOpen, isTrue);
        expect(
          find.byKey(StudioDriverKeys.sessionModeOption(ThreadModeId.task.id)),
          findsOneWidget,
        );
        expect(
          inputFocus.hasFocus,
          isFalse,
          reason: 'pointer-open must leave the unrelated composer focus chain',
        );
        expect(anchor.childFocusNode, same(trigger.focusNode));

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(anchor.controller!.isOpen, isFalse);
        expect(find.byType(MenuItemButton), findsNothing);
        expect(trigger.focusNode!.hasFocus, isTrue);

        if (backwards) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        if (backwards) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pump();
        expect(backwards ? inputFocus.hasFocus : afterFocus.hasFocus, isTrue);
        expect(trigger.focusNode!.hasFocus, isFalse);
        expect(selected, isEmpty);
        expect(text.text, 'Keep this draft');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
