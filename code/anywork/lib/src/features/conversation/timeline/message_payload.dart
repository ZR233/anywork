import 'package:anywork_client/conversation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'message_payload.freezed.dart';

/// 一条 canonical 条目在展示层的 typed 载荷。
///
/// 它不是第二份正文事实源：已加载内容只以本载荷形式存在于当前展示 lease 的
/// `InMemoryChatController.messages` 里，正文来自 canonical 预览，完整字段按
/// [details] 指向的详情引用按需读取（design/26 §26.5、§26.8）。
///
/// 每个原始预览保留自己的身份；GUI 分组只引用同一载荷，不改写原始事实。
@Freezed(toStringOverride: false)
abstract class TimelineMessagePayload with _$TimelineMessagePayload {
  const TimelineMessagePayload._();
  const factory TimelineMessagePayload({
    required ThreadItemView item,
    required StudioTimelineItemSource source,
    required bool saved,
    required StudioTimelineLifecycle lifecycle,
    required int omittedBytes,
    required List<StudioTimelineDetailRef> details,
  }) = _TimelineMessagePayload;
  factory TimelineMessagePayload.fromItem(StudioTimelineItem item) =>
      TimelineMessagePayload(
        item: item.item, source: item.source, saved: item.saved,
        lifecycle: item.lifecycle, omittedBytes: item.omittedBytes,
        details: item.details,
      );
  String get id => item.id;
  int get revision => item.revision;
  bool get terminal => lifecycle == StudioTimelineLifecycle.terminal;

  /// 该字段按需读取全文的入口；null 表示该字段从未交付（与“空字段”不同）。
  StudioTimelineDetailRef? detailFor(ThreadContentFieldView field) {
    for (final detail in details) {
      if (detail.field == field) return detail;
    }
    return null;
  }

  /// 该条目是否有任何被省略的正文：为真时 `bodyOmittedUnits` 给出省略量。
  bool get hasOmittedBody => omittedBytes > 0;

  /// canonical 顺序键：严格 `(ordinal, id)`，与分页 keyset 同一顺序。
  int get order => item.ordinal;

  /// 权威整条 `Add` 落在**已加载**身份上时的原位收敛（design/26 §26.7）。
  ///
  /// 尾部 `Add` 携带权威整条预览，但不承诺同一事实随后还会补发 `UpdateItem`；因此已加载
  /// 身份必须在这里收敛，而不是等待一个不会出现的更新：
  /// - 更高 revision：采纳权威整条（连同它自己的保存水位与终态），本地旧 `saved` 不补到
  ///   新 revision 上；
  /// - 同 revision：逐字段取更完整者，保存/终态/省略量不回退；
  /// - 更旧 revision：迟到事实不得覆盖已加载的新 revision。
  ///
  /// 返回 `null` 表示无法证明与本代次已加载事实兼容（调用方显式重同步），返回同一个实例
  /// 表示这条 `Add` 是更旧 revision 的迟到事实（保持已加载事实，不需要任何操作）。
  ///
  /// 省略量账目**不能**用两份输入的整体省略量合并求出：逐字段取更完整预览后，实际省略
  /// 量可能小于任一输入声明。这里要求两份预览的覆盖方向可比较（一个输入逐字段支配另一
  /// 个），并用支配方的声明作为合成账目；混合覆盖无法在既有预算内证明兼容，直接返回
  /// `null` 显式重同步（design/26 §26.7）。
  TimelineMessagePayload? applyAdd(StudioTimelineItem incoming) {
    if (incoming.item.id != item.id) return null;
    if (incoming.item.ordinal != item.ordinal) return null;
    if (incoming.revision < item.revision) {
      // 迟到的更旧 revision：保持已加载事实，不移除也不回退。
      return this;
    }
    // 执行终态不回退：任何 revision 的权威 `Add` 都不能把已展示终态退回流式。
    if (terminal && !incoming.terminal) return null;
    if (incoming.revision > item.revision) {
      // 更高 revision：采纳权威整条，连同它自己的保存水位与预览账目；
      // 绝不把本地旧 `saved` 水位补到新 revision 上。
      if (!_accountingMatches(incoming.details, incoming.omittedBytes)) {
        return null;
      }
      return TimelineMessagePayload(
        item: incoming.item,
        source: incoming.source,
        saved: incoming.saved,
        lifecycle: incoming.lifecycle,
        omittedBytes: incoming.omittedBytes,
        details: incoming.details,
      );
    }
    final direction = _previewDirection(details, incoming.details);
    if (direction == null) return null;
    // 账目只取一个输入：逐字段支配方（或完全等价时的本地声明）。
    final accounting = direction == _PreviewDirection.incomingFuller
        ? (omitted: incoming.omittedBytes, details: incoming.details)
        : (omitted: omittedBytes, details: details);
    if (direction == _PreviewDirection.identical &&
        incoming.omittedBytes != omittedBytes) {
      // 同一份逐字段预览却声明了不同的省略量：输入自相矛盾。
      return null;
    }
    if (!_accountingMatches(accounting.details, accounting.omitted)) {
      return null;
    }
    // 已核实的合成账目交给 SDK helper，由它只做字段收敛与事实非回退。
    final nextItem = item.convergeWith(
      incoming.item,
      omittedBytes: accounting.omitted,
    );
    if (nextItem == null) return null;
    return TimelineMessagePayload(
      item: nextItem,
      source: incoming.source,
      saved: saved || incoming.saved,
      lifecycle: incoming.terminal || terminal
          ? StudioTimelineLifecycle.terminal
          : incoming.lifecycle,
      omittedBytes: accounting.omitted,
      details: accounting.details,
    );
  }

  /// 两份逐字段预览的覆盖方向：只有一个输入逐字段支配另一个时才可证明账目兼容。
  _PreviewDirection? _previewDirection(
    List<StudioTimelineDetailRef> current,
    List<StudioTimelineDetailRef> incoming,
  ) {
    if (current.length != incoming.length) return null;
    var currentAtLeast = true;
    var incomingAtLeast = true;
    for (final left in current) {
      StudioTimelineDetailRef? right;
      for (final candidate in incoming) {
        if (candidate.field == left.field) {
          right = candidate;
          break;
        }
      }
      if (right == null) return null;
      if (left.totalBytes != right.totalBytes) return null;
      if (left.previewBytes > left.totalBytes ||
          right.previewBytes > right.totalBytes) {
        return null;
      }
      if (left.previewBytes > right.previewBytes) incomingAtLeast = false;
      if (right.previewBytes > left.previewBytes) currentAtLeast = false;
    }
    if (currentAtLeast && incomingAtLeast) return _PreviewDirection.identical;
    if (incomingAtLeast) return _PreviewDirection.incomingFuller;
    if (currentAtLeast) return _PreviewDirection.currentFuller;
    // 跨字段覆盖方向不同：合成后既不是任一声明，无法证明省略量与预算。
    return null;
  }

  /// 应用一帧同身份原子字段提交；本地 revision 不匹配或状态不合法时返回 null。
  ///
  /// 返回 null 表示「本展示代次无法继续这条身份」：调用方必须显式重同步，不能把片段
  /// 当成正文继续应用。
  ///
  /// 预览完整度只在能证明是同一份原文的更完整交付时前进：同 revision 下预览退回、或
  /// 原文没有变短却被预算挤短，都属于无法证明连续（design/26 §26.7）。更高 revision 的
  /// 原文**确实变短**或字段确实删除则仍是合法权威修订，原位替换/删除。
  TimelineMessagePayload? applyUpdate(StudioTimelineUpdateItem change) {
    if (!_previewProgressIsProvable(change)) return null;
    final nextItem = item.applyFieldUpdates(
      fields: [
        for (final update in change.fields)
          ThreadFieldUpdateView(field: update.field, change: update.change),
      ],
      expectedRevision: change.expectedRevision,
      revision: change.revision,
      omittedUnits: change.omittedBytes,
      saved: change.saved,
      terminal: change.lifecycle == StudioTimelineLifecycle.terminal,
      itemShell: change.itemShell,
    );
    if (nextItem == null) return null;
    final nextDetails = _detailsAfter(change);
    // 声明的整体省略量必须等于逐字段账目之和，否则本帧数字自相矛盾。
    if (!_accountingMatches(nextDetails, change.omittedBytes)) return null;
    return TimelineMessagePayload(
      item: nextItem,
      source: source,
      saved: change.saved,
      lifecycle: change.lifecycle,
      omittedBytes: change.omittedBytes,
      details: nextDetails,
    );
  }

  /// 逐字段 `total - preview` 之和必须与声明的整体省略量相符。
  ///
  /// 这是同一条账目不变量：`Add`/`UpdateItem`/更高 revision 路径都必须满足，不能只靠
  /// 某个输入自己的声明“看起来合理”（design/26 §26.7）。
  static bool _accountingMatches(
    List<StudioTimelineDetailRef> details,
    int declared,
  ) {
    if (declared < 0) return false;
    var sum = 0;
    for (final ref in details) {
      if (ref.previewBytes < 0 ||
          ref.totalBytes < 0 ||
          ref.previewBytes > ref.totalBytes) {
        return false;
      }
      sum += ref.totalBytes - ref.previewBytes;
    }
    return sum == declared;
  }

  /// 用逐字段 total/preview 判断这帧的预览完整度是否可证明前进。
  ///
  /// 判定都在持有 old/new 逐字段长度的这一层做（SDK 的裸字符串 helper 没有这些信息）：
  /// - 同 revision：原文长度必须不变、预览不得退回（预览退回只能是预算重新分配的产物）；
  /// - 更高 revision：原文确实变短或字段删除是权威修订；原文未变短却把预览挤短则无法
  ///   证明是同一事实的更完整交付，必须显式重同步；
  /// - 任何 revision：`previewBytes <= totalBytes` 且非负。
  List<StudioTimelineDetailRef> _detailsAfter(StudioTimelineUpdateItem change) {
    final next = <ThreadContentFieldView, StudioTimelineDetailRef>{
      // 详情引用的 revision 是条目**当前** revision，不是字段独立版本：条目推进时
      // 未变化的字段也必须重钉，否则它从此无法按正确 revision 读取（design/26 §26.7）。
      for (final detail in details)
        detail.field: StudioTimelineDetailRef(
          field: detail.field,
          revision: change.revision,
          totalBytes: detail.totalBytes,
          previewBytes: detail.previewBytes,
        ),
    };
    for (final update in change.fields) {
      if (update.change is RemoveThreadFieldChangeView) {
        next.remove(update.field);
        continue;
      }
      next[update.field] = StudioTimelineDetailRef(
        field: update.field,
        revision: change.revision,
        totalBytes: update.totalBytes,
        previewBytes: update.previewBytes,
      );
    }
    return List.unmodifiable(next.values);
  }

  /// 见 [applyUpdate] 的文档：只在能证明连续时允许本帧改变预览完整度。
  bool _previewProgressIsProvable(StudioTimelineUpdateItem change) {
    if (change.omittedBytes < 0) return false;
    final previous = <ThreadContentFieldView, StudioTimelineDetailRef>{
      for (final detail in details) detail.field: detail,
    };
    final sameRevision = change.revision == item.revision;
    for (final update in change.fields) {
      if (update.totalBytes < 0 || update.previewBytes < 0) return false;
      if (update.previewBytes > update.totalBytes) return false;
      if (update.change is RemoveThreadFieldChangeView) continue;
      final before = previous[update.field];
      if (before == null) continue;
      if (sameRevision) {
        // 同一 canonical revision：原文长度与预览完整度都只能保持或提升。
        if (update.totalBytes != before.totalBytes) return false;
        if (update.previewBytes < before.previewBytes) return false;
        continue;
      }
      // 更高 revision：原文没变短却把预览挤短 → 预算重新分配，无法证明连续。
      if (update.totalBytes >= before.totalBytes &&
          update.previewBytes < before.previewBytes) {
        return false;
      }
    }
    return true;
  }
}

/// 逐字段预览的覆盖方向（用于选择唯一一份省略量账目）。
enum _PreviewDirection { identical, incomingFuller, currentFuller }
