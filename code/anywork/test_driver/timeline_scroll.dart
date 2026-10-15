// Manual companion to the native stress-body-large journey. Attach before the
// stream starts: cargo dart run test_driver/timeline_scroll.dart <vm-url> <dir>.
// It drives actual drag/wheel events; snapshots only observe product state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'pointer_scroll.dart';
import 'pointer_drag.dart';
import 'raw_tap.dart';
import 'scrollbar_drag.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('expected <vm-url> <evidence-directory>');
  }
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final output = Directory(args[1])..createSync(recursive: true);
  final observations = <String, Object?>{};
  final timeline = find.byValueKey('timeline-scrollable');
  await driver.sendCommand(SetFrameSync(false));

  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();

  void record(String phase, Map<String, dynamic> state) {
    observations[phase] = {
      'bodyLength': _bodyLength(state),
      'busy': _busy(state),
      'scroll': _scroll(state),
    };
  }

  Future<Map<String, dynamic>> waitFor(
    String label,
    bool Function(Map<String, dynamic>) condition,
  ) async {
    await File('${output.path}/stage.txt').writeAsString('$label\n');
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      final state = await snapshot();
      last = state;
      if (condition(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (last != null) record('timeoutState', last);
    throw StateError('timed out: $label');
  }

  bool idleGeometry(Map<String, dynamic> state) {
    final scroll = _scroll(state);
    return scroll['isScrolling'] == false &&
        scroll['restorePending'] != true &&
        (scroll['mountedRowCount'] as num? ?? 0) > 0 &&
        scroll['anchor'] != null;
  }

  Future<void> drag(double dy) async {
    final ready = await waitFor('drag start geometry', idleGeometry);
    final before = _scroll(ready)['userDragUpdates'] as int;
    final drags = observations.putIfAbsent('drags', () => <Object?>[]) as List;
    drags.add(await driver.sendCommand(PointerDrag(timeline, dy)));
    // Driver has sent pointer-up, but the last published geometry can still be
    // from the middle of that drag. Compare anchors only after its idle frame.
    await waitFor(
      'drag idle geometry',
      (state) =>
          (_scroll(state)['userDragUpdates'] as int) > before &&
          idleGeometry(state),
    );
  }

  Future<void> checkGrowth(Map<String, dynamic> before, String phase) async {
    final state = await waitFor(
      phase,
      (state) =>
          (!_busy(state) || _bodyLength(state) > _bodyLength(before) + 16000) &&
          idleGeometry(state),
    );
    record(phase, state);
    final grew = _bodyLength(state) > _bodyLength(before) + 16000;
    _require(grew || !_busy(state), '$phase did not settle');
    final a = _scroll(before);
    final b = _scroll(state);
    _require(
      b['followingBottom'] == a['followingBottom'],
      '$phase changed reading intent',
    );
    if (a['followingBottom'] == false) {
      final beforeAnchor = a['anchor'];
      final afterAnchor = b['anchor'];
      if (beforeAnchor is Map && afterAnchor is Map) {
        _require(
          beforeAnchor['itemId'] == afterAnchor['itemId'] &&
              ((beforeAnchor['offset'] as num) - (afterAnchor['offset'] as num))
                      .abs() <
                  2,
          '$phase moved the reading anchor',
        );
      }
    }
  }

  try {
    var state = await waitFor(
      'initial auto-follow',
      (state) =>
          _busy(state) &&
          _bodyLength(state) > 12000 &&
          _scroll(state)['followingBottom'] == true &&
          idleGeometry(state),
    );
    record('autoFollow', state);
    // Less than the near-bottom threshold: new layout must not resume following.
    await drag(40);
    state = await snapshot();
    record('smallUpwardDrag', state);
    _require(_scroll(state)['followingBottom'] == false, 'drag did not detach');
    await checkGrowth(state, 'outputWhileReading');

    // Desktop pointer-wheel events advance in bounded platform-sized steps;
    // issue the same downward step used by the edge journey until the latest
    // position is reached instead of assuming one event spans the whole body.
    for (var step = 0; step < 24; step += 1) {
      await driver.sendCommand(PointerScroll(timeline, 1000000));
      state = await snapshot();
      if (_scroll(state)['followingBottom'] == true) break;
    }
    state = await waitFor(
      'wheel back to latest',
      (state) =>
          _scroll(state)['followingBottom'] == true && idleGeometry(state),
    );
    record('wheelToLatest', state);
    await checkGrowth(state, 'outputAfterReturning');

    await drag(300);
    state = await snapshot();
    record('secondUpwardDrag', state);
    _require(
      _scroll(state)['followingBottom'] == false,
      'output prevented the second drag',
    );
    await checkGrowth(state, 'outputAfterSecondDrag');
    final beforeThumb = _scroll(state)['userDragUpdates'] as int;
    observations['streamingThumbDrag'] = await driver.sendCommand(
      ScrollbarDrag(timeline, -60),
    );
    state = await waitFor(
      'thumb idle geometry',
      (state) =>
          (_scroll(state)['userDragUpdates'] as int) > beforeThumb &&
          idleGeometry(state),
    );
    record('thumbWhileStreaming', state);
    _require(
      _scroll(state)['followingBottom'] == false,
      'thumb drag did not detach',
    );
    await checkGrowth(state, 'outputAfterThumbDrag');
    await driver.sendCommand(RawTap(find.byValueKey('timeline-jump-latest')));
    state = await waitFor(
      'explicit jump to latest',
      (state) =>
          _scroll(state)['followingBottom'] == true && idleGeometry(state),
    );
    record('jumpToLatest', state);
    observations['checksPassed'] = true;
    await File('${output.path}/screen.png')
        .writeAsBytes(await driver.screenshot());
  } catch (error) {
    observations['error'] = error.toString();
    rethrow;
  } finally {
    observations['humanVerdict'] = 'pending';
    await File('${output.path}/timeline-scroll.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
    );
    await driver.close();
  }
}

Map<String, dynamic> _scroll(Map<String, dynamic> state) =>
    (state['timelineScroll'] as Map?)?.cast<String, dynamic>() ?? {};

bool _busy(Map<String, dynamic> state) =>
    (state['workspace'] as Map?)?['isBusy'] == true;

int _bodyLength(Map<String, dynamic> state) {
  final rows =
      (state['workspace'] as Map?)?['timelineProgress']?['rows'] as List? ?? [];
  return rows.fold<int>(
    0,
    (total, row) => total + ((row['text'] as String?)?.length ?? 0),
  );
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
