import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/types/chat.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import 'content_converters.dart';
import 'timeline_field_converters.dart';

StudioTimelineFeedFrame timelineFrameFromBridge(
  native.BridgeTimelineFrame value, {
  required String threadId,
}) => switch (value) {
  native.BridgeTimelineFrame_Data(:final deliverySequence, :final event) =>
    StudioTimelineFeedFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'Timeline delivery sequence',
      ),
      event: switch (event) {
        native.BridgeTimelineEvent_Baseline(:final baseline) =>
          StudioTimelineFeedEvent.baseline(
            baseline: timelineBaselineFromBridge(baseline, threadId: threadId),
          ),
        native.BridgeTimelineEvent_Update(:final update) =>
          StudioTimelineFeedEvent.update(update: _update(update, threadId)),
      },
    ),
  native.BridgeTimelineFrame_Failure(:final error) =>
    StudioTimelineFeedFrame.failure(error: bridgeFailure(error)),
  native.BridgeTimelineFrame_Closed() => const StudioTimelineFeedFrame.closed(),
};

StudioTimelineBaseline timelineBaselineFromBridge(
  native.BridgeTimelineBaseline value, {
  required String threadId,
}) => StudioTimelineBaseline(
  subscriptionId: value.subscriptionId,
  version: exactU64(value.version, 'Timeline version'),
  items: List.unmodifiable(value.items.map((item) => _item(item, threadId))),
  before: value.before,
  hasOlder: value.hasOlder,
);

StudioTimelinePage timelinePageFromBridge(
  native.BridgeTimelinePage value, {
  required String threadId,
}) => StudioTimelinePage(
  items: List.unmodifiable(value.items.map((item) => _item(item, threadId))),
  before: value.before,
  hasOlder: value.hasOlder,
);

StudioTimelineUpdate _update(
  native.BridgeTimelineUpdate value,
  String threadId,
) => switch (value) {
  native.BridgeTimelineUpdate_Patch(
    :final subscriptionId,
    :final from,
    :final to,
    :final changes,
    :final priority,
  ) =>
    StudioTimelineUpdate.patch(
      subscriptionId: subscriptionId,
      from: exactU64(from, 'Timeline patch from'),
      to: exactU64(to, 'Timeline patch to'),
      changes: List.unmodifiable(
        changes.map((change) => _change(change, threadId)),
      ),
      priority: switch (priority) {
        native.BridgeTimelinePriority.immediate =>
          StudioTimelinePriority.immediate,
        native.BridgeTimelinePriority.coalesced =>
          StudioTimelinePriority.coalesced,
      },
    ),
  native.BridgeTimelineUpdate_Resync(
    :final subscriptionId,
    :final reason,
    :final baseline,
  ) =>
    StudioTimelineUpdate.resync(
      subscriptionId: subscriptionId,
      reason: switch (reason) {
        native.BridgeTimelineResyncReason.lagging =>
          StudioTimelineResyncReason.lagging,
        native.BridgeTimelineResyncReason.unavailable =>
          StudioTimelineResyncReason.unavailable,
      },
      baseline: timelineBaselineFromBridge(baseline, threadId: threadId),
    ),
};

StudioTimelineChange _change(
  native.BridgeTimelineChange value,
  String threadId,
) => switch (value) {
  native.BridgeTimelineChange_Add(:final item) => StudioTimelineChange.add(
    _item(item, threadId),
  ),
  native.BridgeTimelineChange_Remove(:final itemId) =>
    StudioTimelineChange.remove(itemId),
  native.BridgeTimelineChange_UpdateItem(
    :final itemId,
    :final expectedRevision,
    :final revision,
    :final omittedBytes,
    :final saved,
    :final lifecycle,
    :final itemShell,
    :final fields,
  ) =>
    StudioTimelineChange.updateItem(
      itemId: itemId,
      expectedRevision: exactU64(
        expectedRevision,
        'Timeline expected item revision',
      ),
      revision: exactU64(revision, 'Timeline item revision'),
      omittedBytes: exactU64(omittedBytes, 'Timeline omitted bytes'),
      saved: saved,
      lifecycle: _lifecycle(lifecycle),
      itemShell: itemShell == null
          ? null
          : contentItemFromBridge(
              itemShell,
              expectedThreadId: threadId,
              saved: saved,
              executionTerminal:
                  lifecycle == native.BridgeTimelineLifecycle.terminal,
              omittedBytes: exactU64(omittedBytes, 'Timeline omitted bytes'),
            ),
      fields: List.unmodifiable([
        for (final field in fields)
          StudioFieldUpdateView(
            field: contentFieldFromBridge(field.field),
            change: switch (field.change) {
              native.BridgeTimelineFieldChange_Unchanged() =>
                const ThreadFieldChangeView.unchanged(),
              native.BridgeTimelineFieldChange_Append(:final text) =>
                ThreadFieldChangeView.append(text),
              native.BridgeTimelineFieldChange_Replace(:final text) =>
                ThreadFieldChangeView.replace(text),
              native.BridgeTimelineFieldChange_Remove() =>
                const ThreadFieldChangeView.remove(),
            },
            totalBytes: exactU64(
              field.totalBytes,
              'Timeline field total bytes',
            ),
            previewBytes: exactU64(
              field.previewBytes,
              'Timeline field preview bytes',
            ),
          ),
      ]),
    ),
};

StudioTimelineItem _item(native.BridgeTimelineItem value, String threadId) =>
    StudioTimelineItem(
      item: contentItemFromBridge(
        value.item,
        expectedThreadId: threadId,
        saved: value.saved,
        executionTerminal:
            value.lifecycle == native.BridgeTimelineLifecycle.terminal,
        omittedBytes: exactU64(value.omittedBytes, 'Timeline omitted bytes'),
      ),
      source: switch (value.source) {
        native.BridgeTimelineItemSource_Content() =>
          const StudioTimelineItemSource.content(),
        native.BridgeTimelineItemSource_ModelRecovery(
          :final attemptId,
          :final notice,
        ) =>
          StudioTimelineItemSource.modelRecovery(
            attemptId: attemptId,
            notice: switch (notice) {
              native.BridgeTimelineRecoveryNotice.retry =>
                StudioTimelineRecoveryNotice.retry,
              native.BridgeTimelineRecoveryNotice.result =>
                StudioTimelineRecoveryNotice.result,
            },
          ),
      },
      saved: value.saved,
      lifecycle: _lifecycle(value.lifecycle),
      omittedBytes: exactU64(value.omittedBytes, 'Timeline omitted bytes'),
      details: List.unmodifiable([
        for (final ref in value.details)
          StudioTimelineDetailRef(
            field: contentFieldFromBridge(ref.field),
            revision: exactU64(ref.revision, 'Timeline detail revision'),
            totalBytes: exactU64(ref.totalBytes, 'Timeline detail total bytes'),
            previewBytes: exactU64(
              ref.previewBytes,
              'Timeline detail preview bytes',
            ),
          ),
      ]),
    );

StudioTimelineLifecycle _lifecycle(
  native.BridgeTimelineLifecycle value,
) => switch (value) {
  native.BridgeTimelineLifecycle.streaming => StudioTimelineLifecycle.streaming,
  native.BridgeTimelineLifecycle.terminal => StudioTimelineLifecycle.terminal,
};

StudioTimelineDetailChunk timelineDetailFromBridge(
  native.BridgeTimelineDetailChunk value,
) => StudioTimelineDetailChunk(
  itemId: value.itemId,
  field: contentFieldFromBridge(value.field),
  revision: exactU64(value.revision, 'Timeline detail revision'),
  text: value.text,
  totalBytes: exactU64(value.totalBytes, 'Timeline detail total bytes'),
  continuation: value.continuation,
);
