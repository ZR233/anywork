// D1 纯库先行门禁样板的组件级回归（opt-in，不进入 verify/CI 门禁）。
//
// 全部用例都通过真实入口根（`buildGateRoot`：ProviderScope + MaterialApp + home）挂载，
// 用真实 PointerScrollEvent / 点击驱动；pump 只用于测试同步，不是产品等待帧的修复。
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import 'timeline_native_gate_app.dart';

Future<TimelineGateState> _pumpGate(
  WidgetTester tester, {
  GlobalKey<TimelineGateState>? key,
}) async {
  final gateKey = key ?? GlobalKey<TimelineGateState>();
  await tester.pumpWidget(buildGateRoot(key: gateKey));
  await tester.pump();
  final state = gateKey.currentState;
  expect(state, isNotNull, reason: '真实入口根必须挂载样板');
  return state!;
}

Rect _timelineRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey<String>('gate-timeline')));

Future<void> _wheel(WidgetTester tester, double dy) async {
  final center = tester.getCenter(
    find.byKey(const ValueKey<String>('gate-timeline')),
  );
  await _wheelAt(tester, center, dy);
}

Future<void> _wheelAt(WidgetTester tester, Offset position, double dy) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(position));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

String? _visibleRowId(WidgetTester tester, Iterable<String> candidates) {
  final viewport = _timelineRect(tester);
  for (final id in candidates) {
    final finder = find.byKey(ValueKey<String>('gate-row-$id'));
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder);
    if (rect.top >= viewport.top - 1 && rect.bottom <= viewport.bottom + 1) {
      return id;
    }
  }
  return null;
}

/// 只读库自己的分页 loading 投影（`LoadMoreNotifier.isLoadingOlder` →
/// `Visibility(visible: ...)`）；不读应用自己的标志。
bool _libraryLoadingOlder(WidgetTester tester) {
  final probe = find.byKey(
    const ValueKey<String>('gate-lib-load-more'),
    skipOffstage: false,
  );
  if (probe.evaluate().isEmpty) {
    throw StateError('library load-more sliver was not built');
  }
  final visibility = tester.widgetList<Visibility>(
    find.ancestor(
      of: probe,
      matching: find.byType(Visibility, skipOffstage: false),
    ),
  );
  expect(visibility, isNotEmpty, reason: '库用 Visibility 投影 loading');
  return visibility.first.visible;
}

void main() {
  testWidgets('真实入口根（ProviderScope+MaterialApp+home）可直接运行', (tester) async {
    final key = GlobalKey<TimelineGateState>();
    await tester.pumpWidget(buildGateRoot(key: key));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Chat), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('gate-timeline')), findsOneWidget);
    expect(key.currentState, isNotNull);
  });

  testWidgets('stock controller + 原生 reversed 列表构建，初始贴底', (tester) async {
    final state = await _pumpGate(tester);

    expect(find.byType(ChatAnimatedListReversed), findsOneWidget);
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scrollView.reverse, isTrue, reason: '使用库推荐的反向列表');
    expect(
      identical(scrollView.controller, state.currentGeneration.scroll),
      isTrue,
      reason: '应用提供的标准控制器就是库使用的控制器',
    );
    expect(scrollView.controller!.keepScrollOffset, isFalse);

    final snapshot = state.snapshot();
    expect(snapshot['generation'], 1);
    expect(snapshot['mode'], 'live');
    expect(snapshot['messageCount'], 32, reason: '首屏只构造最新一页');
    expect(snapshot['offset'], closeTo(0, .5));
    expect(snapshot['scrollAttached'], isTrue);
  });

  testWidgets('older 前插后真实行 top 不突变，也不写 pixels', (tester) async {
    final state = await _pumpGate(tester);

    await _wheel(tester, -60);
    final afterWheel = state.snapshot();
    expect(
      afterWheel['mode'],
      'history',
      reason:
          'offset=${afterWheel['offset']} '
          'max=${afterWheel['maxScrollExtent']} '
          'vp=${afterWheel['viewportDimension']}',
    );
    final offsetBefore = afterWheel['offset'] as double;
    expect(offsetBefore, greaterThan(0));

    final rowId = _visibleRowId(tester, <String>[
      for (var item = gateHistoryLength - 32; item < gateHistoryLength; item++)
        gateItemId(item),
    ]);
    expect(rowId, isNotNull, reason: '上翻后必须能定位一条真实可见行');
    final finder = find.byKey(ValueKey<String>('gate-row-$rowId'));
    final topBefore = tester.getTopLeft(finder).dy;

    await state.loadOlder();
    await tester.pump();
    await tester.pump();

    expect(state.snapshot()['messageCount'], 64);
    expect(
      tester.getTopLeft(finder).dy,
      closeTo(topBefore, .5),
      reason: '视觉末端前插不得移动读者看到的行',
    );
    expect(
      state.snapshot()['offset'],
      closeTo(offsetBefore, .5),
      reason: '应用不写 pixels，位移应完全由结构决定',
    );
  });

  testWidgets('Live 长正文增长后仍停在新端底部', (tester) async {
    final state = await _pumpGate(tester);
    final maxBefore = state.snapshot()['maxScrollExtent'] as double;

    state.streamUpdate(chars: 900);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('增量片段'), findsOneWidget);
    expect(state.snapshot()['offset'], closeTo(0, .5));
    expect(
      state.snapshot()['maxScrollExtent'] as double,
      greaterThan(maxBefore),
      reason: '正文确实变高',
    );
    final viewport = _timelineRect(tester);
    final bottom = tester
        .getBottomRight(
          find.byKey(
            ValueKey<String>('gate-row-${gateItemId(gateHistoryLength - 1)}'),
          ),
        )
        .dy;
    expect(
      bottom,
      inInclusiveRange(viewport.bottom - 24, viewport.bottom + 0.5),
      reason: '最新行仍贴住视口底部（无需任何像素校正）',
    );
  });

  testWidgets('真实上翻进入 History 后冻结展示，后台变化只更新提示', (tester) async {
    final state = await _pumpGate(tester);

    await _wheel(tester, -60);
    final snapshotBefore = state.snapshot();
    expect(snapshotBefore['mode'], 'history');
    final idsBefore = (snapshotBefore['messageIds'] as List).cast<String>();
    final displayedBefore = state.displayedText(idsBefore.last);
    final offsetBefore = snapshotBefore['offset'] as double;
    final revisionBefore = snapshotBefore['displayRevision'] as int;

    state.streamUpdate(chars: 300);
    state.streamAppend();
    await tester.pump();
    await tester.pump();

    final snapshotAfter = state.snapshot();
    expect((snapshotAfter['messageIds'] as List).cast<String>(), idsBefore);
    expect(state.displayedText(idsBefore.last), displayedBefore);
    expect(snapshotAfter['offset'], closeTo(offsetBefore, .5));
    expect(snapshotAfter['displayRevision'], revisionBefore);
    expect(
      snapshotAfter['latestRevision'] as int,
      greaterThan(revisionBefore),
      reason: '后台状态仍前进',
    );
    expect(snapshotAfter['pendingNewOutput'], 2);
    expect(
      find.byKey(const ValueKey<String>('gate-row-live-append-0001')),
      findsNothing,
      reason: 'History 不接收新的流式消息',
    );
    expect(find.byKey(const ValueKey<String>('gate-pending')), findsOneWidget);
  });

  testWidgets('改窗不切换 History', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _pumpGate(tester);
    expect(state.snapshot()['mode'], 'live');

    tester.view.physicalSize = const Size(900, 1100);
    await tester.pump();
    await tester.pump();

    expect(state.snapshot()['mode'], 'live', reason: 'resize 不是用户阅读意图');
    expect(state.snapshot()['offset'], closeTo(0, .5));
  });

  testWidgets('用户滚动意图是短生命周期：回实时后的非用户更新不切 History', (tester) async {
    final state = await _pumpGate(tester);

    await _wheel(tester, -60);
    expect(state.snapshot()['mode'], 'history');

    state.returnLive();
    await tester.pump();
    await tester.pump();
    expect(state.snapshot()['mode'], 'live');

    // 模拟惰性几何/改窗造成的像素修正：不是用户输入。
    state.currentGeneration.scroll.jumpTo(40);
    await tester.pump();
    await tester.pump();

    expect(state.snapshot()['mode'], 'live', reason: '没有用户意图的像素变化不得进入 History');
  });

  testWidgets('History 前插更早消息不抬高冻结水位、不改既有正文', (tester) async {
    final state = await _pumpGate(tester);
    await _wheel(tester, -60);

    final before = state.snapshot();
    expect(before['mode'], 'history');
    final idsBefore = (before['messageIds'] as List).cast<String>();
    final bodiesBefore = <String, String?>{
      for (final id in idsBefore) id: state.displayedText(id),
    };
    final revisionBefore = before['displayRevision'] as int;

    state.streamUpdate(chars: 200);
    state.streamAppend();
    await tester.pump();
    await state.loadOlder();
    await tester.pump();
    await tester.pump();

    final after = state.snapshot();
    final idsAfter = (after['messageIds'] as List).cast<String>();
    expect(after['messageCount'], idsBefore.length + 32);
    expect(
      idsAfter.sublist(idsAfter.length - idsBefore.length),
      idsBefore,
      reason: '既有身份与顺序不变，只在前面新增 older 前缀',
    );
    expect(
      idsAfter.sublist(0, 32),
      isNot(contains(idsBefore.first)),
      reason: '新增的只能是更早的一页',
    );
    for (final id in idsBefore) {
      expect(state.displayedText(id), bodiesBefore[id]);
    }
    expect(
      after['displayRevision'],
      revisionBefore,
      reason: '历史前插不改变已展示内容的版本水位',
    );
    expect(after['pendingNewOutput'], 2);
  });

  testWidgets('回到实时后新代次展示后台最新内容（tail 基线生效）', (tester) async {
    final state = await _pumpGate(tester);
    await _wheel(tester, -60);
    final generationBefore = state.snapshot()['generation'] as int;

    state.streamUpdate(chars: 300);
    state.streamAppend();
    await tester.pump();
    expect(
      (state.snapshot()['tailIds'] as List).cast<String>().last,
      'live-append-0001',
      reason: 'History 期间有界 tail 基线确实前进',
    );

    state.returnLive();
    await tester.pump();
    await tester.pump();

    final snapshot = state.snapshot();
    expect(snapshot['generation'], generationBefore + 1);
    expect(snapshot['mode'], 'live');
    expect(snapshot['offset'], closeTo(0, .5));
    expect(snapshot['messageCount'], gateTailLimit);
    expect(
      (snapshot['messageIds'] as List).cast<String>().last,
      'live-append-0001',
    );
    expect(state.displayedText('live-append-0001'), contains('实时新增 1'));
    expect(
      state.displayedText(gateItemId(gateHistoryLength - 1)),
      contains('增量片段'),
    );
    expect(snapshot['displayRevision'], snapshot['latestRevision']);
    expect(snapshot['pendingNewOutput'], 0);

    // 再回实时一次：基线仍然是最新内容，不回退到初始合成快照。
    state.returnLive();
    await tester.pump();
    await tester.pump();
    expect(
      (state.snapshot()['messageIds'] as List).cast<String>().last,
      'live-append-0001',
    );
    expect(
      state.displayedText(gateItemId(gateHistoryLength - 1)),
      contains('增量片段'),
    );
  });

  testWidgets('显式回到实时建立新代次，并从公开 stream 观察旧控制器收束', (tester) async {
    final state = await _pumpGate(tester);
    await _wheel(tester, -60);
    expect(state.snapshot()['mode'], 'history');

    final previous = state.currentGeneration;
    // 广播流 close() 的 done 会等所有监听解除；用 Completer 观察 onDone，
    // 不手动 cancel（cancel 一个已 close 且仍有监听的广播订阅不会完成）。
    final controllerDone = Completer<void>();
    previous.controller.operationsStream.listen(
      (_) {},
      onDone: controllerDone.complete,
    );

    state.returnLive();
    await tester.pump();
    await tester.pump();

    final snapshot = state.snapshot();
    expect(snapshot['generation'], 2);
    expect(snapshot['mode'], 'live');
    expect(snapshot['messageCount'], 32);
    expect(snapshot['offset'], closeTo(0, .5));
    expect(snapshot['lastDisposeRequestedGeneration'], 1);
    expect(snapshot['disposeRequested'], isTrue);
    expect(
      controllerDone.isCompleted,
      isTrue,
      reason: '旧 controller 的公开 operationsStream 必须真正 done',
    );
    expect(previous.scroll.hasClients, isFalse, reason: '旧滚动控制器已脱离');
    expect(
      () => previous.scroll.addListener(() {}),
      throwsFlutterError,
      reason: '已 dispose 的 ScrollController 按 SDK 断言拒绝使用',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('不足一屏时显式加载更早，并在 EOF 收起入口', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _pumpGate(tester);

    state.resetShort();
    await tester.pump();
    await tester.pump();
    expect(state.snapshot()['shortContent'], isTrue);
    expect(state.snapshot()['messageCount'], 5);
    expect(
      find.byKey(const ValueKey<String>('gate-load-older')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('gate-load-older')));
    await tester.pump();
    await tester.pump();

    expect(state.snapshot()['messageCount'], 25);
    expect(state.snapshot()['hasOlder'], isFalse);
    expect(state.snapshot()['loading'], isFalse);
    expect(
      _libraryLoadingOlder(tester),
      isFalse,
      reason: 'EOF 后库自身的 loading 必须收束',
    );
    expect(
      find.byKey(const ValueKey<String>('gate-load-older')),
      findsNothing,
      reason: 'EOF 后不再显示加载入口',
    );
  });

  testWidgets('分页失败保留内容并可重试，库 loading 始终收束', (tester) async {
    final state = await _pumpGate(tester);

    state.failNextLoad();
    await state.loadOlder();
    await tester.pump();
    await tester.pump();

    expect(state.snapshot()['error'], isNotNull);
    expect(state.snapshot()['loading'], isFalse);
    expect(state.snapshot()['messageCount'], 32);
    expect(state.snapshot()['pageRequests'], 1);
    expect(find.byKey(const ValueKey<String>('gate-error')), findsOneWidget);
    expect(
      _libraryLoadingOlder(tester),
      isFalse,
      reason: '失败后库 loading 不能永久为真',
    );

    await tester.tap(find.byKey(const ValueKey<String>('gate-load-older')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(state.snapshot()['pageRequests'], 2);
    expect(state.snapshot()['error'], isNull);
    expect(state.snapshot()['messageCount'], 64);
    expect(_libraryLoadingOlder(tester), isFalse);
  });

  testWidgets('非预期异常被上报且可重试，不伪装 EOF', (tester) async {
    final state = await _pumpGate(tester);
    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    state.failNextLoad(unexpected: true);
    await state.loadOlder();
    await tester.pump();
    await tester.pump();

    expect(reported, isNotEmpty, reason: '程式错误必须上报，不能静默吞掉');
    expect(state.snapshot()['error'], isNotNull);
    expect(state.snapshot()['hasOlder'], isTrue, reason: '失败不等于 EOF');
    expect(state.snapshot()['messageCount'], 32);
    expect(_libraryLoadingOlder(tester), isFalse);
  });

  testWidgets('卸载会唤醒在途分页，不留无 owner 的 future', (tester) async {
    final key = GlobalKey<TimelineGateState>();
    final state = await _pumpGate(tester, key: key);

    state.armNextLoad();
    final pending = state.loadOlder();
    await tester.pump();
    expect(state.snapshot()['loading'], isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await pending;
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('回到实时后仍持有的在途分页，也必须在卸载时收束', (tester) async {
    final key = GlobalKey<TimelineGateState>();
    final state = await _pumpGate(tester, key: key);

    state.armNextLoad();
    final pending = state.loadOlder();
    await tester.pump();

    state.returnLive();
    await tester.pump();
    await tester.pump();
    expect(
      state.snapshot()['pendingGates'] as int,
      greaterThanOrEqualTo(1),
      reason: '旧代次的在途页仍被显式持有（由 Driver/测试释放或卸载唤醒）',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await pending;
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('迟到分页不能污染新的展示代次', (tester) async {
    final state = await _pumpGate(tester);

    state.armNextLoad();
    final pending = state.loadOlder();
    await tester.pump();
    expect(state.snapshot()['loading'], isTrue);

    state.returnLive();
    await tester.pump();
    await tester.pump();
    final generation = state.snapshot()['generation'] as int;

    state.releasePendingLoad();
    await pending;
    await tester.pump();
    await tester.pump();

    final snapshot = state.snapshot();
    expect(snapshot['generation'], generation);
    expect(snapshot['messageCount'], 32);
    expect(
      (snapshot['messageIds'] as List).cast<String>(),
      isNot(contains(gateItemId(gateHistoryLength - 64))),
      reason: '旧代次的页结果不得写入新代次',
    );
    expect(snapshot['stalePagesDropped'] as int, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('只读几何诊断与真实 Row/RenderBox 双向一致', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _pumpGate(tester);
    final viewportRect = _timelineRect(tester);
    expect(viewportRect.left, greaterThan(0), reason: '宽窗下阅读列居中，原点非 0');

    final initial = state.geometry();
    expect(initial['ok'], isTrue);
    expect(initial['frame'], 'viewport');
    final viewport = initial['viewport'] as Map<String, Object?>;
    expect(viewport['left'], 0.0);
    expect(viewport['top'], 0.0);
    expect(viewport['width'] as double, closeTo(viewportRect.width, .5));
    expect(viewport['height'] as double, closeTo(viewportRect.height, .5));
    final global = initial['viewportGlobal'] as Map<String, Object?>;
    expect(global['left'] as double, closeTo(viewportRect.left, .5));
    expect(global['top'] as double, closeTo(viewportRect.top, .5));
    expect(global['width'] as double, closeTo(viewportRect.width, .5));
    expect(global['height'] as double, closeTo(viewportRect.height, .5));

    Set<String> canonicalVisible() {
      final ids = <String>{};
      for (final id
          in (state.snapshot()['messageIds'] as List).cast<String>()) {
        final finder = find.byKey(ValueKey<String>('gate-row-$id'));
        if (finder.evaluate().isEmpty) continue;
        if (tester.getRect(finder).overlaps(viewportRect)) ids.add(id);
      }
      return ids;
    }

    for (final offset in <double>[400, 520, 1300]) {
      state.currentGeneration.scroll.jumpTo(offset);
      await tester.pump();
      await tester.pump();

      final geometry = state.geometry();
      final rows = (geometry['rows'] as List).cast<Map<String, Object?>>();
      final geometryIds = <String>{for (final row in rows) row['id'] as String};
      expect(
        geometryIds,
        canonicalVisible(),
        reason: 'offset=$offset 时几何诊断与真实可见集合必须双向相等',
      );
      for (final row in rows) {
        expect(row['intersects'], isTrue);
        expect(row['painted'], isTrue);
        final rect = row['rect'] as Map<String, Object?>;
        final expected = tester.getRect(
          find.byKey(ValueKey<String>('gate-row-${row['id']}')),
        );
        expect(
          rect['left'] as double,
          closeTo(expected.left - viewportRect.left, .5),
        );
        expect(
          rect['top'] as double,
          closeTo(expected.top - viewportRect.top, .5),
        );
        expect(rect['width'] as double, closeTo(expected.width, .5));
        expect(rect['height'] as double, closeTo(expected.height, .5));
      }
    }

    // requested 终态语义：可见行给出 mounted/painted/intersects/rect；
    // 本库/本 fixture 下视口外的行不会保持挂载（cacheExtent 未产生挂载外行，
    // 实测 built 集合等于可见集合），所以它们的准确终态是「无 Element」→ missing，
    // 而不是伪造 mounted:false。
    final geometry = state.geometry();
    final visibleRows = (geometry['rows'] as List).cast<Map<String, Object?>>();
    final visibleId = visibleRows.first['id'] as String;
    String? unbuiltId;
    for (final id in (state.snapshot()['messageIds'] as List).cast<String>()) {
      if (find.byKey(ValueKey<String>('gate-row-$id')).evaluate().isEmpty) {
        unbuiltId = id;
        break;
      }
    }
    expect(unbuiltId, isNotNull, reason: '应有未挂载的历史行（32 条里只有少数被构建）');

    final requested = state.geometry(
      rowIds: <String>[visibleId, unbuiltId!, 'item-00000'],
    );
    final byId = <String, Map<String, Object?>>{
      for (final row
          in (requested['rows'] as List).cast<Map<String, Object?>>())
        row['id'] as String: row,
    };
    expect(byId[visibleId]!['mounted'], isTrue);
    expect(byId[visibleId]!['painted'], isTrue);
    expect(byId[visibleId]!['intersects'], isTrue);
    expect(byId[visibleId]!['rect'], isNotNull);
    expect(byId.containsKey(unbuiltId), isFalse);
    expect(byId.containsKey('item-00000'), isFalse);
    expect((requested['missing'] as List).cast<String>().toSet(), <String>{
      unbuiltId,
      'item-00000',
    }, reason: '只有没有对应 Element 的 id 才进入 missing');

    final limited = state.geometry(
      rowIds: List<String>.filled(gateGeometryRowLimit + 1, 'item-00000'),
    );
    expect(limited['ok'], isFalse);
    expect(limited['error'], 'tooManyRowIds');
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实 wheel 触发库 onEndReached：握手期间库 loading 为真，放行后收束', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _pumpGate(tester);
    final position = state.currentGeneration.scroll.position;

    // 成功路径：真实轮滚建立方向与阅读位置，改窗产生 metrics 变化触发库分页。
    state.armNextLoad();
    position.jumpTo(position.maxScrollExtent * 0.85);
    await tester.pump();
    await _wheel(tester, -60);
    tester.view.physicalSize = const Size(1180, 900);
    await tester.pump();
    await tester.pump();

    expect(
      _libraryLoadingOlder(tester),
      isTrue,
      reason: '库自己把 onEndReached 挂在在途页上',
    );
    final offsetBefore = state.snapshot()['offset'] as double;
    state.releasePendingLoad();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(_libraryLoadingOlder(tester), isFalse);
    expect(state.snapshot()['error'], isNull);
    expect(state.snapshot()['messageCount'], 64);
    expect(
      state.snapshot()['offset'],
      closeTo(offsetBefore, .5),
      reason: '历史前插不写 pixels',
    );

    // 失败路径：同样由真实轮滚触发，失败后库 loading 必须收束且内容不变。
    state.failNextLoad();
    state.armNextLoad();
    position.jumpTo(position.maxScrollExtent * 0.9);
    await tester.pump();
    await _wheel(tester, -60);
    tester.view.physicalSize = const Size(1160, 900);
    await tester.pump();
    await tester.pump();

    expect(_libraryLoadingOlder(tester), isTrue);
    final countBefore = state.snapshot()['messageCount'] as int;
    state.releasePendingLoad();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(_libraryLoadingOlder(tester), isFalse);
    expect(state.snapshot()['error'], isNotNull);
    expect(state.snapshot()['messageCount'], countBefore);
    expect(find.byKey(const ValueKey<String>('gate-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空会话不崩溃', (tester) async {
    final state = await _pumpGate(tester);

    state.makeEmpty();
    await tester.pump();
    await tester.pump();

    expect(state.snapshot()['messageCount'], 0);
    expect(state.snapshot()['tailCount'], 0);
    expect(state.snapshot()['hasOlder'], isFalse);
    expect(find.byKey(const ValueKey<String>('gate-status')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具行内层滚动优先，不带动外层列表', (tester) async {
    final state = await _pumpGate(tester);

    String? toolId;
    for (var tick = 0; tick < 12 && toolId == null; tick++) {
      await _wheel(tester, -120);
      for (final id
          in (state.snapshot()['messageIds'] as List).cast<String>()) {
        final tool = find.byKey(ValueKey<String>('gate-tool-$id'));
        if (tool.evaluate().isEmpty) continue;
        final rect = tester.getRect(tool);
        final viewport = _timelineRect(tester);
        if (rect.top >= viewport.top && rect.bottom <= viewport.bottom) {
          toolId = id;
          break;
        }
      }
    }
    expect(toolId, isNotNull, reason: '滚动后应出现紧凑工具摘要行');

    final toolFinder = find.byKey(ValueKey<String>('gate-tool-$toolId'));
    final innerScrollable = find.descendant(
      of: find.byKey(ValueKey<String>('gate-tool-scroll-$toolId')),
      matching: find.byType(Scrollable),
    );
    final innerBefore = tester
        .state<ScrollableState>(innerScrollable)
        .position
        .pixels;
    final outerBefore = state.snapshot()['offset'] as double;

    await _wheelAt(tester, tester.getCenter(toolFinder), 120);

    expect(
      tester.state<ScrollableState>(innerScrollable).position.pixels,
      greaterThan(innerBefore),
      reason: '内层滚动区优先消费滚轮',
    );
    expect(
      state.snapshot()['offset'],
      closeTo(outerBefore, .5),
      reason: '外层列表不被内层滚动带动',
    );
  });
  _registerLifecycleCloseTests();
}

/// 记录 native 退出协议调用及其发生时的 fixture 收束状态（mock 只记录，不替代收束）。
class _LifecycleRecorder {
  _LifecycleRecorder(this.state);

  final TimelineGateState state;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  Future<Object?> handle(MethodCall call) async {
    final snapshot = state.snapshot();
    calls.add(<String, Object?>{
      'method': call.method,
      'arguments': call.arguments,
      'closed': state.closed,
      'treeDisposed': snapshot['treeDisposed'] as bool,
      'allStreamsDone': snapshot['allStreamsDone'] as bool,
    });
    if (call.method == 'beginExit') return 30000;
    return null;
  }
}

void _registerLifecycleCloseTests() {
  testWidgets('shutdown 走 owned close 后由 native finishExit(0) 结束', (
    tester,
  ) async {
    final key = GlobalKey<TimelineGateState>();
    final state = await _pumpGate(tester, key: key);
    final recorder = _LifecycleRecorder(state);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      GateHostLifecycle.channel,
      recorder.handle,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(GateHostLifecycle.channel, null),
    );

    state.armNextLoad();
    final pending = state.loadOlder();
    await tester.pump();
    expect(state.snapshot()['loading'], isTrue);
    final idsBefore = (state.snapshot()['messageIds'] as List).cast<String>();

    final exitCode = await runGateShutdown(
      state: state,
      unmount: () => tester.pumpWidget(const SizedBox.shrink()),
    );
    await pending;

    expect(exitCode, 0);
    expect(recorder.calls.map((call) => call['method']).toList(), <String>[
      'beginExit',
      'finishExit',
    ], reason: '先武装 native 期限，收束完成后才 finishExit');
    final finish = recorder.calls.last;
    expect(finish['arguments'], <String, Object?>{'exitCode': 0});
    expect(finish['closed'], isTrue, reason: 'finish 必须在 owned close 之后');
    expect(finish['treeDisposed'], isTrue, reason: 'finish 必须在子树卸载之后');
    expect(
      finish['allStreamsDone'],
      isTrue,
      reason: 'finish 必须在所有代次 controller 流真正 done 之后',
    );

    expect(state.closed, isTrue);
    expect(state.mounted, isFalse);
    expect(state.snapshot()['treeDisposed'], isTrue);
    expect(state.snapshot()['allStreamsDone'], isTrue);
    expect(
      state.snapshot()['stalePagesDropped'],
      greaterThanOrEqualTo(1),
      reason: '关闭时在途页被丢弃，而不是写入展示集合',
    );
    expect(tester.takeException(), isNull);

    // 关闭后迟到的放行与注入都不能复活任何内容或抛异常。
    state.releasePendingLoad();
    state.streamUpdate();
    state.streamAppend();
    await tester.pump();
    expect(
      state.currentGeneration.controller.messages
          .map((message) => message.id)
          .toList(),
      idsBefore,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('收束失败上报并 finishExit(1)，不伪报成功', (tester) async {
    final key = GlobalKey<TimelineGateState>();
    final state = await _pumpGate(tester, key: key);
    final recorder = _LifecycleRecorder(state);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      GateHostLifecycle.channel,
      recorder.handle,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(GateHostLifecycle.channel, null),
    );
    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    final exitCode = await runGateShutdown(
      state: state,
      unmount: () async {
        throw StateError('synthetic unmount failure');
      },
    );

    expect(exitCode, 1);
    expect(recorder.calls.map((call) => call['method']).toList(), <String>[
      'beginExit',
      'finishExit',
    ]);
    expect(recorder.calls.last['arguments'], <String, Object?>{'exitCode': 1});
    expect(reported, isNotEmpty, reason: '失败必须上报，不能静默');
    expect(state.closed, isTrue);

    // 收尾测试树（真实卸载），避免残留。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
