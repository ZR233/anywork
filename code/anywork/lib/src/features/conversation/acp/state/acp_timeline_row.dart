import 'acp_view_state.dart';

sealed class AcpTimelineRow {
  const AcpTimelineRow();

  String get id;
}

final class AcpTimelineMessageRow extends AcpTimelineRow {
  const AcpTimelineMessageRow(this.item);

  final AcpTimelineItemPresentation item;

  @override
  String get id => item.id;
}

final class AcpTimelineProcessRow extends AcpTimelineRow {
  AcpTimelineProcessRow({
    required this.id,
    required List<AcpTimelineItemPresentation> items,
  }) : items = List.unmodifiable(items);

  @override
  final String id;
  final List<AcpTimelineItemPresentation> items;

  int get toolCount => items.whereType<AcpTimelineToolCallItem>().length;

  int get thoughtCount => items.whereType<AcpTimelineThoughtItem>().length;

  bool get hasOnlyThoughts =>
      items.isNotEmpty && items.every((item) => item is AcpTimelineThoughtItem);

  bool get hasOnlyTools =>
      items.isNotEmpty &&
      items.every((item) => item is AcpTimelineToolCallItem);

  AcpTimelineToolCallItem? get activeTool {
    for (final item in items.reversed) {
      if (item case final AcpTimelineToolCallItem tool
          when tool.status == AcpToolStatusKind.pending ||
              tool.status == AcpToolStatusKind.inProgress) {
        return tool;
      }
    }
    return null;
  }

  AcpTimelineThoughtItem? get activeThought {
    for (final item in items.reversed) {
      if (item case final AcpTimelineThoughtItem thought when thought.active) {
        return thought;
      }
    }
    return null;
  }

  AcpTimelineThoughtItem? get latestThought {
    for (final item in items.reversed) {
      if (item case final AcpTimelineThoughtItem thought) {
        return thought;
      }
    }
    return null;
  }

  AcpCompactionUpdatePresentation? get activeCompaction {
    for (final item in items.reversed) {
      if (item
          case AcpTimelineSessionUpdateItem(
            update: final AcpCompactionUpdatePresentation compaction,
          )
          when compaction.inProgress && compaction.errorMessage == null) {
        return compaction;
      }
    }
    return null;
  }

  static String thoughtSummaryText(AcpTimelineThoughtItem thought) {
    final direct = thought.summary.trim();
    if (direct.isNotEmpty) return direct;
    for (final block in thought.blocks) {
      if (block case AcpTextBlockPresentation(:final text)) {
        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) return trimmed;
        }
      }
    }
    return '';
  }

  bool get active => items.any(
    (item) => switch (item) {
      AcpTimelineToolCallItem(:final status) =>
        status == AcpToolStatusKind.pending ||
            status == AcpToolStatusKind.inProgress,
      AcpTimelineThoughtItem(:final active) => active,
      AcpTimelineSessionUpdateItem(
        update: AcpCompactionUpdatePresentation(:final inProgress),
      ) =>
        inProgress,
      _ => false,
    },
  );
}
