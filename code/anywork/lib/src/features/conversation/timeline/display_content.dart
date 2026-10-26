import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/timeline_view_state.dart';
import 'presentation_controller.dart';
import 'presentation_item.dart';

/// Per-display incremental projection, never a second Message/body collection.
final class DisplayContent {
  DisplayContent(InMemoryChatController controller, int generation)
    : _presentation = TimelinePresentationController(
        controller,
        generation: generation,
      );
  final TimelinePresentationController _presentation;
  (int, String)? _floor;
  (int, String)? _ceiling;
  final Map<String, (int, String)> _excluded = {};
  static const int _excludedIdentities = 128;
  bool _excludedOverflow = false;
  TimelineDisplayMode mode = TimelineDisplayMode.live;
  int? _appliedVersion;
  String? _olderCursor;
  bool _hasOlder = false;

  int? get appliedVersion => _appliedVersion;
  String? get olderCursor => _olderCursor;
  bool get hasOlder => _hasOlder;
  int get loadedCount => _presentation.length;
  TimelinePresentationItem? presentationFor(String id) =>
      _presentation.ownerOf(id);
  TimelineMessagePayload? payloadOf(String id) => _presentation.payload(id);
  void addItemListener(TimelineItemListener listener) =>
      _presentation.addItemListener(listener);
  void removeItemListener(TimelineItemListener listener) =>
      _presentation.removeItemListener(listener);
  Future<void> flushWrites() => _presentation.flushWrites();
  void dispose() => _presentation.dispose();

  void adoptBaseline(StudioTimelineBaseline baseline) {
    _presentation.reset();
    _excluded.clear();
    _excludedOverflow = false;
    final ordered = [...baseline.items]
      ..sort(
        (left, right) => compareCanonical(
          (left.item.ordinal, left.id),
          (right.item.ordinal, right.id),
        ),
      );
    for (final item in ordered) {
      _presentation.add(TimelineMessagePayload.fromItem(item));
    }
    _appliedVersion = baseline.version;
    _olderCursor = baseline.before;
    _hasOlder = baseline.hasOlder;
    _floor = ordered.isEmpty
        ? null
        : (ordered.first.item.ordinal, ordered.first.id);
    _ceiling = ordered.isEmpty
        ? null
        : (ordered.last.item.ordinal, ordered.last.id);
  }

  /// 应用一帧连续补丁；返回 false 表示本代次无法证明连续，需要显式新基线。
  ///
  /// History 下已展示内容/结构/saved 全部冻结：不写 Message、不改版本水位。
  bool applyPatch(StudioTimelinePatch patch) {
    if (mode == TimelineDisplayMode.history) return true;
    if (_appliedVersion != patch.from) return false;
    for (final change in patch.changes) {
      final applied = switch (change) {
        StudioTimelineAdd(:final item) => _applyAdded(item),
        StudioTimelineUpdateItem() => _applyUpdated(change),
        StudioTimelineRemove(:final itemId) => _applyRemoved(itemId),
      };
      if (!applied) return false;
    }
    _appliedVersion = patch.to;
    return true;
  }

  /// 一条权威整条预览落进本代次：已加载身份原位收敛，新身份按 canonical 顺序插入。
  ///
  /// `Add` 不保证该身份从未被页查询加载，也不保证随后会补发 `UpdateItem`，因此不能把
  /// 已加载身份直接跳过。更早且未被本代次覆盖的新身份不插入（避免在分页前缀里造洞）、
  /// 也不另存待回放正文；它们由后续页查询取当时的权威值。
  bool _applyAdded(StudioTimelineItem incoming) {
    final payload = _presentation.payload(incoming.id);
    if (payload != null) {
      final next = payload.applyAdd(incoming);
      if (next == null) return false;
      if (!identical(next, payload)) _presentation.replace(incoming.id, next);
      return true;
    }
    final key = (incoming.item.ordinal, incoming.id);
    final floor = _floor;
    if (floor != null && compareCanonical(key, floor) < 0) {
      _rememberExcluded(incoming.id, key);
      return true;
    }
    _excluded.remove(incoming.id);
    _presentation.add(TimelineMessagePayload.fromItem(incoming));
    final ceiling = _ceiling;
    if (ceiling == null || compareCanonical(key, ceiling) > 0) _ceiling = key;
    return true;
  }

  bool _applyUpdated(StudioTimelineUpdateItem change) {
    final current = _presentation.payload(change.itemId);
    if (current != null) {
      final next = current.applyUpdate(change);
      if (next == null) return false;
      _presentation.replace(change.itemId, next);
      return true;
    }
    // 未知身份：只有能证明它属于被有意忽略的更早范围时才能安静跳过。
    final shell = change.itemShell;
    final floor = _floor;
    if (shell != null) {
      if (shell.id != change.itemId) return false;
      final key = (shell.ordinal, shell.id);
      if (floor != null && compareCanonical(key, floor) < 0) {
        _rememberExcluded(change.itemId, key);
        return true;
      }
      // 已覆盖范围内的空洞：本代次漏了一条事实，必须显式重同步。
      return false;
    }
    return _excluded.containsKey(change.itemId);
  }

  bool _applyRemoved(String itemId) {
    // 真实删除清掉该身份的忽略证据，但**不**抹掉已经覆盖的范围下界。
    _excluded.remove(itemId);
    _presentation.remove(itemId);
    return true;
  }

  /// 前插一页更早消息；重叠身份不重复插入，返回实际前插条数。
  ///
  /// 返回 null 表示这页与已覆盖范围无法证明连续（例如页游标之后又发布过更早身份）：
  /// 调用方必须显式重同步，不能把更早身份插进已覆盖范围造成空洞。
  int? prependOlder(StudioTimelinePage page) {
    final floor = _floor;
    final accepted = <(StudioTimelineItem, (int, String))>[];
    for (final item in page.items) {
      final key = (item.item.ordinal, item.id);
      if (floor != null && compareCanonical(key, floor) >= 0) {
        // 已加载的重叠身份直接去重；未加载却在已覆盖范围内说明页前缀与本代次不连续。
        if (_presentation.contains(item.id)) continue;
        return null;
      }
      if (_presentation.contains(item.id)) continue;
      accepted.add((item, key));
    }
    accepted.sort((left, right) => compareCanonical(left.$2, right.$2));
    // 这一页会把 [新下界, 旧下界) 纳入覆盖：区间里已知存在、但页快照没有交付的身份
    // 会被游标永久越过。已知证据不完整时（有界元数据已淘汰）同样不能声称完整。
    if (floor != null && accepted.isNotEmpty) {
      if (_excludedOverflow) return null;
      final newFloor = accepted.first.$2;
      final delivered = {for (final item in page.items) item.id};
      for (final entry in _excluded.entries) {
        final key = entry.value;
        if (compareCanonical(key, floor) >= 0) continue;
        if (compareCanonical(key, newFloor) < 0) continue;
        if (delivered.contains(entry.key)) continue;
        return null;
      }
    }
    for (final entry in accepted) {
      _presentation.add(TimelineMessagePayload.fromItem(entry.$1));
      _excluded.remove(entry.$1.id);
    }
    if (accepted.isNotEmpty) _floor = accepted.first.$2;
    _olderCursor = page.before;
    _hasOlder = page.hasOlder;
    return accepted.length;
  }

  /// 记住“更早范围里已知存在但本代次不展示”的身份与位置；退出有界容量后不再声称完整。
  void _rememberExcluded(String itemId, (int, String) key) {
    if (_excluded.length >= _excludedIdentities &&
        !_excluded.containsKey(itemId)) {
      _excluded.remove(_excluded.keys.first);
      _excludedOverflow = true;
    }
    _excluded[itemId] = key;
  }

  void enterHistory() => mode = TimelineDisplayMode.history;
}

/// canonical 顺序：严格 `(ordinal, id)`，与分页 keyset 同一顺序。
int compareCanonical((int, String) left, (int, String) right) {
  final byOrder = left.$1.compareTo(right.$1);
  return byOrder != 0 ? byOrder : left.$2.compareTo(right.$2);
}
