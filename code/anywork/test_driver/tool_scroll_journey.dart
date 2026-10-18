import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_driver/flutter_driver.dart';

import 'raw_tap.dart';
import 'tool_probe.dart';
import 'scrolling_journey.dart';
import 'timeline_fill_journey.dart';
import 'timeline_observation.dart';
import 'stress_start.dart' as start;

/// 产品动态正文展示预算（`PRODUCT_PREVIEW_BYTES`）。
const _productPreviewBudgetBytes = 32 * 1024;

/// 工具参数/结果各自的展示预算（`TOOL_FIELD_PREVIEW_BYTES`）。
const _toolFieldPreviewBudgetBytes = 4 * 1024;

/// 该 journey 在隔离项目里创建的文件数（`scroll-fixture/entry-000..239.txt`）。
const _fixtureEntryCount = 240;

/// 剧本给 `scroll-call-long` 的 `list_files` limit。
const _listFilesLimit = 200;

String _fixtureEntryName(int index) =>
    'entry-${index.toString().padLeft(3, '0')}.txt';

/// 剧本给 `scroll-call-arguments` 生成的 `exec` 参数原文（与 fixture 逐字节一致）。
///
/// 来源：`pl-provider-fixture` 的 `realtime_exec_arguments`（`{"command": ...}` 单键
/// JSON）+ 12000 字符 padding 的命令构造。这里由 fixture 事实推出**期望原文**，不是
/// 从实际加载内容反推。
String _expectedScrollArguments() {
  const lines = 12;
  const padding = 12000;
  final command =
      'i=1; while [ "\$i" -le $lines ]; do '
      "printf 'line-%s tool output\\n' \"\$i\"; "
      'i=\$((i+1)); done # ${'argument ' * (padding ~/ 9)}';
  return jsonEncode(<String, Object?>{'command': command});
}

/// FNV-1a over the code units. Must stay identical to the Driver-side helper.
int _fnv1a64(String text) {
  var hash = 0xcbf29ce484222325;
  for (var index = 0; index < text.length; index += 1) {
    hash ^= text.codeUnitAt(index);
    hash = hash * 0x100000001b3;
  }
  return hash;
}

/// 校验完整复制的 `list_files` 结果：按**真实后端语义**判定，而不是全目录键序。
///
/// 该 journey 在隔离项目里创建 `scroll-fixture/entry-000.txt`…`entry-239.txt`，剧本以
/// `{"path":"scroll-fixture","limit":200}` 调用 `list_files`。真实工具
/// （`pl-tool/src/workspace_file/local.rs` + `ops.rs`）先**限量遍历**再排序截断，因此
/// 返回的是某个 bounded traversal 子集内排序后的 200 条，**不保证**是全目录编号最小的
/// 200 条。这里只断言后端确实提供的性质：完整路径形状、索引范围、严格升序、无重复、
/// 数量/count 一致，以及真实存在的游标与 hash 字段；不从实际复制内容反推期望。
Map<String, Object?> _validateLongResult(String text, int expectedBytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    return <String, Object?>{'valid': false, 'reason': 'invalidJson: $error'};
  }
  if (decoded is! Map) {
    return <String, Object?>{'valid': false, 'reason': 'resultIsNotAnObject'};
  }
  final files = decoded['files'];
  final resultHash = decoded['resultHash'];
  final pathPattern = RegExp(r'^scroll-fixture/entry-(\d{3})\.txt$');
  final deliveredFiles = <String>[
    if (files is List)
      for (final entry in files)
        if (entry is String) entry,
  ];
  var allStrings = files is List && deliveredFiles.length == files.length;
  var pathShapeOk = allStrings;
  var indexInFixtureRange = allStrings;
  var strictlyAscending = allStrings;
  var duplicateFree = true;
  final seen = <String>{};
  for (var index = 0; index < deliveredFiles.length; index += 1) {
    final file = deliveredFiles[index];
    final match = pathPattern.firstMatch(file);
    if (match == null) {
      pathShapeOk = false;
      allStrings = false;
      continue;
    }
    final ordinal = int.parse(match.group(1)!);
    if (ordinal < 0 || ordinal >= _fixtureEntryCount) {
      indexInFixtureRange = false;
    }
    if (!seen.add(file)) duplicateFree = false;
    if (index > 0 && deliveredFiles[index - 1].compareTo(file) >= 0) {
      strictlyAscending = false;
    }
  }
  final checks = <String, Object?>{
    'filesIsList': files is List,
    'filesAllStrings': allStrings,
    'pathOk': decoded['path'] == 'scroll-fixture',
    'globOk': decoded['glob'] == '*',
    'includeDirsOk': decoded['includeDirs'] == false,
    'cursorResetOk': decoded['cursorReset'] == false,
    'countMatchesFiles': files is List && decoded['count'] == files.length,
    'countIsLimit': decoded['count'] == _listFilesLimit,
    'filesIsLimit': files is List && files.length == _listFilesLimit,
    'pathShapeOk': pathShapeOk,
    'indexInFixtureRange': indexInFixtureRange,
    'strictlyAscending': strictlyAscending,
    'duplicateFree': duplicateFree,
    // 240 个 fixture 文件 > 200 的 limit，所以下一页游标必须存在。
    'fixtureLargerThanLimit': _listFilesLimit < _fixtureEntryCount,
    'hasNextCursor':
        decoded['nextCursor'] is String &&
        (decoded['nextCursor'] as String).isNotEmpty,
    'resultHashWellFormed':
        resultHash is String &&
        RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(resultHash),
    'lengthMatchesDetail': utf8.encode(text).length == expectedBytes,
  };
  final valid = checks.values.every((value) => value == true);
  return <String, Object?>{
    'valid': valid,
    'expectedBytes': expectedBytes,
    'deliveredBytes': utf8.encode(text).length,
    'count': decoded['count'],
    'deliveredFirstFile': deliveredFiles.isEmpty ? null : deliveredFiles.first,
    'deliveredLastFile': deliveredFiles.isEmpty ? null : deliveredFiles.last,
    'checks': checks,
  };
}

/// 当前真正可见（与视口相交）的行 id，按可见位置自上而下。
///
/// 只读：请求时扫描挂载的 element/render tree，不建立每行测量表，也不写回产品。
Future<List<String>> _visibleTimelineRowIds(FlutterDriver driver) async {
  final raw = await driver.requestData(
    jsonEncode(<String, Object?>{'cmd': 'timeline-geometry'}),
  );
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw StateError('timeline geometry response is not an object: $raw');
  }
  return <String>[
    for (final row in TimelineRowsObservation.parse(decoded).visible) row.id,
  ];
}

/// 已加载集合里与 [key] 对应的 canonical 条目 ordinal；不在集合里返回 null。
///
/// 与 `place` 的“已加载”判据同源：条目身份、附件身份或工具附件身份包含在 key 里。
int? _loadedTargetOrdinal(TimelineObservation timeline, String key) {
  for (final item in timeline.items) {
    if (key.contains(item.id) ||
        item.attachments.any((attachment) => key.contains(attachment.id)) ||
        (item.tool?.attachments.any(
              (attachment) => key.contains(attachment.id),
            ) ??
            false)) {
      return item.ordinal;
    }
  }
  return null;
}

int? _ordinalOfItemId(TimelineObservation timeline, String id) {
  for (final item in timeline.items) {
    if (item.id == id) return item.ordinal;
  }
  return null;
}

/// 目标相对当前可见行的外层滚动方向。
///
/// 反向列表：offset 0 在最新端，向更早内容滚动是 offset 增大（滚轮负向）。ordinal
/// 随 canonical 顺序递增，所以目标 ordinal 小于可见最小值即更早。
String? _scrollDirectionToward(int ordinal, List<int> visibleOrdinals) {
  if (visibleOrdinals.isEmpty) return null;
  final lowest = visibleOrdinals.reduce(math.min);
  final highest = visibleOrdinals.reduce(math.max);
  if (ordinal < lowest) return 'older';
  if (ordinal > highest) return 'newer';
  // 目标 ordinal 落在可见区间内部却没有挂载：观测矛盾，交由调用方强失败。
  return null;
}

Future<void> main(List<String> args) async {
  String? remoteProject;
  if (args.length >= 3 && args[2] != '--observe-only') {
    final fixtures = Directory('${args[2]}/scroll-fixture');
    await fixtures.create(recursive: true);
    for (var i = 0; i < _fixtureEntryCount; i++) {
      await File('${fixtures.path}/${_fixtureEntryName(i)}')
          .writeAsString('Tool scrolling fixture\n');
    }
    await File('test_driver/fixtures/tool-image.png')
        .copy('${args[2]}/tool-image.png');
    final git = await Process.run('git', ['init', '-q', args[2]]);
    if (git.exitCode != 0) throw StateError('Fixture project: ${git.stderr}');
    if (args.length >= 4) {
      final target = args[3];
      final parent = args.length >= 5 ? args[4] : '/tmp';
      if (!RegExp(r'^/[a-zA-Z0-9_./-]+$').hasMatch(parent) ||
          parent.split('/').contains('..')) {
        throw ArgumentError('Expected an absolute POSIX fixture parent');
      }
      if (!RegExp(r'^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+$').hasMatch(target)) {
        throw ArgumentError('Expected SSH user@host');
      }
      final created = await Process.run('ssh', [
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=10',
        target,
        'mktemp -d $parent/anywork-image-acceptance-XXXXXXXX',
      ]);
      remoteProject = (created.stdout as String).trim();
      if (created.exitCode != 0 ||
          !RegExp(
            '^${RegExp.escape(parent)}/anywork-image-acceptance-[a-zA-Z0-9]+\$',
          ).hasMatch(remoteProject)) {
        throw StateError('Remote fixture directory: ${created.stderr}');
      }
      final copied = await Process.run('scp', [
        '-q',
        '-r',
        'scroll-fixture',
        'tool-image.png',
        '$target:$remoteProject/',
      ], workingDirectory: args[2]);
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
      final timeline = TimelineObservation.optional(s);
      final persistence = s['persistence'] as Map?;
      if (w?['isBusy'] == false &&
          persistence?['kind'] == 'ready' &&
          persistence?['pendingCommits'] == 0 &&
          (timeline?.items.any(
                (item) => item.text.contains('$marker following paragraph 44.'),
              ) ??
              false)) {
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
    // 连续“真实滚动却没有进展”的次数：到边界仍不可见时强失败，不静默吞。
    var noProgress = 0;
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
        final timelineFact = TimelineObservation.parse(state);
        final key = (target as ByValueKey).keyValue as String;
        final targetOrdinal = _loadedTargetOrdinal(timelineFact, key);
        // 目标不在已加载集合时，只有真实存在的更早页才值得继续向前加载；
        // 目标本来就在集合里则是惰性布局，必须用真实外层滚动把它带进布局。
        if (targetOrdinal == null) {
          if (timelineFact.hasOlder) {
            await driver.requestData('load-older');
            layoutWaits.add({
              'iteration': i,
              'reason': 'targetOutsideLoadedItems',
              'itemCount': timelineFact.itemCount,
              'olderCursor': timelineFact.olderCursor,
            });
            await probe(timeline, 'observe');
            continue;
          }
          await File('${output.path}/lazy-target-failure.json').writeAsString(
            jsonEncode({
              'key': key,
              'itemCount': timelineFact.itemCount,
              'itemIds': timelineFact.itemIds,
              'hasOlder': timelineFact.hasOlder,
              'snapshot': state,
            }),
          );
          throw StateError(
            'Cannot locate lazy tool row: $key '
            '(items=${timelineFact.itemCount}, hasOlder=${timelineFact.hasOlder})',
          );
        }
        // 已加载 ≠ 已挂载：标准惰性列表只为相邻内容建立 render 对象，离屏行不会
        // 因为等帧而自己出现。用正常的外层滚轮把它带进布局/可见区，方向按 canonical
        // ordinal 与当前真实可见行比较，再回到循环开头按真实 rect 精确 place。
        final visibleIds = await _visibleTimelineRowIds(driver);
        final visibleOrdinals = <int>[
          for (final id in visibleIds) ?_ordinalOfItemId(timelineFact, id),
        ];
        final direction = _scrollDirectionToward(
          targetOrdinal,
          visibleOrdinals,
        );
        if (direction == null) {
          await File('${output.path}/unreachable-target-failure.json')
              .writeAsString(
                jsonEncode({
                  'key': key,
                  'targetOrdinal': targetOrdinal,
                  'reason': 'noScrollDirection',
                  'itemCount': timelineFact.itemCount,
                  'itemIds': timelineFact.itemIds,
                  'visibleIds': visibleIds,
                  'visibleOrdinals': visibleOrdinals,
                  'scroll': TimelineScrollObservation.parse(state).toJson(),
                  'snapshot': state,
                }),
              );
          throw StateError(
            'Loaded target row $key (ordinal $targetOrdinal) is not mounted and '
            'the visible rows $visibleOrdinals give no outer scroll direction',
          );
        }
        final scrollBefore = TimelineScrollObservation.parse(state);
        // 步长小于一个视口：新可见区间与旧区间重叠，目标只会被逐步逼近，
        // 不会因为跨步而越过目标。
        final dy = ((direction == 'older' ? -viewHeight : viewHeight) * 0.8)
            .toDouble();
        await probe(timeline, 'wheelOutside', dy: dy);
        final afterState = await snapshot();
        final scrollAfter = TimelineScrollObservation.parse(afterState);
        final afterVisibleIds = await _visibleTimelineRowIds(driver);
        final pixelsMoved =
            scrollBefore.pixels != null &&
            scrollAfter.pixels != null &&
            (scrollAfter.pixels! - scrollBefore.pixels!).abs() > 0.5;
        final visibleChanged =
            visibleIds.join('|') != afterVisibleIds.join('|');
        noProgress = pixelsMoved || visibleChanged ? 0 : noProgress + 1;
        layoutWaits.add({
          'iteration': i,
          'reason': 'scrolledToLoadedTarget',
          'direction': direction,
          'targetOrdinal': targetOrdinal,
          'visibleOrdinals': visibleOrdinals,
          'dy': dy,
          'pixelsBefore': scrollBefore.pixels,
          'pixelsAfter': scrollAfter.pixels,
          'maxScrollExtent': scrollAfter.maxScrollExtent,
          'extentBefore': scrollAfter.extentBefore,
          'extentAfter': scrollAfter.extentAfter,
          'atLiveEdge': scrollAfter.atLiveEdge,
          'pixelsMoved': pixelsMoved,
          'visibleChanged': visibleChanged,
          'itemCount': timelineFact.itemCount,
        });
        if (noProgress >= 3) {
          await File('${output.path}/unreachable-target-failure.json')
              .writeAsString(
                jsonEncode({
                  'key': key,
                  'targetOrdinal': targetOrdinal,
                  'reason': 'outerScrollAtBoundary',
                  'direction': direction,
                  'itemCount': timelineFact.itemCount,
                  'itemIds': timelineFact.itemIds,
                  'visibleIds': visibleIds,
                  'visibleOrdinals': visibleOrdinals,
                  'afterVisibleIds': afterVisibleIds,
                  'scrollBefore': scrollBefore.toJson(),
                  'scrollAfter': scrollAfter.toJson(),
                  'snapshot': afterState,
                }),
              );
          throw StateError(
            'Loaded target row $key (ordinal $targetOrdinal) never became '
            'mounted: three real outer wheel steps toward $direction moved no '
            'offset and changed no visible row '
            '(pixels ${scrollAfter.pixels}/${scrollAfter.maxScrollExtent}, '
            'visible $visibleIds)',
          );
        }
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
    throw StateError(
      'Unable to place tool at $y: 80 observations did not reach it '
      '(last=${layoutWaits.isEmpty ? null : layoutWaits.last})',
    );
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
    final firstItems = TimelineObservation.parse(firstAnswer).items;
    await place(
      find.byValueKey('timeline-row-${firstItems.first.id}'),
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
    await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
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
    // 惰性证明：只观察当前挂载的行（请求时扫描），不要求窗口裁剪。
    final mountedRows = TimelineRowsObservation.parse(
      (jsonDecode(
        await driver.requestData(
          jsonEncode(<String, Object?>{'cmd': 'timeline-geometry'}),
        ),
      ) as Map).cast<String, dynamic>(),
    );
    final loaded = TimelineObservation.parse(s);
    evidence['lazyRows'] = {
      'loadedItems': loaded.itemCount,
      'mountedRows': mountedRows.rows.length,
      'mode': loaded.mode,
      'generation': loaded.generation,
    };
    if (loaded.itemCount <= 8 || mountedRows.rows.length >= loaded.itemCount) {
      throw StateError('Long timeline eagerly mounted every loaded item');
    }
    if (loaded.hasOlder) {
      await driver.requestData('load-older');
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      do {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        s = await snapshot();
      } while ((TimelineObservation.parse(s).hasOlder) &&
          DateTime.now().isBefore(deadline));
    }
    await File('${output.path}/fixture-snapshot.json')
        .writeAsString(jsonEncode(s));
    final loadedTimeline = TimelineObservation.parse(s);
    // 每个 canonical 工具调用都是独立消息，不再合并成活动组。
    final tools = loadedTimeline.items
        .where((item) => item.kind == 'toolCall' && item.tool != null)
        .toList();
    if (tools.length != 6) {
      throw StateError('Expected 6 real tool items, got ${tools.length}');
    }
    final reasoningItems = loadedTimeline.items
        .where((item) => item.kind == 'reasoning')
        .toList();
    if (reasoningItems.length < 3) {
      throw StateError(
        'Expected reasoning items to stay independent, got '
        '${reasoningItems.length}',
      );
    }
    final imageItems = loadedTimeline.items
        .where(
          (item) =>
              item.tool?.name == 'view_image' &&
              item.tool!.attachments.isNotEmpty,
        )
        .toList();
    if (imageItems.length != 2) {
      throw StateError('Expected two independent image reads');
    }
    final imageItem = imageItems.first;
    final summary = find.byValueKey('timeline-row-${imageItem.id}');
    await place(summary, 120);
    final imageTools = imageItems
        .map((item) => item.tool!)
        .toList(growable: false);
    if (imageTools.isNotEmpty) {
      final entries = <String>[];
      for (final tool in imageTools) {
        final attachments = tool.attachments;
        if (tool.status != 'succeeded' || attachments.isEmpty) {
          throw StateError('view_image did not archive its image');
        }
        entries.add('${tool.callId}:${attachments.single.id}');
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
      // 显式回到实时建立新代次，再让惰性列表回收该行。
      final jump = find.byValueKey('timeline-return-live');
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
    // 详情逐块读取：只有用户显式打开查看器才读取完整字段，关闭后停止。
    Future<Map<String, Object?>> readDetail(
      String itemId,
      String field, {
      required int expectedBytes,
    }) async {
      final openKey = 'timeline-detail-open-$itemId-$field';
      await driver.waitFor(
        find.byValueKey(openKey),
        timeout: const Duration(seconds: 20),
      );
      await driver.sendCommand(RawTap(find.byValueKey(openKey)));
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      Map<String, dynamic>? progress;
      var sawPartial = false;
      while (DateTime.now().isBefore(deadline)) {
        progress = (jsonDecode(
          await driver.requestData('timeline-detail-text'),
        ) as Map).cast<String, dynamic>();
        final characters = (progress['characters'] as num? ?? 0).toInt();
        if (characters > 0 && characters < expectedBytes) sawPartial = true;
        if (characters >= expectedBytes) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await driver.sendCommand(RawTap(find.byValueKey('timeline-detail-copy')));
      // 完整剪贴板原文：用来与 fixture 推出的期望原文/结构比较，而不是自证 hash。
      final clipboard = (jsonDecode(
        await driver.requestData('{"cmd":"clipboard-text","full":true}'),
      ) as Map).cast<String, dynamic>();
      await driver.sendCommand(
        RawTap(find.byValueKey('timeline-detail-close')),
      );
      final closeDeadline = DateTime.now().add(const Duration(seconds: 15));
      var closed = false;
      while (DateTime.now().isBefore(closeDeadline)) {
        final state = (jsonDecode(
          await driver.requestData('timeline-detail-text'),
        ) as Map).cast<String, dynamic>();
        if (state['open'] == false) {
          closed = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final loadedCharacters = (progress?['characters'] as num? ?? 0).toInt();
      final loadedHash = progress?['hash'];
      // 完整字节 + 查看器/剪贴板一致 + 已关闭即可证明保真；`sawPartialChunk`
      // 只记录（快速多块读取允许在一次轮询前完成，产品不需要为观测放慢）。
      final pass =
          loadedCharacters == expectedBytes &&
          clipboard['characters'] == expectedBytes &&
          loadedHash != null &&
          clipboard['hash'] == loadedHash &&
          closed;
      return <String, Object?>{
        'field': field,
        'expectedBytes': expectedBytes,
        // 理论块数（ceil(bytes/64KiB)），不是实际读了多少块。
        'theoreticalChunks': (expectedBytes / (64 * 1024)).ceil(),
        'loadedCharacters': loadedCharacters,
        'loadedHash': loadedHash,
        'sawPartialChunk': sawPartial,
        'clipboardCharacters': clipboard['characters'],
        'clipboardHash': clipboard['hash'],
        'clipboardText': clipboard['text'],
        'closed': closed,
        'pass': pass,
      };
    }

    final cases = <Object?>[];
    evidence['cases'] = cases;
    final detailReads = <Object?>[];
    evidence['detailReads'] = detailReads;
    for (var index = 0; index < tools.length; index++) {
      stdout.writeln('tool_scroll_case=$index');
      final toolItem = tools[index];
      final tool = toolItem.tool!;
      final callId = tool.callId;
      final expectedStatus = callId == 'scroll-call-failed'
          ? 'failed'
          : 'succeeded';
      if (tool.status != expectedStatus) {
        throw StateError(
          'Unexpected tool outcome in case $index: ${tool.status}',
        );
      }
      // F2：每个字段的预览都必须落在真实预算内（参数/结果各 4 KiB，正文共享 32 KiB）。
      for (final detail in toolItem.details) {
        // 只有工具参数与工具结果各有 4 KiB 独立额度；output artifacts 与其它
        // 动态正文共用产品 32 KiB 预算，不能把 artifacts 误收紧成 4 KiB。
        final budget =
            detail.field == 'tool-arguments' || detail.field == 'tool-result'
            ? _toolFieldPreviewBudgetBytes
            : _productPreviewBudgetBytes;
        if (detail.previewBytes > budget ||
            detail.previewBytes > detail.totalBytes) {
          throw StateError(
            'detail ${detail.field} preview ${detail.previewBytes} exceeds '
            'budget $budget of total ${detail.totalBytes}',
          );
        }
      }
      final tile = find.byValueKey('timeline-tool-details:${toolItem.id}');
      await place(tile, 125);
      final expanded = await probe(tile, 'tap');
      await File('${output.path}/case-$index-tool-expanded.png')
          .writeAsBytes(await driver.screenshot());
      final nested = (expanded['samples'] as List).last['nested'] as List;
      Map<String, dynamic>? inside;
      if (nested.any((s) => s['axis'] == 'vertical' && (s['max'] as num) > 0)) {
        // Move the output into the viewport; the tool title may now be above it.
        await place(tile, 80);
        inside = await probe(tile, 'wheelInner', dy: 60);
        await place(tile, 125);
      }
      final collapsed = await probe(tile, 'tap');
      var longResult = <String, Object?>{};
      var longArguments = <String, Object?>{};
      if (callId == 'scroll-call-long') {
        final detail = toolItem.detail('tool-result');
        if (detail == null) {
          throw StateError('Long result has no detail reference');
        }
        // 结果超出 4 KiB 字段额度时行内只有预览：完整正文必须经查看器读取，
        // 再用 fixture 事实校验完整复制内容（不是自证 hash）。
        if (detail.previewBytes > _toolFieldPreviewBudgetBytes ||
            detail.previewBytes >= detail.totalBytes) {
          throw StateError(
            'Long result preview ignored the 4 KiB field budget: '
            '${detail.previewBytes} of ${detail.totalBytes}',
          );
        }
        longResult = await readDetail(
          toolItem.id,
          'tool-result',
          expectedBytes: detail.totalBytes,
        );
        detailReads.add(longResult);
        final copied = longResult['clipboardText'];
        final validation = copied is String
            ? _validateLongResult(copied, detail.totalBytes)
            : <String, Object?>{
                'valid': false,
                'reason': 'clipboardTextMissing',
              };
        longResult['fixtureValidation'] = validation;
        longResult['pass'] =
            longResult['pass'] == true && validation['valid'] == true;
        if (longResult['pass'] != true) {
          throw StateError('Long result viewer read/copy failed: $longResult');
        }
      }
      if (callId == 'scroll-call-arguments') {
        final detail = toolItem.detail('tool-arguments');
        final expected = _expectedScrollArguments();
        final expectedBytes = utf8.encode(expected).length;
        if (detail == null || detail.totalBytes != expectedBytes) {
          throw StateError(
            'Long arguments total ${detail?.totalBytes} != fixture '
            '$expectedBytes bytes',
          );
        }
        if (detail.previewBytes > _toolFieldPreviewBudgetBytes ||
            detail.previewBytes >= detail.totalBytes) {
          throw StateError(
            'Long arguments preview ignored the 4 KiB field budget: '
            '${detail.previewBytes} of ${detail.totalBytes}',
          );
        }
        longArguments = await readDetail(
          toolItem.id,
          'tool-arguments',
          expectedBytes: detail.totalBytes,
        );
        detailReads.add(longArguments);
        final copied = longArguments['clipboardText'];
        final expectedHash = _fnv1a64(expected).toRadixString(16);
        final matchesFixture =
            copied == expected &&
            longArguments['loadedHash'] == expectedHash &&
            longArguments['clipboardHash'] == expectedHash;
        longArguments['expectedHash'] = expectedHash;
        longArguments['matchesFixtureText'] = copied == expected;
        longArguments['pass'] = longArguments['pass'] == true && matchesFixture;
        if (longArguments['pass'] != true) {
          throw StateError(
            'Long arguments viewer read/copy did not match the fixture text: '
            '$longArguments',
          );
        }
      }
      cases.add(<String, Object?>{
        'index': index,
        'itemId': toolItem.id,
        'callId': callId,
        'status': tool.status,
        'argumentBytes': tool.arguments.length,
        'resultPreviewBytes': tool.progressBytes,
        'expanded': expanded,
        'collapsed': collapsed,
        'inside': inside,
        'longResult': longResult,
        'longArguments': longArguments,
      });
      await File('${output.path}/case-$index-collapsed.png')
          .writeAsBytes(await driver.screenshot());
    }
    // Leave one tool open, visit a later tool, then return to the earlier tile
    // and expand it after its row has been recycled.
    stdout.writeln('tool_scroll_reverse');
    TimelineItemObservation toolFor(String callId) =>
        tools.singleWhere((item) => item.tool!.callId == callId);
    final earlierTile = find.byValueKey(
      'timeline-tool-details:${toolFor('scroll-call-medium').id}',
    );
    final laterTile = find.byValueKey(
      'timeline-tool-details:${toolFor('scroll-call-arguments').id}',
    );
    await place(earlierTile, 125);
    await probe(earlierTile, 'tap');
    await place(laterTile, 125);
    await probe(laterTile, 'tap');
    await place(earlierTile, 125);
    evidence['reverseExpansion'] = await probe(earlierTile, 'tap');
    await File('${output.path}/reverse-expanded.png')
        .writeAsBytes(await driver.screenshot());
    await place(earlierTile, 125);
    evidence['reverseCollapse'] = await probe(earlierTile, 'tap');
    final imageTool = imageItems.first.tool!;
    final imageId = '${imageTool.callId}:${imageTool.attachments.first.id}';
    final originalThread = (s['navigation'] as Map)['selectedThreadId'];
    final previousGeneration = loadedTimeline.generation;
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
      final timeline = TimelineObservation.optional(reopened);
      final scroll = TimelineScrollObservation.optional(reopened);
      if (reopened['navigation']['selectedThreadId'] == originalThread &&
          workspace?['syncState'] == 'ready' &&
          timeline != null &&
          timeline.ready &&
          !timeline.preparingLive &&
          timeline.generation != previousGeneration &&
          scroll != null &&
          scroll.laidOut &&
          !scroll.isScrolling) {
        evidence['reopenedView'] = {
          'previousGeneration': previousGeneration,
          'currentGeneration': timeline.generation,
          'mode': timeline.mode,
          'itemCount': timeline.itemCount,
          'atLiveEdge': scroll.atLiveEdge,
        };
        if (!scroll.atLiveEdge) {
          throw StateError('Reopened thread did not start at the live edge');
        }
        break;
      }
      if (DateTime.now().isAfter(reopenDeadline)) {
        throw StateError('Historical image window did not reopen');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await place(find.byValueKey('timeline-row-${imageItem.id}'), 120);
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
      find.byValueKey('timeline-row-${firstItems.first.id}'),
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

    bool headerStableAt(Object? probe) {
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
    Map<String, Object?> probeChecks(
      String label,
      Map<String, Object?> record,
    ) {
      final expanded = record['expanded'] as Map?;
      final collapsed = record['collapsed'] as Map?;
      final inside = record['inside'] as Map?;
      final expandedSamples = (expanded?['samples'] as List?) ?? const [];
      final collapsedSamples = (collapsed?['samples'] as List?) ?? const [];
      final headerStable =
          expandedSamples.isNotEmpty &&
          collapsedSamples.isNotEmpty &&
          headerStableAt(expanded) &&
          headerStableAt(collapsed);
      final expandedChanged =
          expandedSamples.length >= 2 && expansionChanged(expanded, true);
      final collapsedChanged =
          collapsedSamples.length >= 2 && expansionChanged(collapsed, false);
      // 展开后高度确实增长、收起后恢复：真实外层位置/尺寸证据。
      final grew =
          expandedSamples.length >= 2 &&
          ((expandedSamples.last as Map)['height'] as num) >
              ((expandedSamples.first as Map)['height'] as num) + 20;
      final shrank =
          collapsedSamples.length >= 2 &&
          ((collapsedSamples.last as Map)['height'] as num) <
              ((collapsedSamples.first as Map)['height'] as num) - 20;
      // 内层滚动只移动工具输出自身：外层 pixels 稳定，内层 pixels 前进且范围有效。
      Map<String, bool>? innerChecks;
      if (inside != null) {
        final samples = (inside['samples'] as List?) ?? const [];
        if (samples.length >= 2) {
          final before = samples.first as Map;
          final after = samples.last as Map;
          final outerStable =
              ((before['scroll']?['pixels'] as num?) != null &&
              (after['scroll']?['pixels'] as num?) != null &&
              (((before['scroll'] as Map)['pixels'] as num) -
                          ((after['scroll'] as Map)['pixels'] as num))
                      .abs() <
                  0.5);
          List<Map> vertical(Map sample) => [
            for (final nested in (sample['nested'] as List?) ?? const [])
              if (nested is Map &&
                  nested['axis'] == 'vertical' &&
                  (nested['max'] as num) > 0)
                nested,
          ];
          final beforeNested = vertical(before);
          final afterNested = vertical(after);
          final innerAdvanced =
              beforeNested.isNotEmpty &&
              afterNested.isNotEmpty &&
              ((afterNested.last['pixels'] as num) >
                  (beforeNested.last['pixels'] as num));
          innerChecks = <String, bool>{
            'outerStable': outerStable,
            'innerRange': beforeNested.isNotEmpty && afterNested.isNotEmpty,
            'innerAdvanced': innerAdvanced,
          };
        } else {
          innerChecks = <String, bool>{'samples': false};
        }
      }
      final record_ = <String, Object?>{
        'label': label,
        'headerStable': headerStable,
        'expandedChanged': expandedChanged,
        'collapsedChanged': collapsedChanged,
        'grew': grew,
        'shrank': shrank,
        'inner': ?innerChecks,
      };
      record_['pass'] =
          headerStable &&
          expandedChanged &&
          collapsedChanged &&
          grew &&
          shrank &&
          (innerChecks == null || innerChecks.values.every((value) => value));
      checks.add(record_['pass'] == true);
      return record_;
    }

    final caseChecks = <Object?>[];
    evidence['caseChecks'] = caseChecks;
    for (final c in cases.cast<Map<String, Object?>>()) {
      caseChecks.add(probeChecks('case-${c['index']}', c));
    }
    evidence['reverseChecks'] = <String, Object?>{
      'expansion': probeChecks('reverse-expansion', <String, Object?>{
        'expanded': evidence['reverseExpansion'],
        'collapsed': evidence['reverseCollapse'],
      }),
    };
    // 详情读取/复制的真实结果并入终局判定：残缺、晚到或复制错误都硬失败。
    final detailPasses = detailReads.cast<Map<String, Object?>>().every(
      (read) => read['pass'] == true,
    );
    checks.add(detailPasses);
    evidence['detailReadPasses'] = detailPasses;
    // 先取证，再算终局（latestViewportFill 的 pass 必须进入最终判定）。
    final fill = await observeLatestViewportFill(driver, output);
    evidence['latestViewportFill'] = fill;
    checks.add(fill['pass'] == true);
    evidence['checks'] = checks;

    // Remote resource-lifecycle 段只在真实 SSH 入口且已配置远端项目父目录
    // （`user@host` + `workspace-parent`，即 args>=5）时执行；执行条件本身未改。
    // 这里准确区分三种入口，不伪造本地 pass，也不把合法的本地/未配置远端当失败。
    final remoteResourceLifecycle = args.length >= 5;
    final lifecycleMode = args.length < 4
        ? 'local'
        : remoteResourceLifecycle
        ? 'remote-with-workspace-parent'
        : 'remote-without-workspace-parent';
    evidence['resourceLifecycle'] = <String, Object?>{
      'mode': lifecycleMode,
      'applicable': remoteResourceLifecycle,
      'ran': remoteResourceLifecycle,
      if (args.length < 4)
        'reason':
            'local run has no remote ssh session or owned remote processes, so the '
            'resource-lifecycle checks are not applicable and were not executed'
      else if (!remoteResourceLifecycle)
        'reason':
            'an ssh target was provided without --ssh-workspace-parent, so the '
            'remote resource-lifecycle scenario is not configured and was not '
            'executed (successful exit requires both)',
    };
    if (remoteResourceLifecycle) {
      final modes = <String>[];
      evidence['resourceLifecycleModes'] = modes;
      final id = (await snapshot())['workspace']['threadId'] as String;
      Future<void> selectIdleMode(String mode) async {
        await driver.sendCommand(
          RawTap(find.byValueKey('session-mode-selector')),
        );
        await driver.sendCommand(RawTap(find.byValueKey('session-mode-$mode')));
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (true) {
          final state = await snapshot();
          final mutations = (state['settings'] as Map)['mutations'] as List;
          final pending = mutations.where((item) => item['key'] == 'mode:$id');
          if (pending.any((item) => item['phase'] == 'failed')) {
            throw StateError('Mode command failed: ${pending.single['error']}');
          }
          if (state['workspace']?['threadMode'] == mode && pending.isEmpty) {
            if (state['workflow']?['currentRun'] != null) {
              throw StateError(
                'Selecting a mode started a workflow without input',
              );
            }
            break;
          }
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Mode refresh did not commit $mode');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        modes.add(mode);
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        for (final mode in ['mode.task', 'mode.simple']) {
          await selectIdleMode(mode);
        }
      }
      await selectIdleMode('mode.task');
      evidence['resourceLifecycleNoPrematureRun'] = true;
      await File('${output.path}/resource-lifecycle.png')
          .writeAsBytes(await driver.screenshot());
      await driver.sendCommand(RawTap(find.byValueKey('composer-input')));
      await driver.enterText('Resource lifecycle task');
      await driver.sendCommand(RawTap(find.byValueKey('composer-submit')));
      final taskState = await waitAnswer('Resource lifecycle task');
      final run = taskState['workflow']?['currentRun'] as Map?;
      if (run == null ||
          run['modeId'] != 'mode.task' ||
          run['currentStateId'] != 'planning' ||
          run['terminal'] != false) {
        throw StateError('Root input did not start the task workflow');
      }
      evidence['resourceLifecycleTaskRun'] = run;
      await File('${output.path}/resource-lifecycle-task.png')
          .writeAsBytes(await driver.screenshot());
      await driver.sendCommand(RawTap(find.byValueKey('thread-menu-$id')));
      await driver.sendCommand(
        RawTap(find.byValueKey('thread-menu-archive-$id')),
      );
      await driver.sendCommand(
        RawTap(find.byValueKey('thread-archive-confirm')),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while ((await snapshot())['workspace']?['threadId'] == id) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Thread close did not complete');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      evidence['resourceLifecycleArchived'] = true;
    }
    // 终局判定在全部证据之后计算：任何缺失 pass 都算失败。
    evidence['checksPassed'] = checks.every((value) => value);
    if (evidence['checksPassed'] != true) exitCode = 1;
  } finally {
    await File('${output.path}/tool-scroll.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    await driver.close();
  }
}
