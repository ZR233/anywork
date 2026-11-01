import 'package:anywork/src/shared/studio_code_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/tool_probe.dart';
import '../../test_driver/tool_probe_extension.dart';

class _UnusedDriverFactory extends Fake
    implements CreateFinderFactory, CommandHandlerFactory {}

void main() {
  testWidgets('title-key probe observes its nearest real ExpansionTile', (
    tester,
  ) async {
    const titleKey = 'conversation-current-collection-tools';
    final probe = ToolProbeExtension(
      owner: () => throw StateError('disclosure reads must not acquire owner'),
    );
    final factory = _UnusedDriverFactory();
    Future<Map> observe(String key) async {
      final pending = probe.call(
        ToolProbe(driver.find.byValueKey(key), 'observe'),
        tester,
        factory,
        factory,
      );
      // observe samples two scheduled frames with a 16ms timer between them.
      // Drive the widget test's fake clock rather than awaiting real time.
      for (var i = 0; i < 3; i++) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
      }
      final result = await pending;
      return (result.toJson()['samples'] as List).last as Map;
    }

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('not a disclosure', key: ValueKey('plain-text')),
              ExpansionTile(
                initiallyExpanded: true,
                title: Text('outer'),
                children: [
                  ExpansionTile(
                    title: Text('tools', key: ValueKey(titleKey)),
                    children: [Text('entry')],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // The outer tile is open; its nested title belongs to the closed inner one.
    expect((await observe(titleKey))['expanded'], false);
    expect((await observe('plain-text')).containsKey('expanded'), false);
    await tester.tap(find.byKey(const ValueKey(titleKey)));
    await tester.pumpAndSettle();
    expect((await observe(titleKey))['expanded'], true);
    await tester.tap(find.byKey(const ValueKey(titleKey)));
    await tester.pumpAndSettle();
    expect((await observe(titleKey))['expanded'], false);
  });

  testWidgets(
    'live output probe reads the mounted selectable payload, not labels',
    (tester) async {
      const outputKey = 'live-tool-output-call-command-output';
      const first = 'realtime-long-output-line-01\n';
      const grown = '${first}realtime-long-output-line-02\n';
      final probe = ToolProbeExtension(
        owner: () =>
            throw StateError('payload reads must not acquire an owner'),
      );
      final factory = _UnusedDriverFactory();

      Future<Map> read(String action) async {
        final result = await probe.call(
          ToolProbe(driver.find.byValueKey(outputKey), action),
          tester,
          factory,
          factory,
        );
        return (result.toJson()['samples'] as List).single as Map;
      }

      Future<void> render(String text) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioCodeBlock(
              key: const ValueKey(outputKey),
              text: text,
              language: 'Output',
              maxHeight: 180,
              horizontalScroll: false,
            ),
          ),
        ),
      );

      await render(first);
      final before = await read('readText');
      expect(before['texts'], [first, 'Output']);
      expect(before['visibleHeight'], greaterThan(0));

      await render(grown);
      final after = await read('readText');
      expect(after['texts'], [grown, 'Output']);
      expect(after['visibleHeight'], greaterThan(0));
    },
  );
}
