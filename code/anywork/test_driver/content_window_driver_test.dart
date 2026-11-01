import 'dart:convert';

import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart' hide find;

import 'content_window_driver.dart';
import 'driver_read_commands.dart';

void main() {
  test(
    'range traversal explicitly advances and copies each displayed window',
    () async {
      final surface = _RangeSurface();
      final evidence = await surface.driver.readAllExplicitly(
        'tool-item',
        'tool.result',
        expectedBytes: 6,
        expectedText: 'abcdef',
      );
      expect(surface.actions, surface.expectedActions);
      expect(evidence['explicitNextActions'], 1);
      expect(evidence['wholeBodyCopy'], 'notApplicable');
      expect(evidence['loadedBytes'], 6);
      expect(evidence['viewerClosed'], isTrue);
      expect(
        (evidence['windows'] as List).map((span) => (span as Map)['offset']),
        [0, 3],
      );
    },
  );

  test(
    'range traversal rejects a new Children generation between windows',
    () async {
      final surface = _RangeSurface(second: {'scopeGeneration': 15});
      await expectLater(
        surface.driver.readAllExplicitly(
          'tool-item',
          'tool.result',
          expectedBytes: 6,
        ),
        throwsStateError,
      );
      expect(surface.actions.length, 3);
    },
  );

  test('copy must equal the actual displayed window', () async {
    final surface = _RangeSurface(clipboardText: 'different');
    await expectLater(
      surface.driver.readAllExplicitly(
        'tool-item',
        'tool.result',
        expectedBytes: 6,
      ),
      throwsStateError,
    );
    expect(surface.actions.length, 2);
  });

  test(
    'window responses reject missing qualification and oversized ranges',
    () async {
      for (final response in [
        _window()..remove('scopeGeneration'),
        {..._window(), 'end': 65537, 'availableThrough': 65537},
        {..._window(), 'itemId': 'another-item'},
        {..._window(), 'parentId': null, 'scopeGeneration': 15},
      ]) {
        await expectLater(
          ContentWindowRead.read(
            (_, {timeout}) async => jsonEncode(response),
            itemId: 'tool-item',
            field: 'tool.result',
          ),
          throwsStateError,
        );
      }
    },
  );
}

Map<String, Object?> _window() => {
  'ok': true,
  'open': true,
  'threadId': 'thread',
  'generation': 7,
  'scopeGeneration': 14,
  'parentId': 'turn-parent',
  'itemId': 'tool-item',
  'field': 'tool.result',
  'offset': 0,
  'end': 3,
  'availableThrough': 6,
  'text': 'abc',
  'characters': 3,
  'hash': 'first-window-hash',
};

/// Scripted Driver responses are the environment boundary. Assertions below
/// check the consumer's actions; this fixture does not implement range loading.
class _RangeSurface {
  _RangeSurface({this.second = const {}, this.clipboardText});
  final Map<String, Object?> second;
  final String? clipboardText;
  final actions = <Map<String, String>>[];

  List<Map<String, String>> get expectedActions => [
    find
        .byValueKey(
          StudioDriverKeyValues.timelineContentOpen('tool-item', 'tool.result'),
        )
        .serialize(),
    find
        .byValueKey(
          StudioDriverKeyValues.timelineContentCopyWindow(
            'tool-item',
            'tool.result',
          ),
        )
        .serialize(),
    find
        .byValueKey(
          StudioDriverKeyValues.timelineContentNextWindow(
            'tool-item',
            'tool.result',
          ),
        )
        .serialize(),
    find
        .byValueKey(
          StudioDriverKeyValues.timelineContentCopyWindow(
            'tool-item',
            'tool.result',
          ),
        )
        .serialize(),
    find
        .byValueKey(
          StudioDriverKeyValues.timelineContentOpen('tool-item', 'tool.result'),
        )
        .serialize(),
  ];

  ContentWindowDriver get driver => ContentWindowDriver(
    reveal: (_) async {},
    tap: (finder) async {
      expect(finder.serialize(), expectedActions[actions.length]);
      actions.add(finder.serialize());
    },
    request: (message, {timeout}) async {
      final command = jsonDecode(message) as Map;
      final later = actions.length >= 3;
      final response = {
        ..._window(),
        if (later) ...{
          'offset': 3,
          'end': 6,
          'text': 'def',
          'hash': 'second-window-hash',
          ...second,
        },
        if (actions.length == 5) 'open': false,
      };
      if (command['cmd'] == 'clipboard-text') {
        return jsonEncode({
          'ok': true,
          'text': clipboardText ?? response['text'],
          'characters': (clipboardText ?? response['text'] as String).length,
          'hash': response['hash'],
        });
      }
      expect(command, {
        'cmd': 'timeline-content-window',
        'itemId': 'tool-item',
        'field': 'tool.result',
      });
      return jsonEncode(response);
    },
  );
}
