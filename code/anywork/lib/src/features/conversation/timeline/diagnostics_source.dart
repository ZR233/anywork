import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../../../diagnostics/contracts/timeline_diagnostics.dart';
import '../../../diagnostics/studio_driver_key_values.dart';
import '../state/plan_confirmation_ownership.dart';
import '../state/timeline_view_state.dart';
import 'coordinator.dart';
import 'presentation_item.dart';

/// Request-local adaptation of the actual display. No consumer, observer,
/// Session lookup/create, detail read, geometry cache or retained body list.
final class ConversationTimelineDiagnostics
    implements TimelineDiagnosticsSource {
  ConversationTimelineDiagnostics(this._coordinator);
  final TimelineCoordinator _coordinator;

  @override
  TimelineDiagnosticsSnapshot capture() {
    final state = _coordinator.value;
    if (state == null) {
      return const TimelineDiagnosticsSnapshot(
        timeline: null,
        timelineScroll: null,
      );
    }
    final display = _coordinator.display(state.threadId);
    final items = <TimelineItemFacts>[];
    final groups = <TimelinePresentationFacts>[];
    if (display != null && !display.retired) {
      for (final message in display.canvas.chatController.messages) {
        final group = timelinePresentationOf(message);
        if (group == null) continue;
        groups.add(
          TimelinePresentationFacts(
            id: group.id,
            kind: group.kind.name,
            ordinal: group.position.$1,
            memberIds: group.memberIds,
            visibleMemberIds: group.visibleMemberIds,
            skillPairs: {
              for (final id in group.memberIds) id: ?group.pairedToolId(id),
            },
            expanded: group.expanded,
            activeCount: group.activeCount,
            issueCount: group.issueCount,
          ),
        );
        for (final payload in group.payloads) {
          items.add(_itemFacts(payload));
        }
      }
      items.sort((left, right) {
        final order = left.ordinal.compareTo(right.ordinal);
        return order == 0 ? left.id.compareTo(right.id) : order;
      });
    }
    final timeline = TimelineDisplayFacts(
      threadId: state.threadId,
      generation: state.generation,
      ready: state.ready,
      mode: state.displayMode.name,
      connection: state.connectionPhase,
      // Runtime type only; code/retryable/correlationId come from an actual
      // StudioFailure and stay null for an unknown original error.
      connectionErrorType: state.connectionErrorType,
      connectionErrorCode: state.connectionErrorCode,
      connectionErrorRetryable: state.connectionErrorRetryable,
      connectionErrorCorrelationId: state.connectionErrorCorrelationId,
      appliedVersion: display?.appliedVersion,
      olderCursor: state.olderCursor,
      hasOlder: state.hasOlder,
      loadingOlder: state.olderLoading,
      // Same diagnostic type rule as the connection error: public type name for
      // a typed failure, never `toString()` or a private generator name.
      olderError: diagnosticTypeName(state.olderError),
      olderErrorCode: switch (state.olderError) {
        final StudioFailure failure => failure.code,
        _ => null,
      },
      hasNewOutput: state.hasNewOutput,
      preparingLive: state.preparingLive,
      items: items,
      presentationItems: groups,
    );
    if (display == null || display.retired) {
      return TimelineDiagnosticsSnapshot(
        timeline: timeline,
        timelineScroll: null,
      );
    }
    final positions = display.canvas.scrollController.positions;
    final position = positions.length == 1 ? positions.single : null;
    if (position == null || !position.hasContentDimensions) {
      return TimelineDiagnosticsSnapshot(
        timeline: timeline,
        timelineScroll: TimelineScrollDiagnostic(
          threadId: display.threadId,
          generation: display.generation,
          pixels: null,
          minScrollExtent: null,
          maxScrollExtent: null,
          viewportDimension: null,
          extentBefore: null,
          extentAfter: null,
          atLiveEdge: false,
          isScrolling: false,
        ),
      );
    }
    return TimelineDiagnosticsSnapshot(
      timeline: timeline,
      timelineScroll: TimelineScrollDiagnostic(
        threadId: display.threadId,
        generation: display.generation,
        pixels: position.pixels,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
        viewportDimension: position.viewportDimension,
        extentBefore: position.extentBefore,
        extentAfter: position.extentAfter,
        atLiveEdge: position.pixels <= 0.5,
        isScrolling: position.isScrollingNotifier.value,
      ),
    );
  }
}

TimelineAttachmentFacts _attachment(
  ThreadAttachmentView value, {
  String? source,
}) => TimelineAttachmentFacts(
  id: value.id,
  modality: value.modality.name,
  filename: value.filename ?? '',
  byteSize: value.byteSize,
  source: source,
);

TimelineItemFacts _itemFacts(TimelineMessagePayload payload) {
  final item = payload.item;
  final tool = item.tool;
  final input = tool?.userInput;
  final plan = ownsPlanConfirmation(tool?.name) ? input?.planReceipt : null;
  return TimelineItemFacts(
    id: item.id,
    ordinal: item.ordinal,
    revision: item.revision,
    saved: payload.saved,
    terminal: payload.terminal,
    omittedBytes: payload.omittedBytes,
    kind: item.kind.name,
    status: item.status,
    text: item.text,
    channel: switch (item.state) {
      ThreadTextItemStateView(:final channel) => channel,
      _ => null,
    },
    details: [
      for (final detail in payload.details)
        TimelineDetailFacts(
          field: StudioDriverKeyValues.timelineDetailField(detail.field),
          revision: detail.revision,
          totalBytes: detail.totalBytes,
          previewBytes: detail.previewBytes,
        ),
    ],
    attachments: [
      for (final value in item.attachments) _attachment(value),
      for (final value in tool?.attachments ?? const <ThreadAttachmentView>[])
        _attachment(value, source: 'tool'),
    ],
    tool: tool == null
        ? null
        : TimelineToolFacts(
            name: tool.name,
            status: item.status,
            callId: tool.callId ?? tool.toolCallId,
            arguments: tool.arguments,
            result: tool.result,
            progressBytes: utf8.encode(tool.result ?? '').length,
            itemRevision: item.revision,
            denialReason: tool.denialReason,
            workingDirectory: tool.workingDirectory,
            exitCode: tool.exitCode,
            attachments: [
              for (final value in tool.attachments) _attachment(value),
            ],
          ),
    userInput: input == null
        ? null
        : TimelineUserInputFacts(
            interactionId: input.interactionId,
            state: switch (input.state) {
              PendingThreadToolUserInputView() => 'pending',
              ResolvedThreadToolUserInputView() => 'resolved',
              CancelledThreadToolUserInputView() => 'cancelled',
            },
            isPlanConfirmation: plan != null,
            planDecision: plan?.decision.name,
          ),
  );
}
