import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_driver/flutter_driver.dart';

import 'driver_read_commands.dart';
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

/// 图片行真实回收所需的最大外层滚轮步数（每步 0.8 个视口）。
///
/// 只用于有界收敛：步数用尽仍未从 render/widget 树卸载就如实失败，不靠固定 sleep。
const _maxImageRecycleSteps = 12;

/// 剧本里的 8 个工具调用身份（`pl-provider-fixture` 的 `gui_tool_scroll_script`）。
///
/// 每个 canonical 工具调用都是独立条目：按 callId 精确判定 name/status，既不放过
/// 漏项，也不接受陌生项；判定不依赖时间线顺序或任何活动分组。
const _expectedToolCalls = <({String callId, String name, String status})>[
  (callId: 'scroll-call-short', name: 'list_files', status: 'succeeded'),
  (callId: 'scroll-call-medium', name: 'list_files', status: 'succeeded'),
  (callId: 'scroll-call-long', name: 'list_files', status: 'succeeded'),
  (callId: 'scroll-call-arguments', name: 'exec', status: 'succeeded'),
  (callId: 'scroll-call-a', name: 'view_image', status: 'succeeded'),
  (callId: 'scroll-call-b', name: 'view_image', status: 'succeeded'),
  (callId: 'scroll-call-c', name: 'view_image', status: 'succeeded'),
  (callId: 'scroll-call-failed', name: 'list_files', status: 'failed'),
];

/// 连续三次图片读取共用一条展示摘要，仍按 a/b/c 的原始调用身份验收。
const _imageCallIds = <String>[
  'scroll-call-a',
  'scroll-call-b',
  'scroll-call-c',
];

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
  for (final group in timeline.presentationItems) {
    if (key == 'timeline-row-${group.id}' ||
        key == 'timeline-activity-summary-${group.id}') {
      return group.ordinal;
    }
  }
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

int? _ordinalOfItemId(TimelineObservation timeline, String id) =>
    timeline.ordinalOfIdentity(id);

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

  Future<TimelinePresentationObservation> presentationFor(String id) async =>
      TimelineObservation.parse(await snapshot()).presentationFor(id);

  SerializableFinder headerOf(SerializableFinder summary) => find.ancestor(
    of: summary,
    matching: find.byType('ListTile'),
    firstMatchOnly: true,
  );

  Future<void> revealItem(String id) async {
    final group = await presentationFor(id);
    await place(find.byValueKey('timeline-row-${group.id}'), 100);
    if (group.kind != 'single' && !group.expanded) {
      await driver.sendCommand(
        RawTap(
          headerOf(find.byValueKey('timeline-activity-summary-${group.id}')),
        ),
      );
    }
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
    // 每个 canonical 工具调用都是独立消息，不再合并成活动组：按 fixture 的精确
    // callId/name/status 集合判定无漏、无重、无陌生项，不依赖时间线顺序。
    final toolItems = loadedTimeline.items
        .where((item) => item.kind == 'toolCall' && item.tool != null)
        .toList();
    final toolsByCallId = <String, TimelineItemObservation>{};
    final duplicateCallIds = <String>[];
    for (final item in toolItems) {
      final callId = item.tool!.callId;
      if (toolsByCallId.containsKey(callId)) duplicateCallIds.add(callId);
      toolsByCallId[callId] = item;
    }
    final missingCallIds = <String>[
      for (final expected in _expectedToolCalls)
        if (!toolsByCallId.containsKey(expected.callId)) expected.callId,
    ];
    final unexpectedCallIds = <String>[
      for (final callId in toolsByCallId.keys)
        if (!_expectedToolCalls.any((expected) => expected.callId == callId))
          callId,
    ];
    final mismatchedCallIds = <String>[
      for (final expected in _expectedToolCalls)
        if (toolsByCallId[expected.callId]?.tool?.name != expected.name ||
            toolsByCallId[expected.callId]?.tool?.status != expected.status)
          expected.callId,
    ];
    if (toolItems.length != _expectedToolCalls.length ||
        duplicateCallIds.isNotEmpty ||
        missingCallIds.isNotEmpty ||
        unexpectedCallIds.isNotEmpty ||
        mismatchedCallIds.isNotEmpty) {
      throw StateError(
        'Tool calls do not match the fixture identities: '
        'count=${toolItems.length} (expected ${_expectedToolCalls.length}), '
        'duplicates=$duplicateCallIds, missing=$missingCallIds, '
        'unexpected=$unexpectedCallIds, '
        'nameOrStatusMismatch=$mismatchedCallIds',
      );
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
    // 连续图片调用仍各有原始身份，不按展示行数量推断调用数量。
    final imageItems = <TimelineItemObservation>[
      for (final callId in _imageCallIds) toolsByCallId[callId]!,
    ];
    final imageCallIds = <String>[
      for (final item in toolItems)
        if (item.tool!.name == 'view_image') item.tool!.callId,
    ];
    if (imageCallIds.length != _imageCallIds.length ||
        !_imageCallIds.every(imageCallIds.contains)) {
      throw StateError(
        'Expected exactly the fixture image reads $_imageCallIds, got '
        '$imageCallIds',
      );
    }
    final imageEntries = <String>[];
    for (final item in imageItems) {
      final tool = item.tool!;
      final attachments = tool.attachments;
      if (tool.name != 'view_image' ||
          tool.status != 'succeeded' ||
          attachments.length != 1) {
        throw StateError(
          'view_image ${tool.callId} did not archive exactly one image: '
          'name=${tool.name} status=${tool.status} '
          'attachments=${attachments.length}',
        );
      }
      imageEntries.add('${tool.callId}:${attachments.single.id}');
    }
    final imageItem = imageItems.first;
    final imageEntryFirst = imageEntries.first;
    // 连续读取统一展开，同时保留每次调用的图片身份。
    final imageEntryOther = imageEntries.last;
    final imageGroup = await presentationFor(imageItem.id);
    if (imageGroup.kind != 'images' ||
        !imageItems.every((item) => imageGroup.memberIds.contains(item.id))) {
      throw StateError(
        'Consecutive image calls did not form one GUI group: ${imageGroup.memberIds}',
      );
    }
    final summary = find.byValueKey('timeline-row-${imageGroup.id}');
    await place(summary, 120);
    await File('${output.path}/consecutive-images-collapsed.png')
        .writeAsBytes(await driver.screenshot());
    await place(summary, 120);
    final toggle = find.byValueKey(
      'timeline-activity-summary-${imageGroup.id}',
    );
    final thumbnail = find.byValueKey('view-image-thumbnail-$imageEntryFirst');
    await driver.sendCommand(RawTap(headerOf(toggle)));
    await driver.waitFor(thumbnail, timeout: const Duration(seconds: 10));
    await File('${output.path}/consecutive-images-expanded.png')
        .writeAsBytes(await driver.screenshot());
    await driver.sendCommand(RawTap(thumbnail));
    await driver.waitFor(find.byValueKey('view-image-dialog-$imageEntryFirst'));
    await File('${output.path}/agent-read-image-dialog.png')
        .writeAsBytes(await driver.screenshot());
    await driver.sendCommand(RawTap(find.byValueKey('timeline-image-close')));
    if ((await probe(
          find.byValueKey('view-image-thumbnail-$imageEntryOther'),
          'observe',
        ))['samples'].last['mounted'] !=
        true) {
      throw StateError('Consecutive image calls did not expand together');
    }
    // 同一 Thread、同一展示代次的真实用户滚动回收：正常外层滚轮把 b 行连同缩略图
    // 滚出 render/widget 树（History 冻结，不建立新代次），再用既有 place 滚回同一
    // ID。展开状态属于同一 lease，必须保留；不允许用显式「回到实时」换 gen，也不
    // 允许重建/重新 toggle。
    bool mountedOf(Map<String, dynamic> result) =>
        (result['samples'] as List).last['mounted'] != false;
    Map<String, Object?> recycleFacts(
      Map<String, dynamic> state,
      TimelineScrollObservation scroll,
    ) {
      final observed = TimelineObservation.parse(state);
      return <String, Object?>{
        'threadId': observed.threadId,
        'generation': observed.generation,
        'mode': observed.mode,
        'pixels': scroll.pixels,
        'extentBefore': scroll.extentBefore,
        'extentAfter': scroll.extentAfter,
        'atLiveEdge': scroll.atLiveEdge,
      };
    }

    // 等标准 controller 自己发布空闲几何（`isScrolling` 来自生产），不按固定帧猜。
    Future<Map<String, dynamic>> settledRecycle(String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      Map<String, dynamic>? last;
      while (DateTime.now().isBefore(deadline)) {
        last = await snapshot();
        final scroll = TimelineScrollObservation.optional(last);
        if (scroll != null && scroll.laidOut && !scroll.isScrolling) {
          return last;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError(
        'Timeline geometry did not settle after $label: '
        '${last == null ? 'no snapshot' : TimelineScrollObservation.optional(last)?.toJson()}',
      );
    }

    final recycleBefore = await settledRecycle('image recycle before');
    final beforeTimeline = TimelineObservation.parse(recycleBefore);
    final beforeScroll = TimelineScrollObservation.parse(recycleBefore);
    final beforeItem = beforeTimeline.item(imageItem.id);
    final rowMountedBefore = mountedOf(await probe(summary, 'observe'));
    final thumbMountedBefore = mountedOf(await probe(thumbnail, 'observe'));
    if (!rowMountedBefore || !thumbMountedBefore) {
      throw StateError(
        'Image row was not mounted and expanded before recycling '
        '(row=$rowMountedBefore, thumbnail=$thumbMountedBefore)',
      );
    }
    // 真实外层 wheel 离开该行：方向与 place 的同一标准写法一致（向更早内容为负 dy）。
    final recycleSteps = <Map<String, Object?>>[];
    var away = false;
    var awayState = recycleBefore;
    for (var step = 1; step <= _maxImageRecycleSteps; step += 1) {
      final view = (await probe(timeline, 'observe'))['samples'].last as Map;
      final stepDy = -((view['height'] as num).toDouble()) * 0.8;
      await probe(timeline, 'wheelOutside', dy: stepDy);
      final state = await settledRecycle('image recycle step $step');
      final scroll = TimelineScrollObservation.parse(state);
      final rowMounted = mountedOf(await probe(summary, 'observe'));
      final thumbMounted = mountedOf(await probe(thumbnail, 'observe'));
      recycleSteps.add(<String, Object?>{
        'step': step,
        'dy': stepDy,
        ...recycleFacts(state, scroll),
        'rowMounted': rowMounted,
        'thumbnailMounted': thumbMounted,
      });
      awayState = state;
      if (!rowMounted && !thumbMounted) {
        away = true;
        break;
      }
    }
    final awayTimeline = TimelineObservation.parse(awayState);
    final awayScroll = TimelineScrollObservation.parse(awayState);
    final sameThread = awayTimeline.threadId == beforeTimeline.threadId;
    final sameGeneration = awayTimeline.generation == beforeTimeline.generation;
    if (!away || !sameThread || !sameGeneration || !awayTimeline.isHistory) {
      throw StateError(
        'The image row never left the render tree inside the same lease: '
        'away=$away sameThread=$sameThread sameGeneration=$sameGeneration '
        'mode=${awayTimeline.mode} steps=$recycleSteps',
      );
    }
    // 离开阶段的事实先独立落盘：即使回程断言失败也留下真实 gen/mode/mounted 与步数。
    // 写失败直接传播（不吞、不 rethrow）。
    await File('${output.path}/agent-read-image-recycle-away.json')
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'itemId': imageItem.id,
            'imageEntry': imageEntryFirst,
            'before': <String, Object?>{
              ...recycleFacts(recycleBefore, beforeScroll),
              'rowMounted': rowMountedBefore,
              'thumbnailMounted': thumbMountedBefore,
            },
            'steps': recycleSteps,
            'stepCount': recycleSteps.length,
            'away': <String, Object?>{
              ...recycleFacts(awayState, awayScroll),
              'rowMounted': false,
              'thumbnailMounted': false,
            },
            'sameThread': sameThread,
            'sameGeneration': sameGeneration,
            'stayedHistory': awayTimeline.isHistory,
          }),
        );
    // 再用既有 place（同 ID）正常滚回，不 toggle：缩略图必须自动仍在。
    await place(summary, 120);
    await driver.waitFor(thumbnail, timeout: const Duration(seconds: 15));
    final returnedState = await settledRecycle('image recycle return');
    final returnedTimeline = TimelineObservation.parse(returnedState);
    final returnedScroll = TimelineScrollObservation.parse(returnedState);
    final returnedItem = returnedTimeline.item(imageItem.id);
    final rowMountedReturned = mountedOf(await probe(summary, 'observe'));
    final thumbMountedReturned = mountedOf(await probe(thumbnail, 'observe'));
    final otherThumbMounted = mountedOf(
      await probe(
        find.byValueKey('view-image-thumbnail-$imageEntryOther'),
        'observe',
      ),
    );
    final returnedSameThread =
        returnedTimeline.threadId == beforeTimeline.threadId;
    final returnedSameGeneration =
        returnedTimeline.generation == beforeTimeline.generation;
    if (!rowMountedReturned ||
        !thumbMountedReturned ||
        !otherThumbMounted ||
        !returnedSameThread ||
        !returnedSameGeneration ||
        !returnedTimeline.isHistory ||
        returnedItem == null ||
        returnedItem.tool?.status != beforeItem?.tool?.status) {
      throw StateError(
        'Recycled image row did not come back expanded in the same lease: '
        'row=$rowMountedReturned thumbnail=$thumbMountedReturned '
        'otherThumbnail=$otherThumbMounted '
        'sameThread=$returnedSameThread '
        'sameGeneration=$returnedSameGeneration '
        'mode=${returnedTimeline.mode} '
        'toolStatus=${returnedItem?.tool?.status} '
        'beforeToolStatus=${beforeItem?.tool?.status} '
        'away=${recycleFacts(awayState, awayScroll)} '
        'steps=${recycleSteps.length}',
      );
    }
    await File('${output.path}/agent-read-image-recycled.png')
        .writeAsBytes(await driver.screenshot());
    // 同一组的真实 collapse 必须同时隐藏所有连续读取的缩略图。
    await driver.sendCommand(RawTap(headerOf(toggle)));
    await driver.waitForAbsent(thumbnail, timeout: const Duration(seconds: 10));
    final collapsed = !mountedOf(await probe(thumbnail, 'observe'));
    final otherStillCollapsed = !mountedOf(
      await probe(
        find.byValueKey('view-image-thumbnail-$imageEntryOther'),
        'observe',
      ),
    );
    if (!collapsed || !otherStillCollapsed) {
      throw StateError(
        'Image collapse did not settle after recycling '
        '(collapsed=$collapsed otherStillCollapsed=$otherStillCollapsed)',
      );
    }
    // 承重回收证据：写失败直接传播（不吞、不需要额外 rethrow）。
    final recycleEvidence = <String, Object?>{
      'itemId': imageItem.id,
      'imageEntry': imageEntryFirst,
      'otherImageEntry': imageEntryOther,
      'input': 'outer wheel (ToolProbe wheelOutside) away, existing place back',
      'before': <String, Object?>{
        ...recycleFacts(recycleBefore, beforeScroll),
        'rowMounted': rowMountedBefore,
        'thumbnailMounted': thumbMountedBefore,
        'toolStatus': beforeItem?.tool?.status,
      },
      'steps': recycleSteps,
      'stepCount': recycleSteps.length,
      'away': <String, Object?>{
        ...recycleFacts(awayState, awayScroll),
        'rowMounted': false,
        'thumbnailMounted': false,
      },
      'returned': <String, Object?>{
        ...recycleFacts(returnedState, returnedScroll),
        'rowMounted': rowMountedReturned,
        'thumbnailMounted': thumbMountedReturned,
        'otherImageThumbnailMounted': otherThumbMounted,
        'toolStatus': returnedItem.tool?.status,
      },
      'sameThread': sameThread && returnedSameThread,
      'sameGeneration': sameGeneration && returnedSameGeneration,
      'stayedHistory': awayTimeline.isHistory && returnedTimeline.isHistory,
      'survivedRowRecycling': away && thumbMountedReturned,
      'collapsed': collapsed,
      'otherImageStillCollapsed': otherStillCollapsed,
    };
    await File('${output.path}/agent-read-image-recycle.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(recycleEvidence),
    );
    evidence['agentReadImage'] = <String, Object?>{
      'distinctCalls': imageEntries.length,
      'dialogOpened': true,
      'survivedRowRecycling': recycleEvidence['survivedRowRecycling'],
      'collapsed': collapsed,
      'recycle': recycleEvidence,
    };
    await place(summary, 120);
    // 详情逐块读取：只有用户显式打开查看器才读取完整字段，关闭后停止。
    Future<Map<String, Object?>> readDetail(
      String itemId,
      String field, {
      required int expectedBytes,
    }) async {
      final openKey = 'timeline-detail-open-$itemId-$field';
      // loaded ≠ mounted：前面的展开/收起与内外滚动会改变几何，标准惰性列表不会因为
      // `waitFor` 自己把下方行挂载出来。先用同一套真实外层滚轮把该 canonical item 的
      // 详情入口带进挂载/可见区（`place` 走 ToolProbe wheelOutside，无像素写），再等待
      // 并点击。两个 caller（long result / arguments）共用这一条路径，不做特判。
      layoutWaits.add(<String, Object?>{
        'reason': 'locateDetailOpen',
        'itemId': itemId,
        'field': field,
        'key': openKey,
        'expectedBytes': expectedBytes,
      });
      final openFinder = find.byValueKey(openKey);
      await place(openFinder, 120);
      await driver.waitFor(openFinder, timeout: const Duration(seconds: 20));
      await driver.sendCommand(RawTap(openFinder));
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      DetailViewerRead? progress;
      var sawPartial = false;
      var viewerOpened = false;
      while (DateTime.now().isBefore(deadline)) {
        progress = await DetailViewerRead.read(driver.requestData);
        if (progress.open) viewerOpened = true;
        final characters = progress.characters;
        if (characters > 0 && characters < expectedBytes) sawPartial = true;
        if (characters >= expectedBytes) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await driver.sendCommand(RawTap(find.byValueKey('timeline-detail-copy')));
      // 完整剪贴板原文：用来与 fixture 推出的期望原文/结构比较，而不是自证 hash。
      final clipboard = await ClipboardRead.read(
        driver.requestData,
        full: true,
      );
      await driver.sendCommand(
        RawTap(find.byValueKey('timeline-detail-close')),
      );
      final closeDeadline = DateTime.now().add(const Duration(seconds: 15));
      var closed = false;
      while (DateTime.now().isBefore(closeDeadline)) {
        final state = await DetailViewerRead.read(driver.requestData);
        if (!state.open) {
          closed = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final loadedCharacters = progress?.characters ?? 0;
      final loadedHash = progress?.hash;
      // 完整字节 + 查看器/剪贴板一致 + 已关闭即可证明保真；`sawPartialChunk`
      // 只记录（快速多块读取允许在一次轮询前完成，产品不需要为观测放慢）。
      final pass =
          viewerOpened &&
          loadedCharacters == expectedBytes &&
          clipboard.characters == expectedBytes &&
          loadedHash != null &&
          clipboard.hash == loadedHash &&
          closed;
      return <String, Object?>{
        'field': field,
        'expectedBytes': expectedBytes,
        // 理论块数（ceil(bytes/64KiB)），不是实际读了多少块。
        'theoreticalChunks': (expectedBytes / (64 * 1024)).ceil(),
        'loadedCharacters': loadedCharacters,
        'loadedHash': loadedHash,
        'sawPartialChunk': sawPartial,
        'viewerOpened': viewerOpened,
        'clipboardCharacters': clipboard.characters,
        'clipboardHash': clipboard.hash,
        'clipboardText': clipboard.text,
        'closed': closed,
        'pass': pass,
      };
    }

    final cases = <Object?>[];
    evidence['cases'] = cases;
    final detailReads = <Object?>[];
    evidence['detailReads'] = detailReads;
    for (var index = 0; index < _expectedToolCalls.length; index++) {
      final expected = _expectedToolCalls[index];
      stdout.writeln('tool_scroll_case=$index:${expected.callId}');
      // 用 canonical callId 定位条目；index 只用于证据文件命名与稳定输出。
      final toolItem = toolsByCallId[expected.callId]!;
      final tool = toolItem.tool!;
      final callId = tool.callId;
      if (callId != expected.callId ||
          tool.name != expected.name ||
          tool.status != expected.status) {
        throw StateError(
          'Unexpected tool identity in case $index: '
          '${tool.name}/${tool.status} for $callId',
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
      await revealItem(toolItem.id);
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
      // 收起前必须把真实 header 重新带回可点区域：展开后标题可能已被原生反向布局
      // 推到视口上方，点屏外坐标不是一次真实收起。
      await place(tile, 125);
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
    TimelineItemObservation toolFor(String callId) => toolsByCallId[callId]!;
    final earlierTile = find.byValueKey(
      'timeline-tool-details:${toolFor('scroll-call-medium').id}',
    );
    final laterTile = find.byValueKey(
      'timeline-tool-details:${toolFor('scroll-call-arguments').id}',
    );
    // 逆序复测必须从真实的 collapsed 准备态开始：先读公开 `expanded` flag；若它仍
    // 展开，先用一次真实点击收起，再进入“离开→返回→重新展开→收起”的序列。
    await place(earlierTile, 125);
    final earlierPrepared = await probe(earlierTile, 'observe');
    final earlierExpandedBefore =
        (earlierPrepared['samples'] as List).last['expanded'] == true;
    if (earlierExpandedBefore) {
      await place(earlierTile, 125);
      final prepared = await probe(earlierTile, 'tap');
      if ((prepared['samples'] as List).last['expanded'] != false) {
        throw StateError(
          'reverse expansion: the preparing collapse did not settle',
        );
      }
    }
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
    final reopenedGroup = await presentationFor(imageItem.id);
    await place(find.byValueKey('timeline-row-${reopenedGroup.id}'), 120);
    await driver.sendCommand(
      RawTap(
        headerOf(
          find.byValueKey('timeline-activity-summary-${reopenedGroup.id}'),
        ),
      ),
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

    double? finite(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : null;

    /// 原生反向列表的逐 sample 精确 range-clamp 不变量（design/24 工具段）。
    ///
    /// 每个 sample 都必须：min/max 为真实有限数值且 `min <= max`、Thread/gen 与
    /// 初样本一致、`mode == history`；实际 pixels 精确等于「初 pixels 对**本次
    /// sample 自己** min/max 的 clamp」（±0.5）；row 最新侧 bottom（`top+height`）
    /// 的变化精确等于 pixels 的变化（±0.5）。stock clamp 会同步移动行边缘，预览的
    /// 展开/收起本身不写入 pixels；不额外 jump/animate。
    ///
    /// 初样本本身必须合法且有限；不用 `extentAfter ≈` 代替 min/max；所有 sample 都
    /// 参与判定。返回逐 tap 事实（含 clamp 发生样本数与真实 min/max/pixel/edge 变化），
    /// 由调用方强消费 `pass`，不让一个 bool 吞掉细节。
    Map<String, Object?> nativeReverseGeometry(Object? probe) {
      final samples = probe is Map && probe['samples'] is List
          ? probe['samples'] as List
          : const <Object?>[];
      final evidence = <String, Object?>{
        'sampleCount': samples.length,
        'pass': false,
        'rangeClampSamples': 0,
        'clampedSamples': <Map<String, Object?>>[],
        'failures': <Map<String, Object?>>[],
      };
      if (samples.length < 2) return evidence;
      final first = samples.first as Map;
      final firstScroll = first['scroll'];
      if (firstScroll is! Map) return evidence;
      final threadId = firstScroll['threadId'];
      final generation = firstScroll['generation'];
      final initialPixel = finite(firstScroll['pixels']);
      final initialMin = finite(firstScroll['minScrollExtent']);
      final initialMax = finite(firstScroll['maxScrollExtent']);
      final initialTop = finite(first['top']);
      final initialHeight = finite(first['height']);
      if (threadId is! String ||
          generation is! int ||
          initialPixel == null ||
          initialMin == null ||
          initialMax == null ||
          initialTop == null ||
          initialHeight == null ||
          initialMin > initialMax) {
        return evidence;
      }
      final initialEdge = initialTop + initialHeight;
      final clampedSamples = <Map<String, Object?>>[];
      final failures = <Map<String, Object?>>[];
      for (final sample in samples) {
        final current = sample as Map;
        final scroll = current['scroll'];
        final top = finite(current['top']);
        final height = finite(current['height']);
        final pixels = scroll is Map ? finite(scroll['pixels']) : null;
        final min = scroll is Map ? finite(scroll['minScrollExtent']) : null;
        final max = scroll is Map ? finite(scroll['maxScrollExtent']) : null;
        Map<String, Object?>? failure;
        Map<String, Object?>? clamped;
        if (scroll is! Map ||
            current['mode'] != 'history' ||
            scroll['threadId'] != threadId ||
            scroll['generation'] != generation ||
            min == null ||
            max == null ||
            min > max ||
            pixels == null ||
            top == null ||
            height == null) {
          failure = <String, Object?>{
            'valid': false,
            'mode': current['mode'],
            'pixels': pixels,
            'min': min,
            'max': max,
            'top': top,
            'height': height,
          };
        } else {
          final expectedPixel = initialPixel.clamp(min, max);
          final edge = top + height;
          final pixelOk = (pixels - expectedPixel).abs() <= 0.5;
          final edgeOk =
              ((edge - initialEdge) - (pixels - initialPixel)).abs() <= 0.5;
          final rangeClamped = (expectedPixel - initialPixel).abs() > 0.5;
          final fact = <String, Object?>{
            'pixels': pixels,
            'min': min,
            'max': max,
            'expectedPixels': expectedPixel,
            'edge': edge,
            'edgeDelta': edge - initialEdge,
            'pixelDelta': pixels - initialPixel,
            'rangeClamped': rangeClamped,
          };
          if (!pixelOk || !edgeOk) {
            failure = <String, Object?>{
              'valid': true,
              'pixelOk': pixelOk,
              'edgeOk': edgeOk,
              ...fact,
            };
          } else if (rangeClamped) {
            clamped = fact;
          }
        }
        if (failure != null) failures.add(failure);
        if (clamped != null) clampedSamples.add(clamped);
      }
      evidence['pass'] = failures.isEmpty;
      evidence['rangeClampSamples'] = clampedSamples.length;
      evidence['clampedSamples'] = clampedSamples;
      evidence['failures'] = failures;
      evidence['initial'] = <String, Object?>{
        'pixels': initialPixel,
        'min': initialMin,
        'max': initialMax,
        'edge': initialEdge,
      };
      return evidence;
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
      final expandedChanged =
          expandedSamples.length >= 2 && expansionChanged(expanded, true);
      final collapsedChanged =
          collapsedSamples.length >= 2 && expansionChanged(collapsed, false);
      final expandedGeometry = nativeReverseGeometry(expanded);
      final collapsedGeometry = nativeReverseGeometry(collapsed);
      final nativeGeometry =
          expandedGeometry['pass'] == true && collapsedGeometry['pass'] == true;
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
        'nativeReverseGeometry': nativeGeometry,
        'geometryEvidence': <String, Object?>{
          'expanded': expandedGeometry,
          'collapsed': collapsedGeometry,
        },
        'expandedChanged': expandedChanged,
        'collapsedChanged': collapsedChanged,
        'grew': grew,
        'shrank': shrank,
        'inner': ?innerChecks,
      };
      record_['pass'] =
          nativeGeometry &&
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
