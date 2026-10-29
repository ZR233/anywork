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
      expect((await read('readText'))['texts'], ['Output']);
      final before = await read('readSelectableText');
      expect(before['texts'], [first]);
      expect(before['visibleHeight'], greaterThan(0));

      await render(grown);
      final after = await read('readSelectableText');
      expect(after['texts'], [grown]);
      expect(after['visibleHeight'], greaterThan(0));
      expect((await read('readText'))['texts'], ['Output']);
    },
  );
}
