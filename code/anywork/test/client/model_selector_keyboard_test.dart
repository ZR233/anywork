import 'dart:ui' show PointerDeviceKind;

import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/model_route_selector.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final backwards in [false, true]) {
    testWidgets(
      'pointer model menu Escape and ${backwards ? 'Shift Tab' : 'Tab'}',
      (tester) async {
        final input = FocusNode();
        final after = FocusNode();
        addTearDown(input.dispose);
        addTearDown(after.dispose);
        final selected = <ModelSelectionOption>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.linux),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: input, autofocus: true),
                  ModelRouteSelector(
                    options: const [
                      ModelSelectionOption(
                        providerId: 'provider',
                        providerName: 'Provider',
                        descriptor: ProviderModelView(
                          modelId: 'model',
                          displayName: 'Model',
                          reasoningEfforts: [],
                        ),
                      ),
                    ],
                    providerId: 'provider',
                    model: 'model',
                    onSelected: selected.add,
                    fieldLabel: 'Route',
                    selectorKey: const ValueKey('route'),
                  ),
                  TextButton(
                    focusNode: after,
                    onPressed: () {},
                    child: const Text('After'),
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
        final triggerFinder = find.descendant(
          of: find.byKey(const ValueKey('route')),
          matching: find.byType(TextButton),
        );
        await mouse.addPointer(location: const Offset(700, 500));
        await mouse.moveTo(tester.getCenter(triggerFinder));
        await mouse.down(tester.getCenter(triggerFinder));
        await mouse.up();
        await tester.pumpAndSettle();
        final anchor = tester.widget<MenuAnchor>(
          find.byKey(const ValueKey('route')),
        );
        expect(anchor.controller!.isOpen, isTrue);
        expect(input.hasFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(anchor.controller!.isOpen, isFalse);
        final trigger = tester.widget<TextButton>(triggerFinder);
        expect(trigger.focusNode!.hasFocus, isTrue);
        if (backwards) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        if (backwards) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pump();
        expect(backwards ? input.hasFocus : after.hasFocus, isTrue);
        expect(selected, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
