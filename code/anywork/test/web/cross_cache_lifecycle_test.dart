@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:cross_cache/src/cache/html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unused cache can be disposed without an unowned open failure',
    () async {
      for (var i = 0; i < 20; i++) {
        Cache().dispose();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test('disposal during open rejects every waiter and never reopens', () async {
    final cache = Cache();
    final first = expectLater(cache.contains('pending-a'), throwsStateError);
    final second = expectLater(cache.contains('pending-b'), throwsStateError);
    cache.dispose();
    await Future.wait([first, second]);
    await expectLater(cache.contains('after-dispose'), throwsStateError);
    cache.dispose();
  });

  test(
    'real IndexedDB operations share opening and preserve stored bytes',
    () async {
      final cache = Cache();
      addTearDown(cache.dispose);
      final key = 'lifecycle-${DateTime.now().microsecondsSinceEpoch}';
      final renamed = '$key-renamed';
      expect(
        await Future.wait([cache.contains(key), cache.contains(renamed)]),
        [false, false],
      );
      final bytes = Uint8List.fromList([1, 23, 255]);
      await cache.set(key, bytes);
      expect(await cache.get(key), bytes);
      await cache.updateKey(key, renamed);
      expect(await cache.contains(key), isFalse);
      expect(await cache.get(renamed), bytes);
      await cache.delete(renamed);
      expect(await cache.contains(renamed), isFalse);
      await expectLater(cache.get(renamed), throwsException);
      cache.dispose();
      await expectLater(cache.set(key, bytes), throwsStateError);
    },
  );
}
