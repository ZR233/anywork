import '../../models.dart';

/// 条目的执行终态事实（后端 `BridgeChatLifecycle`），与保存水位 [StudioChatItem.saved]
/// 严格独立。
enum StudioChatLifecycle { streaming, terminal }

class StudioChatItem {
  const StudioChatItem(
    this.item, {
    required this.saved,
    required this.lifecycle,
  });

  final ThreadItemView item;
  final bool saved;
  final StudioChatLifecycle lifecycle;

  bool get terminal => lifecycle == StudioChatLifecycle.terminal;
}

class StudioChatSnapshot {
  const StudioChatSnapshot({
    required this.focusedItemId,
    required this.version,
    required this.items,
    required this.hasOlder,
    required this.hasNewer,
    required this.canExtendLatest,
  });

  final String? focusedItemId;
  final int version;
  final List<StudioChatItem> items;
  final bool hasOlder;
  final bool hasNewer;
  final bool canExtendLatest;
}

/// 一次同 item 的原子字段提交：全部字段应用完后一次提交 revision/omitted/saved。
class StudioFieldUpdateView {
  const StudioFieldUpdateView({required this.field, required this.change});

  final ThreadContentFieldView field;
  final ThreadFieldChangeView change;
}

/// 窗口差量里的单条结构化变化（后端 `BridgeViewChange` 的 domain 投影）。
sealed class StudioViewChange {
  const StudioViewChange();
}

class StudioViewSplice extends StudioViewChange {
  const StudioViewSplice({
    required this.index,
    required this.remove,
    required this.items,
  });

  final int index;
  final int remove;
  final List<StudioChatItem> items;
}

class StudioViewItemUpdate extends StudioViewChange {
  const StudioViewItemUpdate({
    required this.itemId,
    required this.expectedRevision,
    required this.revision,
    required this.omittedUnits,
    required this.saved,
    required this.fields,
  });

  final String itemId;
  final int expectedRevision;
  final int revision;
  final int omittedUnits;
  final bool saved;
  final List<StudioFieldUpdateView> fields;
}

/// 唯一内容出口交付的一帧权威内容。
///
/// `Reset` 是权威整窗替换（窗口建立、换焦点/翻页的窗口移动、宿主回退）；
/// `Patch` 是相对消费者自己交付基线的 typed 差量。transport 只做 DTO 投影，
/// 不保存第二份 baseline，也不在此应用差量——应用只属于 read model 的唯一 reducer。
sealed class StudioChatFrame {
  const StudioChatFrame();

  /// 观测记录用的稳定帧类型名；不参与 reducer 判定。
  String get kind => switch (this) {
    StudioChatReset() => 'reset',
    StudioChatPatch() => 'patch',
  };
}

class StudioChatReset extends StudioChatFrame {
  const StudioChatReset(this.snapshot);

  final StudioChatSnapshot snapshot;
}

class StudioChatPatch extends StudioChatFrame {
  const StudioChatPatch({
    required this.from,
    required this.to,
    required this.changes,
    required this.hasNewer,
  });

  final int from;
  final int to;
  final List<StudioViewChange> changes;
  final bool hasNewer;
}

/// 控制操作回执：操作已被权威窗口接受；内容仍由 [StudioChatWindow.next] 以 Reset/Patch
/// 从唯一出口交付。
enum StudioChatDisposition { applied, noChange }

class StudioChatReceipt {
  const StudioChatReceipt({
    required this.operationId,
    required this.version,
    required this.retained,
    required this.disposition,
  });

  /// 控制操作标识：把 pending 状态与「成功回执 + 本地观察到目标版本」关联。
  final int operationId;

  final StudioChatDisposition disposition;

  /// 操作完成后的窗口当前版本（no-op 时等于操作前版本）。
  final int version;

  /// 只对「展开完整正文」有意义：`false` 表示该身份已不在窗口或完整正文此刻不可得。
  final bool retained;
}

/// 一个有界、独立定位的权威内容窗口。
///
/// 唯一内容出口是 [next]：首帧 [initial]，之后 Reset/Patch。控制操作（[load]/[focus]/
/// [extendLatest]/[expandItem]）只返回回执，不交付窗口；「已交付给客户端」的基线只由
/// `next` 推进。同一 view 同时至多一个未完成的 `next`——消费方 reduce 完上一帧后再取下一帧。
abstract interface class StudioChatWindow {
  Future<StudioChatSnapshot> initial();
  Future<StudioChatFrame?> next();
  Future<StudioChatReceipt> load(TimelineDirection direction);
  Future<StudioChatReceipt> extendLatest();
  Future<StudioChatReceipt> focus(String? itemId);

  /// 按 identity 请求一条窗口条目的完整正文。
  ///
  /// 这是一次同 view 的窗口操作：原生窗口把该身份完整正文 retain 进窗口；当它真的升级了可见
  /// 正文时，完整正文由下一次 `next` 以 typed 字段更新交付。`retained == false` 表示该身份已
  /// 不在窗口、或数据源此刻给不出完整正文：调用方保留预览并等待下一次窗口帧或显式重试，不伪造
  /// 正文。迟到/被取代的展开结果绝不写回新窗口。
  Future<StudioChatReceipt> expandItem(String itemId);
  void requestClose();
  Future<void> close();
}

/// The UI requests another batch only after it has processed the preceding one.
///
/// transport 是薄壳：只把 FRB DTO 机械映射成 domain 投影（[StudioChatItem]/[StudioViewChange]），
/// 不保留 baseline、不应用 patch、不生成窗口事实——那是 read model 唯一 reducer 的职责。
