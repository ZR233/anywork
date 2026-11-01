import 'dart:convert';

import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:flutter_driver/flutter_driver.dart';

import 'driver_read_commands.dart';
import 'flutter_driver_session.dart';
import 'raw_tap.dart';
import 'timeline_scope_driver.dart';

/// Explicit finite range traversal. Every next request is a real UI action;
/// only the currently displayed window is copied, never an implicit whole body.
final class ContentWindowDriver {
  ContentWindowDriver({
    required this.request,
    required this.tap,
    required this.reveal,
    this.revealItem,
  });
  factory ContentWindowDriver.session(FlutterDriverSession driver) =>
      ContentWindowDriver(
        request: driver.requestData,
        tap: (finder) => driver.rawTap(finder),
        revealItem: TimelineScopeDriver.session(driver).revealItem,
        reveal: (finder) =>
            driver.waitFor(finder, timeout: const Duration(seconds: 20)),
      );
  factory ContentWindowDriver.raw(
    FlutterDriver driver, {
    required Future<void> Function(SerializableFinder) reveal,
  }) => ContentWindowDriver(
    request: driver.requestData,
    tap: (finder) async {
      await driver.sendCommand(RawTap(finder));
    },
    reveal: reveal,
  );
  final DriverReadRequest request;
  final Future<void> Function(SerializableFinder) tap, reveal;
  final Future<void> Function(String)? revealItem;

  Future<Map<String, Object?>> readAllExplicitly(
    String itemId,
    String field, {
    required int expectedBytes,
    String? expectedText,
  }) async {
    if (expectedBytes <= 0) {
      throw ArgumentError.value(
        expectedBytes,
        'expectedBytes',
        'must be positive',
      );
    }
    final open = find.byValueKey(
      StudioDriverKeyValues.timelineContentOpen(itemId, field),
    );
    await revealItem?.call(itemId);
    await reveal(open);
    await tap(open);
    final spans = <Map<String, Object?>>[];
    final text = StringBuffer();
    Object? qualification;
    var offset = 0;
    String? copiedHash;
    var copiedCharacters = 0;
    final budget = Stopwatch()..start();
    while (offset < expectedBytes &&
        budget.elapsed < const Duration(minutes: 3)) {
      ContentWindowRead? current;
      while (budget.elapsed < const Duration(minutes: 3)) {
        final sample = await ContentWindowRead.read(
          request,
          itemId: itemId,
          field: field,
        );
        if (sample.open && sample.offset == offset) {
          current = sample;
          break;
        }
        if (sample.open && sample.offset > offset) {
          throw StateError(
            'window skipped bytes after an explicit next request',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (current == null) {
        throw StateError('content window did not become readable');
      }
      qualification ??= current.qualification;
      if (current.qualification != qualification ||
          current.availableThrough != expectedBytes ||
          current.end <= offset) {
        throw StateError(
          'range identity/manifest changed during explicit reading',
        );
      }
      // These fixtures are text; raw windows may split UTF-8. Never claim exact
      // byte fidelity after replacement decoding. A caller with such a fixture
      // needs a byte-aware API observation rather than hashing a display glyph.
      if (utf8.encode(current.text).length != current.end - current.offset) {
        throw StateError(
          'display window has a split UTF-8 sequence; exact text proof unavailable',
        );
      }
      text.write(current.text);
      await tap(
        find.byValueKey(
          StudioDriverKeyValues.timelineContentCopyWindow(itemId, field),
        ),
      );
      final clipboard = await ClipboardRead.read(request, full: true);
      if (clipboard.text != current.text || clipboard.hash != current.hash) {
        throw StateError(
          'copy-current-window did not copy the actual displayed text',
        );
      }
      copiedHash = clipboard.hash;
      copiedCharacters = clipboard.characters;
      spans.add({
        'offset': offset,
        'end': current.end,
        'characters': current.characters,
        'hash': current.hash,
        'copyMatchesDisplayedWindow': true,
      });
      offset = current.end;
      if (offset < expectedBytes) {
        await tap(
          find.byValueKey(
            StudioDriverKeyValues.timelineContentNextWindow(itemId, field),
          ),
        );
      }
    }
    final body = text.toString();
    if (offset != expectedBytes ||
        (expectedText != null && body != expectedText)) {
      throw StateError(
        'explicit range traversal did not reproduce the canonical fixture body',
      );
    }
    await tap(open);
    final closed = await ContentWindowRead.read(
      request,
      itemId: itemId,
      field: field,
    );
    if (closed.open) {
      throw StateError('collapsed range viewer retained displayed text');
    }
    if (closed.qualification != qualification) {
      throw StateError('content scope changed before viewer closure');
    }
    return {
      'itemId': itemId,
      'field': field,
      'loadedCharacters': body.length,
      'loadedBytes': offset,
      'loadedHash': contentTextHash(body),
      'text': body,
      'windows': spans,
      'explicitNextActions': spans.length - 1,
      'copiedWindowCharacters': copiedCharacters,
      'copiedWindowHash': copiedHash,
      'wholeBodyCopy': 'notApplicable',
      'viewerClosed': true,
      'pass': true,
    };
  }
}

String contentTextHash(String text) {
  var hash = 0xcbf29ce484222325;
  for (final unit in text.codeUnits) {
    hash = (hash ^ unit) * 0x100000001b3;
  }
  return hash.toRadixString(16);
}
