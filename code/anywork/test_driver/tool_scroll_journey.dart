import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_driver/flutter_driver.dart';

import 'raw_tap.dart';
import 'tool_probe.dart';
import 'scrolling_journey.dart';
import 'timeline_fill_journey.dart';
import 'stress_start.dart' as start;

Future<void> main(List<String> args) async {
  String? remoteProject;
  if (args.length >= 3 && args[2] != '--observe-only') {
    final fixtures = Directory('${args[2]}/scroll-fixture');
    await fixtures.create(recursive: true);
    for (var i = 0; i < 240; i++) {
      await File('${fixtures.path}/entry-${i.toString().padLeft(3, '0')}.txt')
          .writeAsString('Tool scrolling fixture\n');
    }
    await File('test_driver/fixtures/tool-image.png')
        .copy('${args[2]}/tool-image.png');
    final git = await Process.run('git', ['init', '-q', args[2]]);
    if (git.exitCode != 0) throw StateError('Fixture project: ${git.stderr}');
    if (args.length == 4) {
      final target = args[3];
      if (!RegExp(r'^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+$').hasMatch(target)) {
        throw ArgumentError('Expected SSH user@host');
      }
      final created = await Process.run('ssh', [
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=10',
        target,
        'mktemp -d /tmp/anywork-image-acceptance-XXXXXXXX',
      ]);
      remoteProject = (created.stdout as String).trim();
      if (created.exitCode != 0 ||
          !RegExp(r'^/tmp/anywork-image-acceptance-[a-zA-Z0-9]+$')
              .hasMatch(remoteProject)) {
        throw StateError('Remote fixture directory: ${created.stderr}');
      }
      final copied = await Process.run('scp', [
        '-q',
        '-r',
        '${args[2]}/scroll-fixture',
        '${args[2]}/tool-image.png',
        '$target:$remoteProject/',
      ]);
      if (copied.exitCode != 0) {
        throw StateError('Remote fixtures: ${copied.stderr}');
      }
      final initialized = await Process.run('ssh', [
        '-o',
        'BatchMode=yes',
        target,
        'git init -q $remoteProject',
      ]);
      if (initialized.exitCode != 0) {
        throw StateError('Remote git: ${initialized.stderr}');
      }
      await File('${args[1]}/remote-project.txt')
          .writeAsString('$target:$remoteProject\n');
    }
    await start.main([
      args[0],
      remoteProject ?? args[2],
      'Tool scroll short',
      '${args[1]}/start-stage',
      '--attach-image',
      if (remoteProject != null) '--ssh-target=${args[3]}',
    ]);
  }
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final output = Directory(args[1]);
  await output.create(recursive: true);
  final evidence = <String, Object?>{};
  final layoutWaits = <Map<String, Object?>>[];
  evidence['layoutWaits'] = layoutWaits;
  final timeline = find.byValueKey('timeline-scrollable');
  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();
  Future<Map<String, dynamic>> waitAnswer(String marker) async {
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(end)) {
      final s = await snapshot();
      final w = s['workspace'] as Map?;
      final rows = w?['timeline'] as List? ?? [];
      final persistence = s['persistence'] as Map?;
      if (w?['isBusy'] == false &&
          persistence?['kind'] == 'ready' &&
          persistence?['pendingCommits'] == 0 &&
          rows.any(
            (r) => (r['text'] as String? ?? '').contains(
              '$marker following paragraph 44.',
            ),
          )) {
        return s;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await File('${output.path}/incomplete-answer.json')
        .writeAsString(jsonEncode(await snapshot()));
    throw StateError('Tool fixture did not complete: $marker');
  }

  Future<Map<String, dynamic>> probe(
    SerializableFinder f,
    String action, {
    double dy = 0,
  }) => driver.sendCommand(ToolProbe(f, action, dy: dy));
  Future<void> place(
    SerializableFinder target,
    double y, {
    double leadingInset = 16,
  }) async {
    for (var i = 0; i < 80; i++) {
      final view = (await probe(timeline, 'observe'))['samples'].last as Map;
      final viewTop = view['top'] as num;
      final viewHeight = view['height'] as num;
      // Application banners can move the viewport. Keep the operation and its
      // surrounding padding visible before judging expansion geometry.
      final wanted = math.max(y, viewTop.toDouble() + leadingInset);
      final geometry = await probe(target, 'observe');
      final sample = (geometry['samples'] as List).last as Map;
      if (sample['mounted'] == false) {
        final state = await snapshot();
        final rows = (state['workspace'] as Map)['timeline'] as List;
        final scroll = state['timelineScroll'] as Map;
        // Client delivery and Flutter layout are independent observations.
        // A completed load can publish its rows before the viewport has laid
        // them out. Let the existing probe cross the framework's endOfFrame
        // barrier before comparing a painted anchor with the new row order.
        if (scroll['rowCount'] != rows.length) {
          layoutWaits.add({
            'iteration': i,
            'projectedRows': rows.length,
            'laidOutRows': scroll['rowCount'],
            'restorePending': scroll['restorePending'],
          });
          await probe(timeline, 'observe');
          continue;
        }
        final key = (target as ByValueKey).keyValue as String;
        final targetIndex = rows.indexWhere(
          (row) =>
              key.contains(row['id'] as String) ||
              (row['itemIds'] as List).any(
                (itemId) => key.contains(itemId as String),
              ),
        );
        final anchor = scroll['anchor'] as Map?;
        final anchorIndex = rows.indexWhere(
          (row) =>
              row['id'] == anchor?['itemId'] ||
              (row['itemIds'] as List).contains(anchor?['itemId']),
        );
        if (targetIndex < 0 && state['timelineWindow']['hasOlder'] == true) {
          // Entering history opens a fresh bounded window. Mixed activities add
          // real items, so the first fixture turn may now be outside that window.
          // Load through the production Client action before locating its widget.
          await driver.requestData('load-older');
          await probe(timeline, 'observe');
          continue;
        }
        if (targetIndex < 0 && state['timelineWindow']['hasNewer'] == true) {
          await driver.requestData('load-newer');
          await probe(timeline, 'observe');
          continue;
        }
        if (targetIndex < 0 || anchorIndex < 0) {
          await File('${output.path}/lazy-target-failure.json').writeAsString(
            jsonEncode({
              'key': key,
              'targetIndex': targetIndex,
              'anchorIndex': anchorIndex,
              'snapshot': state,
            }),
          );
          throw StateError(
            'Cannot locate lazy tool row: $key '
            '(target=$targetIndex, anchor=$anchorIndex)',
          );
        }
        await probe(
          timeline,
          'wheelOutside',
          dy:
              (targetIndex < anchorIndex ? -1 : 1) *
              viewHeight.toDouble() *
              0.8,
        );
        continue;
      }
      final top = (sample['top'] as num).toDouble();
      if ((top - wanted).abs() < 1) return;
      // A fully clipped sliver has a paint extent of zero; its transform is
      // not a distance-to-item estimate. Traverse by viewport steps until the
      // header is visible, then use its actual on-screen position.
      final delta = top < viewTop
          ? -viewHeight * 0.8
          : top > viewTop + viewHeight - 25
          ? viewHeight * 0.8
          : top - wanted;
      await probe(timeline, 'wheelOutside', dy: delta.toDouble());
    }
    throw StateError('Unable to place tool at $y');
  }

  try {
    await driver.sendCommand(SetFrameSync(false));
    final firstAnswer = await waitAnswer('Tool scroll short');
    final sentImages =
        ((firstAnswer['workspace'] as Map)['historyAttachments'] as List)
            .where(
              (attachment) =>
                  attachment['source'] != 'tool' &&
                  attachment['modality'] == 'image',
            )
            .toList();
    if (sentImages.length != 1) throw StateError('Sent image was not archived');
    final sentImageId = (sentImages.single as Map)['id'] as String;
    final firstRows = (firstAnswer['workspace'] as Map)['timeline'] as List;
    await place(
      find.byValueKey('timeline-block-${firstRows.first['id']}'),
      ((await probe(timeline, 'observe'))['samples'].last['top'] as num)
          .toDouble(),
      leadingInset: 0,
    );
    await driver.sendCommand(
      RawTap(find.byValueKey('history-attachment-$sentImageId')),
    );
    await driver.waitFor(find.byValueKey('timeline-image-dialog-$sentImageId'));
    await File('${output.path}/sent-image-dialog.png')
        .writeAsBytes(await driver.screenshot());
    await driver.sendCommand(RawTap(find.byValueKey('timeline-image-close')));
    evidence['sentImage'] = {
      'archived': true,
      'dialogOpened': true,
      'remoteProject': remoteProject,
    };
    await driver.sendCommand(RawTap(find.byValueKey('timeline-jump-latest')));
    for (final kind
        in args.contains('--observe-only')
            ? <String>[]
            : ['medium', 'long', 'arguments', 'multiple', 'failed']) {
      await driver.sendCommand(RawTap(find.byValueKey('composer-input')));
      await driver.enterText('Tool scroll $kind');
      await driver.sendCommand(RawTap(find.byValueKey('composer-submit')));
      await waitAnswer('Tool scroll $kind');
    }
    evidence['wheelNavigation'] = await observeTimelineScrolling(
      args[0],
      output,
    );
    if ((evidence['wheelNavigation'] as Map)['pass'] != true) {
      throw StateError('Wheel/scrollbar navigation failed');
    }
    var s = await snapshot();
    final lazy = s['timelineScroll'] as Map;
    evidence['lazyRows'] = {
      'windowRows': lazy['rowCount'],
      'mountedRows': lazy['mountedRowCount'],
    };
    if ((lazy['rowCount'] as num) <= 8 ||
        (lazy['mountedRowCount'] as num) >= (lazy['rowCount'] as num)) {
      throw StateError('Long timeline eagerly mounted its whole window');
    }
    if ((s['timelineWindow'] as Map)['hasOlder'] == true) {
      await driver.requestData('load-older');
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      do {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        s = await snapshot();
      } while ((s['timelineWindow'] as Map)['hasOlder'] == true &&
          DateTime.now().isBefore(deadline));
    }
    await File('${output.path}/fixture-snapshot.json')
        .writeAsString(jsonEncode(s));
    final groups = ((s['workspace'] as Map)['timeline'] as List)
        .where((r) => r['type'] == 'activityGroup')
        .toList();
    if (groups.length != 6) {
      throw StateError('Expected 6 real tool groups, got ${groups.length}');
    }
    final imageRows = ((s['workspace'] as Map)['timeline'] as List)
        .cast<Map>()
        .where((row) => row['type'] == 'imageRead')
        .toList();
    if (imageRows.length != 2) {
      throw StateError('Expected two independent image reads');
    }
    final imageGroup = imageRows.first;
    final summary = find.byValueKey('timeline-block-${imageGroup['id']}');
    await place(summary, 120);
    final imageTools = imageRows.expand((row) => row['tools'] as List).toList();
    if (imageTools.isNotEmpty) {
      final entries = <String>[];
      for (final tool in imageTools) {
        final attachments = tool['attachments'] as List;
        if (tool['status'] != 'succeeded' || attachments.isEmpty) {
          throw StateError('view_image did not archive its image');
        }
        entries.add('${tool['callId']}:${attachments.single['id']}');
      }
      final first = entries.first;
      final toggle = find.byValueKey('view-image-toggle-$first');
      final thumbnail = find.byValueKey('view-image-thumbnail-$first');
      await driver.sendCommand(RawTap(toggle));
      await driver.waitFor(thumbnail, timeout: const Duration(seconds: 10));
      await driver.sendCommand(RawTap(thumbnail));
      await driver.waitFor(find.byValueKey('view-image-dialog-$first'));
      await File('${output.path}/agent-read-image-dialog.png')
          .writeAsBytes(await driver.screenshot());
      await driver.sendCommand(RawTap(find.byValueKey('timeline-image-close')));
      if ((await probe(
            find.byValueKey('view-image-thumbnail-${entries.last}'),
            'observe',
          ))['samples'].last['mounted'] !=
          false) {
        throw StateError('Distinct image calls share expansion state');
      }
      // Recycle the containing row, then return without toggling it again.
      final jump = find.byValueKey('timeline-jump-latest');
      await driver.sendCommand(RawTap(jump));
      await driver.waitForAbsent(
        thumbnail,
        timeout: const Duration(seconds: 10),
      );
      await place(summary, 120);
      await driver.waitFor(thumbnail, timeout: const Duration(seconds: 10));
      await File('${output.path}/agent-read-image-recycled.png')
          .writeAsBytes(await driver.screenshot());
      await driver.sendCommand(RawTap(toggle));
      await driver.waitForAbsent(thumbnail);
      evidence['agentReadImage'] = {
        'distinctCalls': entries.length,
        'dialogOpened': true,
        'survivedRowRecycling': true,
        'collapsed': true,
      };
      await place(summary, 120);
    }
    final cases = <Object?>[];
    evidence['cases'] = cases;
    for (var index = 0; index < groups.length; index++) {
      stdout.writeln('tool_scroll_case=$index');
      var row = groups[index] as Map;
      final callId = (row['tools'] as List).first['callId'];
      final kinds = row['activityKinds'] as List;
      if (!kinds.contains('reasoning') || !kinds.contains('tool')) {
        throw StateError('Thinking and tools were not merged for $callId');
      }
      if (callId == 'scroll-call-medium' &&
          kinds.where((kind) => kind == 'reasoning').length != 2) {
        throw StateError(
          'Thinking after a tool must remain in the same activity group',
        );
      }
      final summary = find.byValueKey('timeline-activity-summary-${row['id']}');
      await place(summary, 120);
      for (final item in row['tools'] as List) {
        if (((await snapshot())['timelineWindow']['previewedItemIds'] as List)
            .contains(item['itemId'])) {
          await driver.sendCommand(
            RawTap(
              find.byValueKey('timeline-item-body-load-${item['itemId']}'),
            ),
          );
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (((await snapshot())['timelineWindow']['previewedItemIds']
                  as List)
              .contains(item['itemId'])) {
            if (DateTime.now().isAfter(deadline)) {
              throw StateError('Tool body did not load');
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
      row =
          (((await snapshot())['workspace'] as Map)['timeline'] as List)
                  .firstWhere((r) => r['id'] == row['id'])
              as Map;
      await place(summary, 120);
      final opened = await probe(summary, 'tap');
      final record = <String, Object?>{'index': index, 'groupOpen': opened};
      cases.add(record);
      final items = row['tools'] as List;
      if (items.any(
        (item) =>
            item['status'] !=
            (callId == 'scroll-call-failed' ? 'failed' : 'succeeded'),
      )) {
        throw StateError('Unexpected tool outcome in case $index');
      }
      if (callId == 'scroll-call-long' &&
          jsonDecode(items.single['result'] as String)['count'] != 200) {
        throw StateError('Long result was not delivered whole');
      }
      if (callId == 'scroll-call-arguments' &&
          (items.single['arguments'] as String).length < 12000) {
        throw StateError('Long arguments were truncated');
      }
      final tiles = <Object?>[];
      record['tiles'] = tiles;
      for (var j = 0; j < items.length; j++) {
        final item = items[j] as Map;
        final tile = find.byValueKey('timeline-tool-details:${item['itemId']}');
        await place(tile, 125);
        final expanded = await probe(tile, 'tap');
        await File('${output.path}/case-$index-tool-$j-expanded.png')
            .writeAsBytes(await driver.screenshot());
        final nested = (expanded['samples'] as List).last['nested'] as List;
        Map<String, dynamic>? inside;
        if (nested.any(
          (s) => s['axis'] == 'vertical' && (s['max'] as num) > 0,
        )) {
          // Move the output into the viewport; the tool title may now be above it.
          await place(tile, 80);
          inside = await probe(tile, 'wheelInner', dy: 60);
          await place(tile, 125);
        }
        final collapsed = await probe(tile, 'tap');
        tiles.add({
          'item': item['itemId'],
          'argumentLength': (item['arguments'] as String? ?? '').length,
          'outputLength': (item['result'] as String? ?? '').length,
          'expanded': expanded,
          'collapsed': collapsed,
          'inside': inside,
        });
      }
      await place(summary, 95);
      record['groupClose'] = await probe(summary, 'tap');
      await File('${output.path}/case-$index-collapsed.png')
          .writeAsBytes(await driver.screenshot());
    }
    // Leave one group open, visit a later group, then return to the earlier
    // group and expand its nested tool after its row has been recycled.
    stdout.writeln('tool_scroll_reverse');
    Map groupFor(String callId) => groups.cast<Map>().singleWhere(
      (row) => (row['tools'] as List).any((tool) => tool['callId'] == callId),
    );
    final earlier = groupFor('scroll-call-medium');
    final later = groupFor('scroll-call-arguments');
    final earlierSummary = find.byValueKey(
      'timeline-activity-summary-${earlier['id']}',
    );
    final laterSummary = find.byValueKey(
      'timeline-activity-summary-${later['id']}',
    );
    await place(earlierSummary, 120);
    await probe(earlierSummary, 'tap');
    await place(laterSummary, 120);
    await probe(laterSummary, 'tap');
    final earlierTile = find.byValueKey(
      'timeline-tool-details:${(earlier['tools'] as List).first['itemId']}',
    );
    await place(earlierTile, 125);
    evidence['reverseExpansion'] = await probe(earlierTile, 'tap');
    await File('${output.path}/reverse-expanded.png')
        .writeAsBytes(await driver.screenshot());
    await place(earlierTile, 125);
    evidence['reverseCollapse'] = await probe(earlierTile, 'tap');
    final imageTool = (imageGroup['tools'] as List).firstWhere(
      (tool) => tool['name'] == 'view_image',
    ) as Map;
    final imageId =
        '${imageTool['callId']}:${(imageTool['attachments'] as List).first['id']}';
    final originalThread = (s['navigation'] as Map)['selectedThreadId'];
    final previousView = (await snapshot())['timelineWindow']['viewId'];
    if (previousView == null) {
      throw StateError('Content view identity is missing');
    }
    await driver.sendCommand(RawTap(find.byValueKey('sidebar-new-session')));
    await driver.waitFor(
      find.byValueKey('start-page-selectors'),
      timeout: const Duration(seconds: 10),
    );
    await driver.sendCommand(
      RawTap(find.byValueKey('thread-row-$originalThread')),
    );
    final reopenDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      final reopened = await snapshot();
      final workspace = reopened['workspace'] as Map?;
      final window = reopened['timelineWindow'] as Map;
      if (reopened['navigation']['selectedThreadId'] == originalThread &&
          workspace?['syncState'] == 'ready' &&
          window['ready'] == true &&
          window['loading'] != true &&
          window['viewId'] != null &&
          window['viewId'] != previousView) {
        evidence['reopenedView'] = {
          'previous': previousView,
          'current': window['viewId'],
        };
        break;
      }
      if (DateTime.now().isAfter(reopenDeadline)) {
        throw StateError('Historical image window did not reopen');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await place(find.byValueKey('timeline-block-${imageGroup['id']}'), 120);
    await driver.sendCommand(
      RawTap(find.byValueKey('view-image-toggle-$imageId')),
    );
    await driver.waitFor(
      find.byValueKey('view-image-thumbnail-$imageId'),
      timeout: const Duration(seconds: 10),
    );
    await File('${output.path}/agent-read-image-reopened.png')
        .writeAsBytes(await driver.screenshot());
    (evidence['agentReadImage'] as Map)['reopenedFromHistory'] = true;
    await place(
      find.byValueKey('timeline-block-${firstRows.first['id']}'),
      ((await probe(timeline, 'observe'))['samples'].last['top'] as num)
          .toDouble(),
      leadingInset: 0,
    );
    await driver.sendCommand(
      RawTap(find.byValueKey('history-attachment-$sentImageId')),
    );
    await driver.waitFor(find.byValueKey('timeline-image-dialog-$sentImageId'));
    await File('${output.path}/sent-image-reopened.png')
        .writeAsBytes(await driver.screenshot());
    await driver.sendCommand(RawTap(find.byValueKey('timeline-image-close')));
    (evidence['sentImage'] as Map)['reopenedFromHistory'] = true;

    bool headerStable(Object? probe) {
      final samples = (probe as Map)['samples'] as List;
      final initial = samples.first['top'] as num;
      return samples.every((s) => ((s['top'] as num) - initial).abs() < 1);
    }

    bool expansionChanged(Object? probe, bool expanded) {
      final samples = (probe as Map)['samples'] as List;
      return samples.first['expanded'] == !expanded &&
          samples.last['expanded'] == expanded;
    }

    final checks = <bool>[];
    checks.add(headerStable(evidence['reverseExpansion']));
    checks.add(headerStable(evidence['reverseCollapse']));
    checks.add(expansionChanged(evidence['reverseExpansion'], true));
    checks.add(expansionChanged(evidence['reverseCollapse'], false));
    for (final c in cases.cast<Map>()) {
      checks.add(headerStable(c['groupOpen']));
      checks.add(headerStable(c['groupClose']));
      checks.add(expansionChanged(c['groupOpen'], true));
      checks.add(expansionChanged(c['groupClose'], false));
      for (final t in (c['tiles'] as List).cast<Map>()) {
        checks.add(headerStable(t['expanded']));
        checks.add(headerStable(t['collapsed']));
        checks.add(expansionChanged(t['expanded'], true));
        checks.add(expansionChanged(t['collapsed'], false));
        final expanded = (t['expanded'] as Map)['samples'] as List;
        final collapsed = (t['collapsed'] as Map)['samples'] as List;
        checks.add(
          (expanded.last['height'] as num) >
              (expanded.first['height'] as num) + 20,
        );
        checks.add(
          (collapsed.last['height'] as num) <
              (collapsed.first['height'] as num) - 20,
        );
        final inside = t['inside'] as Map?;
        if (inside != null) {
          final samples = inside['samples'] as List;
          final before = samples.first as Map;
          final after = samples.last as Map;
          checks.add(
            ((before['scroll']['pixels'] as num) -
                        (after['scroll']['pixels'] as num))
                    .abs() <
                0.5,
          );
          final nestedBefore = (before['nested'] as List)
              .where((n) => n['axis'] == 'vertical' && (n['max'] as num) > 0)
              .last;
          final nestedAfter = (after['nested'] as List)
              .where((n) => n['axis'] == 'vertical' && (n['max'] as num) > 0)
              .last;
          checks.add(
            (nestedAfter['pixels'] as num) > (nestedBefore['pixels'] as num),
          );
        }
      }
    }
    evidence['checks'] = checks;
    evidence['checksPassed'] = checks.every((v) => v);
    evidence['latestViewportFill'] = await observeLatestViewportFill(
      driver,
      output,
    );
    if (evidence['checksPassed'] != true) exitCode = 1;
  } finally {
    await File('${output.path}/tool-scroll.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    await driver.close();
  }
}
