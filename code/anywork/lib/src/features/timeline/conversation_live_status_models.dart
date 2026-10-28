import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

/// 会话聊天框上方实时状态栏的阶段枚举。
enum ConversationLivePhase {
  /// 空闲（隐藏状态栏）。
  idle,

  /// 准备中（准备上下文、构造请求或等待准入）。
  preparing,

  /// 正在压缩上下文（区分于普通准备中）。
  compacting,

  /// 思考中（等待模型响应或流式产出推理内容）。
  thinking,

  /// 规划工具调用中。
  planning,

  /// 正在执行工具。
  runningTool,

  /// 等待工具权限审批。
  awaitingApproval,

  /// 等待用户交互输入。
  awaitingInput,

  /// 正在停止当前轮次或工具。
  stopping,

  /// 存储受限或保存故障阻塞。
  storageBlocked,

  /// 正在流式输出回复正文（动态增高，达最大高度可滚动，不可展开）。
  responding,
}

/// 单个正在执行工具的生命周期状态。
enum ConversationLiveToolExecutionState {
  running,
  awaitingApproval,
  cancelling,
  finished,
}

/// 泛型等待/运行工具规范接口（Open-Closed 设计）：
///
/// - [S]：工具自身定义的状态类型（如命令输出状态、文件读写状态、子代理等待状态等）。
/// - [M]：工具自身定义的流式增量/状态更新消息类型。
///
/// 新增工具或新增工具专属消息时，只需实现 `LiveToolSpec<MyState, MyEvent>` 并通过
/// [ConversationLiveToolStartedMessage] 与 [ConversationLiveToolEventMessage] 喂入，
/// **无需修改实时状态栏组件、Controller 或顶层 sealed 消息定义**。
abstract interface class LiveToolSpec<S, M> {
  /// 根据工具自身定义的消息 [M] 演进工具状态 [S]。
  S reduce(S state, M message);

  /// 构建工具折叠行主标题（纯文本式，如 `$ cargo test --workspace`）。
  String buildSummaryLabel(BuildContext context, S state);

  /// 构建工具折叠行副标题或简短参数说明（可选）。
  String? buildSubtitleLabel(BuildContext context, S state) => null;

  /// 构建工具折叠行前导视觉元素（无框纯文本前缀符号或线性图标）。
  Widget buildLeading(BuildContext context, S state);

  /// 当前状态是否支持二次展开查看该工具的执行详情。
  bool isExpandable(S state);

  /// 构建展开后的工具详情视图（沿二级 `1px` 左侧竖向引导线展示）。
  Widget buildExpandedDetails(
    BuildContext context,
    S state, {
    required int elapsedSeconds,
  });
}

/// 抹除具体类型参数后的只读工具槽位视图接口。
///
/// 内部由具体泛型实现 `_LiveToolSlot<S, M>` 承载，在保持外层列表类型统一的同时，
/// 完整保留编译期泛型 `S` 与 `M` 的类型安全归约与渲染分派。
abstract interface class LiveToolSlotView {
  String get callId;
  String get toolName;
  DateTime get startedAt;
  ConversationLiveToolExecutionState get executionState;
  bool get isForeground;

  /// 工具当前的强类型状态对象（供测试与调试读取）。
  Object? get rawState;

  bool isExpandable();
  String buildSummaryLabel(BuildContext context);
  String? buildSubtitleLabel(BuildContext context);
  Widget buildLeading(BuildContext context);
  Widget buildExpandedDetails(
    BuildContext context, {
    required int elapsedSeconds,
  });
}

final class _LiveToolSlot<S, M> implements LiveToolSlotView {
  _LiveToolSlot({
    required this.callId,
    required this.toolName,
    required this.spec,
    required S initialState,
    required this.startedAt,
    this.executionState = ConversationLiveToolExecutionState.running,
    this.isForeground = true,
  }) : _state = initialState;

  @override
  final String callId;

  @override
  final String toolName;

  final LiveToolSpec<S, M> spec;
  S _state;

  @override
  DateTime startedAt;

  @override
  ConversationLiveToolExecutionState executionState;

  @override
  bool isForeground;

  @override
  Object? get rawState => _state;

  bool applyEvent(Object? event) {
    if (event is M) {
      _state = spec.reduce(_state, event);
      return true;
    }
    return false;
  }

  @override
  bool isExpandable() => spec.isExpandable(_state);

  @override
  String buildSummaryLabel(BuildContext context) =>
      spec.buildSummaryLabel(context, _state);

  @override
  String? buildSubtitleLabel(BuildContext context) =>
      spec.buildSubtitleLabel(context, _state);

  @override
  Widget buildLeading(BuildContext context) =>
      spec.buildLeading(context, _state);

  @override
  Widget buildExpandedDetails(
    BuildContext context, {
    required int elapsedSeconds,
  }) => spec.buildExpandedDetails(
    context,
    _state,
    elapsedSeconds: elapsedSeconds,
  );
}

/// 实时状态栏支持喂入的所有消息类型的封闭类层次（`sealed class`）。
///
/// 通过喂入该封闭类的子类型消息，可在完全脱离 Rust Bridge、ProviderScope 与
/// AnyworkClient 的纯 Dart 测试或官方 Widget Preview 中驱动所有实时状态与流式更新。
sealed class ConversationLiveStatusMessage {
  const ConversationLiveStatusMessage();
}

/// 阶段切换与基础活动状态消息。
final class ConversationLivePhaseMessage extends ConversationLiveStatusMessage {
  const ConversationLivePhaseMessage({
    required this.phase,
    this.identity = 'live-activity',
    this.turnId,
    this.summary,
    this.errorMessage,
    this.storage,
    this.wait,
    this.details = const [],
    this.detailsLoading = false,
    this.detailsError,
    this.expandableOverride,
    this.backgroundToolCount = 0,
  });

  final String identity;
  final ConversationLivePhase phase;
  final String? turnId;
  final String? summary;
  final String? errorMessage;
  final ThreadStorageStateView? storage;
  final ThreadWaitPresentationView? wait;
  final List<ConversationActivityDetail> details;
  final bool detailsLoading;
  final String? detailsError;
  final bool? expandableOverride;
  final int backgroundToolCount;
}

/// 思考摘要消息（支持 Markdown 格式，如 `正在准备实现计划`）。
///
/// 一旦出现思考摘要，外层状态栏即固定展示该摘要（例如 `思考了 3 秒 · 正在准备计划`），
/// 后续执行工具阶段也继续保留该摘要作为最外层展示，直到新的思考摘要到达将其替换，
/// 或进入文本回复（`responding`）/轮次结束。
final class ConversationLiveThinkingSummaryMessage
    extends ConversationLiveStatusMessage {
  const ConversationLiveThinkingSummaryMessage({
    required this.summaryMarkdown,
    this.elapsedSeconds,
    this.turnId,
  });

  final String summaryMarkdown;
  final int? elapsedSeconds;
  final String? turnId;
}

/// 流式思考正文消息（支持增量 `delta` 追加或 `fullText` 覆盖）。
///
/// - 若当前已有思考摘要，外层状态栏仍只展示思考摘要，流式思考正文收纳在展开区中；
/// - 若当前没有思考摘要，外层状态栏展示一行流式更新的思考内容，不断更新并截断前面部分
///   （保留最新末尾可见），点击可展开查看完整思考正文。
final class ConversationLiveThinkingStreamMessage
    extends ConversationLiveStatusMessage {
  const ConversationLiveThinkingStreamMessage({
    this.delta,
    this.fullText,
    this.clear = false,
  });

  const ConversationLiveThinkingStreamMessage.append(String chunk)
    : delta = chunk,
      fullText = null,
      clear = false;

  const ConversationLiveThinkingStreamMessage.replace(String text)
    : delta = null,
      fullText = text,
      clear = false;

  const ConversationLiveThinkingStreamMessage.clear()
    : delta = null,
      fullText = null,
      clear = true;

  final String? delta;
  final String? fullText;
  final bool clear;
}

/// 泛型工具启动消息：将工具自身的规范 [LiveToolSpec<S, M>] 与初始状态 [S] 注入实时状态栏。
final class ConversationLiveToolStartedMessage<S, M>
    extends ConversationLiveStatusMessage {
  const ConversationLiveToolStartedMessage({
    required this.callId,
    required this.toolName,
    required this.spec,
    required this.initialState,
    this.startedAt,
    this.executionState = ConversationLiveToolExecutionState.running,
    this.isForeground = true,
  });

  final String callId;
  final String toolName;
  final LiveToolSpec<S, M> spec;
  final S initialState;
  final DateTime? startedAt;
  final ConversationLiveToolExecutionState executionState;
  final bool isForeground;

  LiveToolSlotView createSlot(DateTime defaultStartedAt) {
    return _LiveToolSlot<S, M>(
      callId: callId,
      toolName: toolName,
      spec: spec,
      initialState: initialState,
      startedAt: startedAt ?? defaultStartedAt,
      executionState: executionState,
      isForeground: isForeground,
    );
  }
}

/// 泛型工具事件消息：喂入工具自身定义的消息 [M]（如 stdout chunk、新搜索词、子代理进度等）。
final class ConversationLiveToolEventMessage<M>
    extends ConversationLiveStatusMessage {
  const ConversationLiveToolEventMessage({
    required this.callId,
    required this.event,
    this.executionState,
    this.isForeground,
  });

  final String callId;
  final M event;
  final ConversationLiveToolExecutionState? executionState;
  final bool? isForeground;
}

/// 工具执行完成并移出活跃列表的消息。
final class ConversationLiveToolFinishedMessage
    extends ConversationLiveStatusMessage {
  const ConversationLiveToolFinishedMessage({required this.callId});

  final String callId;
}

/// 流式文本输出消息（对应 `responding` 阶段，支持增量 `delta` 追加或 `fullText` 覆盖）。
///
/// 文本输出直接流式展示全部内容，动态增高状态栏，达到最大高度后内部可滚动，
/// **不可展开，也没有单独的展开内容区**。
final class ConversationLiveResponseStreamMessage
    extends ConversationLiveStatusMessage {
  const ConversationLiveResponseStreamMessage({
    this.delta,
    this.fullText,
    this.clear = false,
  });

  const ConversationLiveResponseStreamMessage.append(String chunk)
    : delta = chunk,
      fullText = null,
      clear = false;

  const ConversationLiveResponseStreamMessage.replace(String text)
    : delta = null,
      fullText = text,
      clear = false;

  const ConversationLiveResponseStreamMessage.clear()
    : delta = null,
      fullText = null,
      clear = true;

  final String? delta;
  final String? fullText;
  final bool clear;
}

/// 会话实时状态栏的独立状态控制器。
///
/// 完全不依赖 Rust Bridge、ProviderScope 或 AnyworkClient，通过 [ingest] 消费
/// [ConversationLiveStatusMessage] 即可完成全部状态归约。
class ConversationLiveStatusController extends ChangeNotifier {
  ConversationLiveStatusController({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  String _identity = 'live-activity';
  String? _turnId;
  ConversationLivePhase _phase = ConversationLivePhase.idle;
  String? _phaseSummary;
  String? _errorMessage;
  ThreadStorageStateView? _storage;
  ThreadWaitPresentationView? _wait;
  List<ConversationActivityDetail> _extraDetails = const [];
  bool _detailsLoading = false;
  String? _detailsError;
  bool? _expandableOverride;
  int _backgroundToolCount = 0;

  String? _thinkingSummaryMarkdown;
  int? _thinkingSummarySeconds;
  DateTime? _thinkingStartedAt;
  String _thinkingStreamText = '';

  String _responseStreamText = '';

  final Map<String, LiveToolSlotView> _toolSlots = <String, LiveToolSlotView>{};
  final Set<String> _expandedToolCallIds = <String>{};

  bool _expanded = false;

  String get identity => _identity;
  String? get turnId => _turnId;
  ConversationLivePhase get phase => _phase;
  String? get phaseSummary => _phaseSummary;
  String? get errorMessage => _errorMessage;
  ThreadStorageStateView? get storage => _storage;
  ThreadWaitPresentationView? get wait => _wait;
  List<ConversationActivityDetail> get extraDetails => _extraDetails;
  bool get detailsLoading => _detailsLoading;
  String? get detailsError => _detailsError;
  int get backgroundToolCount => _backgroundToolCount;

  /// 当前粘性保留的思考摘要 Markdown（一旦出现，在工具执行阶段也继续作为最外层展示，直到新摘要替换）。
  String? get thinkingSummaryMarkdown => _thinkingSummaryMarkdown;

  /// 思考耗时秒数（优先取显式传入的秒数，否则按思考开始时间实时计算）。
  int? get thinkingElapsedSeconds {
    if (_thinkingSummarySeconds != null) return _thinkingSummarySeconds;
    if (_thinkingStartedAt == null) return null;
    final seconds = _clock().difference(_thinkingStartedAt!).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  /// 完整的流式思考正文。
  String get thinkingStreamText => _thinkingStreamText;

  /// 单行流式思考文本（将换行与多余空白折叠为空格，供无摘要时的单行尾部展示）。
  String get singleLineThinkingStream =>
      _thinkingStreamText.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 无思考摘要时的单行流式思考前向截断文本（保留最新末尾，截断前面部分）。
  String frontTruncatedThinkingLine({int maxChars = 68}) {
    final single = singleLineThinkingStream;
    if (single.isEmpty || maxChars <= 0) return '';
    final runes = single.runes.toList(growable: false);
    if (runes.length <= maxChars) return single;
    final tail = String.fromCharCodes(runes.sublist(runes.length - maxChars));
    return '…$tail';
  }

  /// 当前是否有思考摘要作为最外层主展示。
  bool get hasStickyThinkingSummary =>
      _phase != ConversationLivePhase.idle &&
      _phase != ConversationLivePhase.responding &&
      _phase != ConversationLivePhase.storageBlocked &&
      _thinkingSummaryMarkdown != null &&
      _thinkingSummaryMarkdown!.trim().isNotEmpty;

  /// 当前是否处于无思考摘要但有流式思考正文的单行截断展示模式。
  bool get hasStreamingThinkingWithoutSummary =>
      !hasStickyThinkingSummary &&
      _phase == ConversationLivePhase.thinking &&
      singleLineThinkingStream.isNotEmpty;

  /// 完整的流式回复正文（`responding` 阶段直接展示）。
  String get responseStreamText {
    if (_responseStreamText.trim().isNotEmpty) {
      return _responseStreamText;
    }
    if (_phase == ConversationLivePhase.responding &&
        _phaseSummary != null &&
        _phaseSummary!.trim().isNotEmpty) {
      return _phaseSummary!;
    }
    return '';
  }

  /// 当前正在执行的工具槽位列表（按插入顺序排列）。
  List<LiveToolSlotView> get activeTools =>
      List<LiveToolSlotView>.unmodifiable(_toolSlots.values);

  int get activeToolCount => _toolSlots.length;

  /// 最近启动的活跃工具槽位。
  LiveToolSlotView? get latestActiveTool =>
      _toolSlots.isEmpty ? null : _toolSlots.values.last;

  /// 指定工具当前是否处于二次展开状态。
  bool isToolExpanded(String callId) => _expandedToolCallIds.contains(callId);

  /// 切换指定工具的二次展开状态。
  void toggleToolExpanded(String callId) {
    if (!_toolSlots.containsKey(callId)) return;
    if (!_expandedToolCallIds.remove(callId)) {
      _expandedToolCallIds.add(callId);
    }
    notifyListeners();
  }

  /// 设置指定工具的二次展开状态。
  void setToolExpanded(String callId, bool expanded) {
    if (!_toolSlots.containsKey(callId)) return;
    final changed = expanded
        ? _expandedToolCallIds.add(callId)
        : _expandedToolCallIds.remove(callId);
    if (changed) notifyListeners();
  }

  /// 计算指定工具已执行的秒数。
  int elapsedSecondsForTool(String callId) {
    final slot = _toolSlots[callId];
    if (slot == null) return 0;
    final elapsed = _clock().difference(slot.startedAt).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  /// 状态栏整体是否可展开：
  /// - `responding` 文本输出直接流式展示，**不可展开**；
  /// - 存在活跃工具、流式思考正文、粘性思考摘要或显式可展开标记时可展开。
  bool get isExpandable {
    if (_phase == ConversationLivePhase.idle ||
        _phase == ConversationLivePhase.responding) {
      return false;
    }
    if (_expandableOverride != null) {
      return _expandableOverride!;
    }
    if (_toolSlots.isNotEmpty) return true;
    if (_thinkingStreamText.trim().isNotEmpty) return true;
    if (hasStickyThinkingSummary) return true;
    if (_extraDetails.isNotEmpty) return true;
    return false;
  }

  /// 状态栏当前是否处于展开状态（`responding` 阶段始终为 `false`）。
  bool get expanded => isExpandable && _expanded;

  /// 是否存在需要每秒刷新计时器的活跃工作（思考计时或运行中工具计时）。
  bool get hasActiveTimer =>
      _phase != ConversationLivePhase.idle &&
      (_toolSlots.isNotEmpty || _phase == ConversationLivePhase.thinking);

  /// 切换顶层展开/收起状态。
  void toggleExpanded() {
    setExpanded(!expanded);
  }

  /// 设置顶层展开/收起状态。
  void setExpanded(bool value) {
    if (!isExpandable) {
      if (_expanded) {
        _expanded = false;
        notifyListeners();
      }
      return;
    }
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  /// 触发一次时钟推进通知（供 UI 每秒定时器或测试手动推进秒数使用）。
  void notifyTick() {
    if (_phase == ConversationLivePhase.idle) return;
    notifyListeners();
  }

  /// 批量喂入消息并一次性通知监听者。
  void ingestAll(Iterable<ConversationLiveStatusMessage> messages) {
    var any = false;
    for (final message in messages) {
      _applyMessage(message);
      any = true;
    }
    if (any) notifyListeners();
  }

  /// 喂入单条 [ConversationLiveStatusMessage] 更新内部状态。
  void ingest(ConversationLiveStatusMessage message) {
    _applyMessage(message);
    notifyListeners();
  }

  void _applyMessage(ConversationLiveStatusMessage message) {
    switch (message) {
      case ConversationLivePhaseMessage():
        final identityChanged = message.identity != _identity;
        final turnChanged =
            message.turnId != null &&
            _turnId != null &&
            message.turnId != _turnId;
        _identity = message.identity;
        if (message.turnId != null) {
          _turnId = message.turnId;
        }
        if (identityChanged) {
          _expanded = false;
          _expandedToolCallIds.clear();
        }
        if (turnChanged ||
            message.phase == ConversationLivePhase.idle ||
            message.phase == ConversationLivePhase.responding) {
          _thinkingSummaryMarkdown = null;
          _thinkingSummarySeconds = null;
          _thinkingStartedAt = null;
          _thinkingStreamText = '';
          if (turnChanged || message.phase == ConversationLivePhase.idle) {
            _responseStreamText = '';
            _toolSlots.clear();
            _expandedToolCallIds.clear();
          }
        }
        if (message.phase == ConversationLivePhase.thinking &&
            _thinkingStartedAt == null) {
          _thinkingStartedAt = _clock();
        } else if (message.phase != ConversationLivePhase.thinking &&
            _thinkingStartedAt != null &&
            _thinkingSummarySeconds == null) {
          final seconds = _clock().difference(_thinkingStartedAt!).inSeconds;
          _thinkingSummarySeconds = seconds < 0 ? 0 : seconds;
        }
        if (message.phase == ConversationLivePhase.responding) {
          _expanded = false;
        }
        _phase = message.phase;
        _phaseSummary = message.summary;
        _errorMessage = message.errorMessage;
        _storage = message.storage;
        _wait = message.wait;
        _extraDetails = message.details;
        _detailsLoading = message.detailsLoading;
        _detailsError = message.detailsError;
        _expandableOverride = message.expandableOverride;
        _backgroundToolCount = message.backgroundToolCount;

      case ConversationLiveThinkingSummaryMessage():
        if (message.turnId != null) {
          _turnId = message.turnId;
        }
        final trimmed = message.summaryMarkdown.trim();
        if (trimmed.isNotEmpty) {
          _thinkingSummaryMarkdown = trimmed;
        }
        if (message.elapsedSeconds != null) {
          _thinkingSummarySeconds = message.elapsedSeconds;
        } else {
          _thinkingStartedAt ??= _clock();
        }

      case ConversationLiveThinkingStreamMessage():
        _thinkingStartedAt ??= _clock();
        if (message.clear) {
          _thinkingStreamText = '';
        }
        if (message.fullText != null) {
          _thinkingStreamText = message.fullText!;
        }
        if (message.delta != null && message.delta!.isNotEmpty) {
          _thinkingStreamText = '$_thinkingStreamText${message.delta!}';
        }

      case ConversationLiveToolStartedMessage():
        final existing = _toolSlots[message.callId];
        final startedAt = message.startedAt ?? existing?.startedAt ?? _clock();
        final slot = message.createSlot(startedAt);
        _toolSlots[message.callId] = slot;

      case ConversationLiveToolEventMessage():
        final slot = _toolSlots[message.callId];
        if (slot is _LiveToolSlot) {
          slot.applyEvent(message.event);
          if (message.executionState != null) {
            slot.executionState = message.executionState!;
          }
          if (message.isForeground != null) {
            slot.isForeground = message.isForeground!;
          }
        }

      case ConversationLiveToolFinishedMessage():
        _toolSlots.remove(message.callId);
        _expandedToolCallIds.remove(message.callId);

      case ConversationLiveResponseStreamMessage():
        if (message.clear) {
          _responseStreamText = '';
        }
        if (message.fullText != null) {
          _responseStreamText = message.fullText!;
        }
        if (message.delta != null && message.delta!.isNotEmpty) {
          _responseStreamText = '$_responseStreamText${message.delta!}';
        }
    }
  }
}
