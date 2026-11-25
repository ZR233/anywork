import 'package:anywork/src/shared/widgets/studio_menu_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final icon in [false, true]) {
    testWidgets('${icon ? 'icon' : 'text'} menu keeps keyboard ownership', (
      tester,
    ) async {
      const triggerKey = ValueKey('menu-trigger');
      var selected = false;
      final rows = [
        MenuItemButton(
          onPressed: () => selected = true,
          child: const Text('Choose model'),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const TextField(),
                if (icon)
                  StudioMenuButton.icon(
                    tooltip: 'Configuration',
                    buttonKey: triggerKey,
                    menuChildren: rows,
                    icon: const Icon(Icons.more_horiz),
                  )
                else
                  StudioMenuButton(
                    tooltip: 'Configuration',
                    buttonKey: triggerKey,
                    menuChildren: rows,
                    child: const Text('Models'),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      await tester.tap(find.byKey(triggerKey));
      await tester.pumpAndSettle();
      expect(find.text('Choose model'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Choose model'), findsNothing);
      expect(selected, isFalse);

      // Escape returns keyboard control to the trigger, rather than leaving
      // it on the input that was focused before the pointer opened the menu.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Choose model'), findsOneWidget);
      await tester.tap(find.text('Choose model'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(find.text('Choose model'), findsNothing);
      expect(find.text('Keep my draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('open contents refresh and locked triggers only explain', (
    tester,
  ) async {
    const triggerKey = ValueKey('menu-trigger');
    var label = 'First model';
    var enabled = true;
    var explanations = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return StudioMenuButton(
                tooltip: 'Models',
                buttonKey: triggerKey,
                enabled: enabled,
                onBlockedTap: () => explanations++,
                menuChildren: [
                  MenuItemButton(onPressed: () {}, child: Text(label)),
                ],
                child: const Text('Select'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(triggerKey));
    await tester.pumpAndSettle();
    expect(find.text('First model'), findsOneWidget);
    rebuild(() => label = 'Updated model');
    await tester.pumpAndSettle();
    expect(find.text('First model'), findsNothing);
    expect(find.text('Updated model'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    rebuild(() => enabled = false);
    await tester.pump();
    await tester.tap(find.byKey(triggerKey));
    await tester.pumpAndSettle();
    expect(explanations, 1);
    expect(find.text('Updated model'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
