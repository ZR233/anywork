// D1 纯库先行门禁样板（opt-in，仅用于组件路线证明；不是生产 Timeline）。
//
// 唯一列表路线：公开 `Chat` + 原生 `ChatAnimatedListReversed` + stock
// `InMemoryChatController`，外加一个只用于 Scrollbar/被动观察/诊断的标准
// `ScrollController(keepScrollOffset: false)`。这里没有任何像素恢复、observer、
// 每行 GlobalKey、锚点、pin、帧末预取或 edge-wheel；应用从不写 pixels。
//
// 数据是确定性合成长历史（20000 个互不相同的 canonical id），首屏只构造最新 32 条
// Message；older 页按游标合成 32 条并 `insertAllMessages(index: 0, animated: false)`，
// 不裁对端、不做整表 diff。另有一个**有界最新 tail 基线**（≤32 条不可变 Message，
// 模拟同 Session 的 tail 订阅）：History 只更新它与提示，显式回实时用它建立新代次。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// 合成长历史的条目总数（身份确定，不代表内存里存在这么多 Message）。
const int gateHistoryLength = 20000;

/// 每页条目数（与 design/26 的默认页大小一致）。
const int gatePageSize = 32;

/// 有界最新 tail 的条数上限。
const int gateTailLimit = 32;

/// 单次几何诊断最多查询的行数。
const int gateGeometryRowLimit = 64;

/// 复用现有 native 退出协议；独立布局门禁不装配 AppGraph/FRB。
///
/// - `beginExit`：武装 native 硬期限并返回剩余毫秒（重复调用不刷新）。
/// - `finishExit`：以真实退出码结束本实例；native 只接受 0/1。
/// 原生 runner 的 `main()` 在消息循环自然返回时会判为「未确认退出」并返回非 0，
/// 因此本样板在收束完成后必须走 `finishExit`，不能依赖自然退出。
abstract final class GateHostLifecycle {
  static const MethodChannel channel = MethodChannel(
    'io.github.zr233.anywork/host_lifecycle',
  );

  static Future<int> beginExit() async {
    try {
      final remaining = await channel.invokeMethod<int>('beginExit');
      return remaining ?? 30000;
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'timeline_native_gate',
          context: ErrorDescription('while arming the native exit deadline'),
        ),
      );
      return 30000;
    }
  }

  static Future<void> finishExit({required int exitCode}) async {
    try {
      await channel.invokeMethod<void>('finishExit', <String, Object?>{
        'exitCode': exitCode,
      });
    } on Object catch (error, stackTrace) {
      // native 通常会在此调用中直接终止进程；能走到这里说明通道缺失或异常，
      // 只能如实上报（native 硬期限会以非 0 兜底），不伪装成成功退出。
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'timeline_native_gate',
          context: ErrorDescription('while requesting native finishExit'),
        ),
      );
    }
  }
}

/// 展示模式。Live 跟随最新端；History 冻结已展示内容，只允许向前插更早消息。
enum GateMode { live, history }

/// typed 分页失败（样板展示错误与重试，不把异常抛给库）。
class GateLoadFailure implements Exception {
  const GateLoadFailure(this.message);

  final String message;

  @override
  String toString() => 'GateLoadFailure: $message';
}

/// 一行在样板中的渲染类型，用来覆盖短文本、Markdown、长正文与紧凑工具摘要。
enum GateRowKind { text, markdown, longText, tool }

GateRowKind _kindFor(int index) {
  if (index % 11 == 0) return GateRowKind.longText;
  if (index % 7 == 3) return GateRowKind.tool;
  if (index % 5 == 0) return GateRowKind.markdown;
  return GateRowKind.text;
}

String gateItemId(int index) => 'item-${index.toString().padLeft(5, '0')}';

String _textFor(int index, GateRowKind kind) {
  final id = gateItemId(index);
  switch (kind) {
    case GateRowKind.markdown:
      return '### $id\n\n- 合成长历史条目 $index\n- `stable identity`\n\n'
          '正文用于验证 Markdown 行高与滚动。';
    case GateRowKind.tool:
      return '工具摘要 $id：读取 12 个文件，输出已折叠。';
    case GateRowKind.longText:
      return List.filled(
        6,
        '$id 第 ${index % 13} 段长正文，用于撑出行高并验证 Live 增长。',
      ).join('\n\n');
    case GateRowKind.text:
      return '$id 的简短正文（$index）。';
  }
}

Message _messageFor(int index) {
  final kind = _kindFor(index);
  final now = DateTime.utc(2026, 1, 1);
  return Message.text(
    id: gateItemId(index),
    authorId: index.isEven ? 'user' : 'assistant',
    text: _textFor(index, kind),
    createdAt: now,
    updatedAt: now,
    metadata: <String, dynamic>{'kind': kind.name, 'index': index},
  );
}

/// 门禁样板的真实入口根形状：ProviderScope + MaterialApp + home。
///
/// main 与组件测试共用这一个构造，避免「测试自己包了一层 MaterialApp 而入口缺根」。
Widget buildGateRoot({required GlobalKey<TimelineGateState> key}) =>
    ProviderScope(child: buildGateRootBody(key: key));

/// 根形状的内层（MaterialApp + home）；`buildGateRoot` 与 Driver 入口共用。
Widget buildGateRootBody({required GlobalKey<TimelineGateState> key}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: TimelineGateApp(key: key),
  );
}

/// 一代展示：新的 Chat key、新的消息控制器、新的滚动控制器。
class GateGeneration {
  GateGeneration({required this.index, required List<Message> messages})
    : controller = InMemoryChatController(messages: messages),
      scroll = ScrollController(keepScrollOffset: false);

  final int index;
  final InMemoryChatController controller;
  final ScrollController scroll;
  int pageRequests = 0;
  int stalePagesDropped = 0;
  bool disposed = false;
  final Completer<void> _streamDone = Completer<void>();

  bool get streamDone => _streamDone.isCompleted;

  /// 公开 controller 流真正 done 的收束 ACK。
  Future<void> get whenStreamDone => _streamDone.future;

  void dispose() {
    if (disposed) return;
    disposed = true;
    // 先挂一个 done 观察者再关闭流：广播流的 done 是最直接、可被 await 的释放 ACK。
    controller.operationsStream.listen(
      (_) {},
      onDone: () {
        if (!_streamDone.isCompleted) _streamDone.complete();
      },
    );
    controller.dispose();
    scroll.dispose();
  }
}

class TimelineGateApp extends StatefulWidget {
  const TimelineGateApp({super.key});

  @override
  State<TimelineGateApp> createState() => TimelineGateState();
}

class TimelineGateState extends State<TimelineGateApp> {
  /// 有界最新 tail 基线（≤[gateTailLimit] 条不可变 Message），模拟同 Session 的
  /// 有界最新内容；History 期间只更新它，不写展示集合。
  final List<Message> _tail = <Message>[];

  /// 展示集合中最早一条历史条目的历史下标（用于 older 游标）。
  int _tailStart = gateHistoryLength - gatePageSize;

  late GateGeneration _generation;
  GateMode _mode = GateMode.live;
  int _olderCursor = gateHistoryLength - gatePageSize;
  bool _hasOlder = true;
  bool _loadingOlder = false;
  String? _error;
  Future<void>? _inFlight;
  final List<Completer<void>> _pendingGates = <Completer<void>>[];
  bool _armNextLoad = false;
  bool _failNextLoad = false;
  bool _failNextUnexpected = false;
  int _latestRevision = 0;
  int _displayRevision = 0;
  int _pendingNewOutput = 0;
  int _appended = 0;
  int _updated = 0;
  int _stalePagesDropped = 0;
  int _lastDisposeRequestedGeneration = 0;
  bool _disposeRequested = false;
  bool _shortContent = false;
  bool _userScrollIntent = false;
  bool _closed = false;
  Future<bool>? _closeScopeFuture;
  final Set<Future<void>> _pages = <Future<void>>{};
  final List<GateGeneration> _retired = <GateGeneration>[];
  final Completer<void> _treeDisposed = Completer<void>();

  GateGeneration get currentGeneration => _generation;
  GateMode get mode => _mode;
  bool get hasOlder => _hasOlder;
  bool get loadingOlder => _loadingOlder;
  String? get loadError => _error;
  bool get shortContent => _shortContent;
  bool get closed => _closed;

  /// fixture 子树真正卸载（`State.dispose`）的 ACK。
  Future<void> get treeDisposed => _treeDisposed.future;
  List<Message> get tailBaseline => List<Message>.unmodifiable(_tail);

  @override
  void initState() {
    super.initState();
    _tail.addAll(_initialTail());
    _generation = _buildGeneration(1);
  }

  List<Message> _initialTail() => <Message>[
    for (
      var item = gateHistoryLength - gatePageSize;
      item < gateHistoryLength;
      item++
    )
      _messageFor(item),
  ];

  GateGeneration _buildGeneration(int index) {
    _displayRevision = _latestRevision;
    return GateGeneration(index: index, messages: List<Message>.of(_tail));
  }

  @override
  void dispose() {
    // 未完成的查询不能留下无 owner 的 future：先唤醒本 scope 的所有 gate，
    // 在途请求会在代次/挂载检查处被丢弃，不会在 dispose 后 setState。
    _closed = true;
    _releaseAllGates();
    final generations = <GateGeneration>[..._retired, _generation];
    for (final generation in generations) {
      generation.dispose();
    }
    unawaited(_completeTreeDisposed(generations));
    super.dispose();
  }

  /// 子树卸载 + 所有代次 controller 流真正 done 之后才完成 [treeDisposed] 的 ACK。
  Future<void> _completeTreeDisposed(List<GateGeneration> generations) async {
    await Future.wait<void>([
      for (final generation in generations) generation.whenStreamDone,
    ]);
    if (!_treeDisposed.isCompleted) _treeDisposed.complete();
  }

  // --- 观察：只有真实用户滚动才切换 History --------------------------------

  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.depth != 0) return false;
    // 方向通知先于像素变化到达：这里只登记「这次是用户滚动」，并随 end/idle 立刻失效。
    _userScrollIntent = notification.direction != ScrollDirection.idle;
    return false;
  }

  bool _onScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.depth != 0) return false;
    if (!_userScrollIntent && notification.dragDetails == null) {
      // 惰性几何/改窗引起的像素修正没有用户意图，不是阅读意图。
      return false;
    }
    if (_mode == GateMode.live &&
        _generation.scroll.hasClients &&
        _generation.scroll.position.pixels > 0.5) {
      setState(() => _mode = GateMode.history);
    }
    return false;
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0) return false;
    _userScrollIntent = false;
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    final short = notification.metrics.maxScrollExtent <= 0;
    if (short != _shortContent && mounted) {
      setState(() => _shortContent = short);
    }
    return false;
  }

  // --- 分页（同一 future 合并并发；失败在样板边界收束，不抛给库） ----------

  Future<void> loadOlder() {
    if (_closed) return Future<void>.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (!_hasOlder) return Future<void>.value();
    final future = _runOlderPage();
    _inFlight = future;
    _pages.add(future);
    unawaited(
      future.whenComplete(() {
        _pages.remove(future);
        if (identical(_inFlight, future)) _inFlight = null;
      }),
    );
    return future;
  }

  /// 关闭本 fixture 自己拥有的 scope：停止发布、唤醒并等待所有在途查询，
  /// 关闭当前与已退役代次的 stock controller 流；返回是否干净收束。
  ///
  /// 滚动子树的实际卸载由调用方 unmount 完成，并以 [treeDisposed] 作为 ACK。
  Future<bool> closeScope() {
    final existing = _closeScopeFuture;
    if (existing != null) return existing;
    final future = _closeScope();
    _closeScopeFuture = future;
    return future;
  }

  Future<bool> _closeScope() async {
    _closed = true;
    _releaseAllGates();
    final pages = List<Future<void>>.of(_pages);
    var clean = true;
    if (pages.isNotEmpty) {
      try {
        await Future.wait<void>(pages, eagerError: false);
      } on Object catch (error, stackTrace) {
        clean = false;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'timeline_native_gate',
            context: ErrorDescription('while closing in-flight gate pages'),
          ),
        );
      }
    }
    clean = clean && _pages.isEmpty;
    // 已卸载的旧代次可以立即释放；当前代次由卸载触发 dispose 释放。
    for (final generation in _retired) {
      generation.dispose();
    }
    return clean;
  }

  /// 当前与已退役代次的 controller 流是否全部真正 done。
  bool get allGenerationStreamsDone =>
      <GateGeneration>[..._retired, _generation].every((g) => g.streamDone);

  List<GateGeneration> get retiredGenerations =>
      List<GateGeneration>.unmodifiable(_retired);

  Future<void> _runOlderPage() async {
    final generation = _generation;
    final cursor = _olderCursor;
    Completer<void>? gate;
    if (_armNextLoad) {
      _armNextLoad = false;
      gate = Completer<void>();
      _pendingGates.add(gate);
    }
    setState(() {
      _loadingOlder = true;
      _error = null;
    });
    generation.pageRequests += 1;
    try {
      if (gate != null) await gate.future;
      if (_failNextUnexpected) {
        _failNextUnexpected = false;
        throw StateError('synthetic programming error while loading a page');
      }
      if (_failNextLoad) {
        _failNextLoad = false;
        throw const GateLoadFailure('synthetic page failure');
      }
      final start = math.max(0, cursor - gatePageSize);
      final page = <Message>[
        for (var item = start; item < cursor; item++) _messageFor(item),
      ];
      if (!_isCurrent(generation)) {
        _dropStale(generation);
        return;
      }
      if (page.isNotEmpty) {
        await generation.controller.insertAllMessages(
          page,
          index: 0,
          animated: false,
        );
      }
      if (!_isCurrent(generation)) {
        _dropStale(generation);
        return;
      }
      setState(() {
        // 历史前插不改变已展示内容的版本水位；冻结仍以 displayRevision 为准。
        _olderCursor = start;
        _hasOlder = start > 0;
      });
    } on GateLoadFailure catch (failure) {
      if (!_isCurrent(generation)) {
        _dropStale(generation);
        return;
      }
      setState(() => _error = failure.message);
    } catch (error, stack) {
      // 非预期错误不被静默吞掉：上报给框架，同时让样板显示可重试错误。
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'timeline_native_gate',
          context: ErrorDescription('while loading an older page'),
        ),
      );
      if (!_isCurrent(generation)) {
        _dropStale(generation);
        return;
      }
      setState(() => _error = '分页异常：$error');
    } finally {
      if (mounted &&
          !_closed &&
          generation == _generation &&
          !generation.disposed) {
        setState(() => _loadingOlder = false);
      }
      _pendingGates.remove(gate);
    }
  }

  bool _isCurrent(GateGeneration generation) =>
      mounted && !_closed && generation == _generation && !generation.disposed;

  void _dropStale(GateGeneration generation) {
    generation.stalePagesDropped += 1;
    _stalePagesDropped += 1;
  }

  /// 让下一次分页等待 Driver 的 `release-load`（验证持续轮滚与在途查询交叠）。
  void armNextLoad() {
    if (_closed) return;
    _armNextLoad = true;
  }

  bool releasePendingLoad() {
    final armed = _armNextLoad || _pendingGates.isNotEmpty;
    _armNextLoad = false;
    _releaseAllGates();
    return armed;
  }

  void _releaseAllGates() {
    final pending = List<Completer<void>>.of(_pendingGates);
    _pendingGates.clear();
    for (final gate in pending) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  void failNextLoad({bool unexpected = false}) {
    if (_closed) return;
    _failNextLoad = !unexpected;
    _failNextUnexpected = unexpected;
  }

  // --- Live 注入（History 下只更新有界 tail 与提示，不写展示 ops） ----------

  void streamUpdate({int chars = 240}) {
    if (_closed) return;
    _updated += 1;
    _latestRevision += 1;
    if (_tail.isNotEmpty) {
      final latest = _tail.last;
      final text = latest is TextMessage
          ? '${latest.text}\n\n增量片段 $_updated：${'正文' * (chars ~/ 2)}'
          : '增量片段 $_updated';
      final updated = Message.text(
        id: latest.id,
        authorId: latest.authorId,
        text: text,
        createdAt: latest.createdAt,
        updatedAt: DateTime.utc(2026, 1, 1, 0, 0, _updated % 60),
        metadata: latest.metadata,
      );
      _tail[_tail.length - 1] = updated;
      if (_mode == GateMode.live) {
        unawaited(_generation.controller.updateMessage(latest, updated));
      }
    }
    _afterLiveMutation();
  }

  void streamAppend({int chars = 120}) {
    if (_closed) return;
    _appended += 1;
    _latestRevision += 1;
    final now = DateTime.utc(2026, 1, 1, 0, 1, _appended % 60);
    final message = Message.text(
      id: 'live-append-${_appended.toString().padLeft(4, '0')}',
      authorId: 'assistant',
      text: '实时新增 $_appended：${'输出' * (chars ~/ 2)}',
      createdAt: now,
      updatedAt: now,
      metadata: const <String, dynamic>{'kind': 'text'},
    );
    _tail.add(message);
    while (_tail.length > gateTailLimit) {
      final dropped = _tail.removeAt(0);
      if (dropped.id.startsWith('item-')) _tailStart += 1;
    }
    if (_mode == GateMode.live) {
      unawaited(_generation.controller.insertMessage(message));
    }
    _afterLiveMutation();
  }

  void _afterLiveMutation() {
    setState(() {
      if (_mode == GateMode.live) {
        _displayRevision = _latestRevision;
        _pendingNewOutput = 0;
      } else {
        _pendingNewOutput += 1;
      }
    });
  }

  // --- 显式回到实时：从有界 tail 基线建立新代次 ----------------------------

  void returnLive() {
    if (_closed) return;
    final previous = _generation;
    setState(() {
      _mode = GateMode.live;
      _pendingNewOutput = 0;
      _loadingOlder = false;
      _error = null;
      _inFlight = null;
      _userScrollIntent = false;
      _armNextLoad = false;
      _olderCursor = _tailStart;
      _hasOlder = _tailStart > 0;
      _shortContent = false;
      _generation = _buildGeneration(previous.index + 1);
    });
    _disposeAfterUnmount(previous);
  }

  void resetShort({int count = 5, int olderAvailable = 20}) {
    if (_closed) return;
    final previous = _generation;
    setState(() {
      _mode = GateMode.live;
      _pendingNewOutput = 0;
      _loadingOlder = false;
      _error = null;
      _inFlight = null;
      _userScrollIntent = false;
      _tail
        ..clear()
        ..addAll(<Message>[
          for (var item = olderAvailable; item < olderAvailable + count; item++)
            _messageFor(item),
        ]);
      _tailStart = olderAvailable;
      _olderCursor = olderAvailable;
      _hasOlder = olderAvailable > 0;
      _shortContent = false;
      _generation = _buildGeneration(previous.index + 1);
    });
    _disposeAfterUnmount(previous);
  }

  void makeEmpty() {
    if (_closed) return;
    final previous = _generation;
    setState(() {
      _mode = GateMode.live;
      _pendingNewOutput = 0;
      _loadingOlder = false;
      _error = null;
      _inFlight = null;
      _userScrollIntent = false;
      _tail.clear();
      _tailStart = 0;
      _olderCursor = 0;
      _hasOlder = false;
      _shortContent = true;
      _generation = _buildGeneration(previous.index + 1);
    });
    _disposeAfterUnmount(previous);
  }

  void _disposeAfterUnmount(GateGeneration previous) {
    _retired.add(previous);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous.dispose();
      if (!mounted) return;
      setState(() {
        _lastDisposeRequestedGeneration = previous.index;
        // 只表示「已请求释放」，实际收束由测试从公开 stream done / 控制器
        // dispose 行为观察，不用自己的 flag 冒充 ACK。
        _disposeRequested = true;
      });
    });
  }

  /// 当前展示集合里某条消息的正文（History 冻结断言用）。
  String? displayedText(String id) {
    for (final message in _generation.controller.messages) {
      if (message.id == id && message is TextMessage) return message.text;
    }
    return null;
  }

  Map<String, Object?> snapshot() {
    final generation = _generation;
    final position = generation.scroll.hasClients
        ? generation.scroll.position
        : null;
    return <String, Object?>{
      'generation': generation.index,
      'mode': _mode.name,
      'messageIds': <String>[
        for (final message in generation.controller.messages) message.id,
      ],
      'messageCount': generation.controller.messages.length,
      'tailIds': <String>[for (final message in _tail) message.id],
      'tailCount': _tail.length,
      'pageRequests': generation.pageRequests,
      'stalePagesDropped': _stalePagesDropped,
      'hasOlder': _hasOlder,
      'loading': _loadingOlder,
      'error': _error,
      'offset': position?.pixels,
      'maxScrollExtent': position?.maxScrollExtent,
      'viewportDimension': position?.viewportDimension,
      'latestRevision': _latestRevision,
      'displayRevision': _displayRevision,
      'pendingNewOutput': _pendingNewOutput,
      'shortContent': _shortContent,
      'lastDisposeRequestedGeneration': _lastDisposeRequestedGeneration,
      'disposeRequested': _disposeRequested,
      'scrollAttached': generation.scroll.hasClients,
      'pendingGates': _pendingGates.length,
      'pendingPages': _pages.length,
      'closed': _closed,
      'treeDisposed': _treeDisposed.isCompleted,
      'allStreamsDone': allGenerationStreamsDone,
      'retiredGenerations': <int>[for (final g in _retired) g.index],
    };
  }

  /// 只读几何诊断（Driver `geometry` 命令）：视口 rect + 与视口真实相交的行 rect。
  ///
  /// 通过公开 Element/RenderBox 遍历按 `ValueKey('gate-row-<id>')` 读取，不在应用里维护
  /// 每行 GlobalKey，也不用它驱动任何滚动/锚点。指定 `rowIds` 时最多 [gateGeometryRowLimit]
  /// 个，未找到的进入 `missing`（`mounted: false`）。
  Map<String, Object?> geometry({List<String>? rowIds}) {
    if (rowIds != null && rowIds.length > gateGeometryRowLimit) {
      return <String, Object?>{
        'ok': false,
        'error': 'tooManyRowIds',
        'limit': gateGeometryRowLimit,
      };
    }
    RenderBox? viewport;
    void findViewport(Element element) {
      if (viewport != null) return;
      final key = element.widget.key;
      if (key is ValueKey<String> && key.value == 'gate-timeline') {
        final box = element.renderObject;
        if (box is RenderBox) viewport = box;
        return;
      }
      element.visitChildElements(findViewport);
    }

    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement != null) findViewport(rootElement);
    final viewportBox = viewport;
    if (viewportBox == null || !viewportBox.attached || !viewportBox.hasSize) {
      return <String, Object?>{'ok': false, 'error': 'viewportNotMounted'};
    }
    final globalOrigin = viewportBox.localToGlobal(Offset.zero);
    final size = viewportBox.size;
    // 统一坐标系：视口内左上角为原点；相交判据也在这个 frame 里做。
    final bounds = Offset.zero & size;
    final requested = rowIds?.toSet();
    final rows = <Map<String, Object?>>[];
    final found = <String>{};

    void visit(Element element) {
      final key = element.widget.key;
      if (key is ValueKey<String> && key.value.startsWith('gate-row-')) {
        final id = key.value.substring('gate-row-'.length);
        if (requested == null || requested.contains(id)) {
          found.add(id);
          final render = element.renderObject;
          if (render is! RenderBox) {
            rows.add(<String, Object?>{
              'id': id,
              'mounted': true,
              'painted': false,
              'intersects': false,
              'reason': 'noRenderBox',
            });
          } else if (!render.attached) {
            rows.add(<String, Object?>{
              'id': id,
              'mounted': true,
              'painted': false,
              'intersects': false,
              'reason': 'detachedRenderBox',
            });
          } else if (!render.hasSize ||
              !render.size.isFinite ||
              render.size.isEmpty) {
            rows.add(<String, Object?>{
              'id': id,
              'mounted': true,
              'painted': false,
              'intersects': false,
              'reason': 'notLaidOut',
            });
          } else {
            final local = render.localToGlobal(
              Offset.zero,
              ancestor: viewportBox,
            );
            final rect = local & render.size;
            if (!rect.isFinite) {
              rows.add(<String, Object?>{
                'id': id,
                'mounted': true,
                'painted': false,
                'intersects': false,
                'reason': 'nonFiniteRect',
              });
            } else {
              final intersects =
                  rect.top < bounds.bottom &&
                  rect.bottom > bounds.top &&
                  rect.left < bounds.right &&
                  rect.right > bounds.left;
              rows.add(<String, Object?>{
                'id': id,
                'mounted': true,
                'painted': intersects,
                'intersects': intersects,
                'rect': <String, Object?>{
                  'left': rect.left,
                  'top': rect.top,
                  'width': rect.width,
                  'height': rect.height,
                },
              });
            }
          }
        }
      }
      element.visitChildElements(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    // 默认只返回真正可见（与视口相交且可测）的行；指定 rowIds 时逐个给终态。
    final visible = requested == null
        ? <Map<String, Object?>>[
            for (final row in rows)
              if (row['intersects'] == true) row,
          ]
        : rows;
    return <String, Object?>{
      'ok': true,
      // frame='viewport'：viewport 与 rows.rect 都以视口左上角为原点。
      'frame': 'viewport',
      'viewport': <String, Object?>{
        'left': 0.0,
        'top': 0.0,
        'width': size.width,
        'height': size.height,
      },
      // 视口在全局坐标里的原点/尺寸，供 Driver getTopLeft 交叉核对。
      'viewportGlobal': <String, Object?>{
        'left': globalOrigin.dx,
        'top': globalOrigin.dy,
        'width': size.width,
        'height': size.height,
      },
      'rows': visible,
      // 只有「没有对应 Element」的 id 才进 missing；Element 存在但不可测会在 rows 里
      // 给出 mounted=true + painted=false + reason。
      'missing': <String>[
        if (requested != null)
          for (final id in requested)
            if (!found.contains(id)) id,
      ],
      'requested': requested?.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: Column(
        children: <Widget>[
          _GateStatusBar(
            mode: _mode,
            pendingNewOutput: _pendingNewOutput,
            error: _error,
            hasOlder: _hasOlder,
            loading: _loadingOlder,
            onLoadOlder: loadOlder,
            onReturnLive: returnLive,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: KeyedSubtree(
                  key: const ValueKey<String>('gate-timeline'),
                  child: SizedBox.expand(
                    child: NotificationListener<ScrollMetricsNotification>(
                      onNotification: _onMetrics,
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: _onScrollEnd,
                        child: NotificationListener<UserScrollNotification>(
                          onNotification: _onUserScroll,
                          child: NotificationListener<ScrollUpdateNotification>(
                            onNotification: _onScrollUpdate,
                            child: Chat(
                              key: ValueKey<String>(
                                'gate-chat-${generation.index}',
                              ),
                              currentUserId: 'user',
                              resolveUser: (id) async => User(id: id),
                              chatController: generation.controller,
                              backgroundColor: Colors.transparent,
                              builders: Builders(
                                chatAnimatedListBuilder: (context, itemBuilder) {
                                  return ChatAnimatedListReversed(
                                    itemBuilder: itemBuilder,
                                    scrollController: generation.scroll,
                                    insertAnimationDuration: Duration.zero,
                                    removeAnimationDuration: Duration.zero,
                                    scrollToEndAnimationDuration: Duration.zero,
                                    shouldScrollToEndWhenSendingMessage: false,
                                    topPadding: 0,
                                    bottomPadding: 0,
                                    handleSafeArea: false,
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .manual,
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    cacheExtent: 600,
                                    onEndReached: loadOlder,
                                  );
                                },
                                // 只读投影库自己的 loading 状态：库把 LoadMoreNotifier.isLoadingOlder
                                // 渲染成 Visibility(visible: ...)，测试用 skipOffstage:false 读取它。
                                loadMoreBuilder: (context) => const SizedBox(
                                  key: ValueKey<String>('gate-lib-load-more'),
                                  width: 1,
                                  height: 1,
                                ),
                                composerBuilder: (context) =>
                                    const SizedBox.shrink(),
                                scrollToBottomBuilder: (
                                  context,
                                  animation,
                                  onPressed,
                                ) => const SizedBox.shrink(),
                                emptyChatListBuilder: (context) =>
                                    const SizedBox.shrink(),
                                chatMessageBuilder:
                                    (
                                      context,
                                      message,
                                      index,
                                      animation,
                                      child, {
                                      bool? isRemoved,
                                      required bool isSentByMe,
                                      MessageGroupStatus? groupStatus,
                                    }) {
                                      if (isRemoved == true) {
                                        return const SizedBox.shrink();
                                      }
                                      return GateRow(
                                        key: ValueKey<String>(
                                          'gate-row-${message.id}',
                                        ),
                                        message: message,
                                      );
                                    },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GateStatusBar extends StatelessWidget {
  const _GateStatusBar({
    required this.mode,
    required this.pendingNewOutput,
    required this.error,
    required this.hasOlder,
    required this.loading,
    required this.onLoadOlder,
    required this.onReturnLive,
  });

  final GateMode mode;
  final int pendingNewOutput;
  final String? error;
  final bool hasOlder;
  final bool loading;
  final Future<void> Function() onLoadOlder;
  final VoidCallback onReturnLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('gate-status'),
      color: const Color(0xFF1B222A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          Text(
            'mode=${mode.name}',
            key: const ValueKey<String>('gate-mode'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (pendingNewOutput > 0) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              '有新输出 $pendingNewOutput',
              key: const ValueKey<String>('gate-pending'),
              style: const TextStyle(color: Colors.amber, fontSize: 13),
            ),
          ],
          if (error != null) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              '分页失败：$error',
              key: const ValueKey<String>('gate-error'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const Spacer(),
          if (hasOlder)
            TextButton(
              key: const ValueKey<String>('gate-load-older'),
              onPressed: loading ? null : () => onLoadOlder(),
              child: Text(loading ? '加载中…' : '加载更早'),
            ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey<String>('gate-return-live'),
            onPressed: onReturnLive,
            child: const Text('回到实时'),
          ),
        ],
      ),
    );
  }
}

/// 一行内容：短文本 / Markdown / 长正文 / 紧凑工具摘要（内层独立滚动）。
class GateRow extends StatelessWidget {
  const GateRow({required this.message, super.key});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final text = message is TextMessage ? (message as TextMessage).text : '';
    final kind = switch (message.metadata?['kind']) {
      'markdown' => GateRowKind.markdown,
      'tool' => GateRowKind.tool,
      'longText' => GateRowKind.longText,
      _ => GateRowKind.text,
    };
    final alignEnd = message.authorId == 'user';
    final body = switch (kind) {
      GateRowKind.markdown => GptMarkdown(text),
      GateRowKind.tool => Container(
        key: ValueKey<String>('gate-tool-${message.id}'),
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF222A33),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: ListView.builder(
          key: ValueKey<String>('gate-tool-scroll-${message.id}'),
          itemCount: 24,
          itemBuilder: (context, line) => Text(
            'tool line $line',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ),
      GateRowKind.longText || GateRowKind.text => Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    };
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: alignEnd ? const Color(0xFF2B4A63) : const Color(0xFF1C242C),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message.id,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 4),
            body,
          ],
        ),
      ),
    );
  }
}

/// Driver `shutdown` 的收束序列（可测试版本：`unmount` 由调用方提供）。
///
/// 顺序固定：武装 native 期限 → 关闭本 fixture 的发布与在途查询 → 卸载子树 →
/// 等待 `treeDisposed`（子树卸载 + 所有代次 controller 流真正 done 的 ACK）→
/// `finishExit{exitCode}`。任何一步失败都以 1 退出并上报，绝不伪报 0。
///
/// native 会在此调用中直接终止进程，因此 Driver 请求的响应可能收不到；
/// 退出码以 native-exit 报告为准。
Future<int> runGateShutdown({
  required TimelineGateState state,
  required Future<void> Function() unmount,
}) async {
  var exitCode = 0;
  try {
    await GateHostLifecycle.beginExit();
    final pagesClean = await state.closeScope();
    await unmount();
    await state.treeDisposed;
    if (!pagesClean || !state.allGenerationStreamsDone) exitCode = 1;
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'timeline_native_gate',
        context: ErrorDescription('while shutting down the gate fixture'),
      ),
    );
    exitCode = 1;
  }
  await GateHostLifecycle.finishExit(exitCode: exitCode);
  return exitCode;
}
