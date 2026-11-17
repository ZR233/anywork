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

  int get failedCount => items
      .whereType<AcpTimelineToolCallItem>()
      .where((item) => item.status == AcpToolStatusKind.failed)
      .length;

  bool get active => items.any(
    (item) => switch (item) {
      AcpTimelineToolCallItem(:final status) =>
        status == AcpToolStatusKind.pending ||
            status == AcpToolStatusKind.inProgress,
      AcpTimelineThoughtItem(:final active) => active,
      _ => false,
    },
  );
}
