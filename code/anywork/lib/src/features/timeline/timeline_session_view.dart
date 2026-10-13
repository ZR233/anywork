import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/commands/thread_commands.dart';
import '../../data/frb/studio_api.dart' show StudioBridgeDataSource;
import '../../data/stores/selection_store.dart';
import '../../data/stores/thread_session_store.dart';
import '../../domain/models/studio_models.dart';
import '../../domain/models/timeline_commands.dart';

part 'timeline_session_view.g.dart';

/// 当前选中且已打开会话的有界窗口。没有历史窗口时返回 null，调用方保留构造参数。
class TimelineSessionWindow {
  const TimelineSessionWindow({
    required this.threadId,
    required this.rows,
    required this.turn,
    required this.history,
    required this.isLoadingOlder,
    required this.isLoadingNewer,
  });

  final String threadId;
  final List<TimelineRow> rows;
  final StudioTurnView? turn;
  final ThreadHistoryWindow history;
  final bool isLoadingOlder;
  final bool isLoadingNewer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineSessionWindow &&
          threadId == other.threadId &&
          listEquals(rows, other.rows) &&
          turn == other.turn &&
          history == other.history &&
          isLoadingOlder == other.isLoadingOlder &&
          isLoadingNewer == other.isLoadingNewer;

  @override
  int get hashCode => Object.hash(
    threadId,
    Object.hashAll(rows),
    turn,
    history,
    isLoadingOlder,
    isLoadingNewer,
  );
}

@riverpod
TimelineSessionWindow? timelineSessionWindow(Ref ref) {
  final selection = ref.watch(selectionStoreProvider);
  final threadId = selection.selectedThreadId;
  // needsOpen 时不 watch session，避免首屏恢复选择自动建流。
  if (threadId == null || selection.needsOpen) return null;
  final session = ref.watch(threadSessionStoreProvider(threadId));
  if (!session.hasChatWindow && session.items.isEmpty) {
    return null;
  }
  final history = session.history;
  final loadingOlder =
      history.isLoading && history.direction == TimelineDirection.older;
  final loadingNewer =
      history.isLoading && history.direction == TimelineDirection.newer;
  return TimelineSessionWindow(
    threadId: threadId,
    rows: timelineRowsFromThreadItems(session.items),
    turn: session.activeTurn,
    history: history,
    isLoadingOlder: loadingOlder,
    isLoadingNewer: loadingNewer,
  );
}

/// 把时间线 UI 命令完整映射到 threadCommands：分页、权威窗口扩展、本地跳转、正文补齐与锚点写回。
Future<void> dispatchTimelineSessionCommand(
  ThreadCommands commands,
  String threadId,
  TimelineCommand command,
) {
  return switch (command) {
    TimelineLoadOlder() => commands.loadOlderHistory(threadId),
    TimelineLoadNewer() => commands.loadNewerHistory(threadId),
    TimelineExtendLatest() => commands.extendLatestHistory(threadId),
    TimelineJumpToLatest() => commands.jumpToLatest(threadId),
    TimelineExpandBody(:final itemId) => commands.loadItemBody(
      threadId,
      itemId,
    ),
    TimelineVisibleBodies(:final itemIds) => commands.ensureItemBodies(
      threadId,
      itemIds,
    ),
    TimelineAnchorChanged(:final anchor, :final viewAction) =>
      commands.updateTimelineAnchor(threadId, anchor, viewAction: viewAction),
  };
}

/// 附件字节没有命令 lane。这是已知缺口：feature 直接读 data source，不往 data/ 加方法。
Future<Uint8List> readTimelineAttachment(
  StudioBridgeDataSource api,
  String threadId,
  String attachmentId,
) {
  return api.readThreadAttachment(threadId, attachmentId);
}
