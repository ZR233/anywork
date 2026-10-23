import 'contracts/timeline_diagnostics.dart';

/// The existing Driver wire whitelist. No generic DTO serialization, owner
/// lookup, retained snapshot or fallback for missing canonical facts.
extension TimelineDiagnosticsJson on TimelineDiagnosticsSnapshot {
  Map<String, Object?> toJson() => {
    'timeline': timeline?.toJson(),
    'timelineScroll': timelineScroll?.toJson(),
  };
}

extension TimelineDisplayFactsJson on TimelineDisplayFacts {
  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'generation': generation,
    'ready': ready,
    'mode': mode,
    'connection': connection.name,
    'connectionErrorType': connectionErrorType,
    'connectionErrorCode': connectionErrorCode?.name,
    'connectionErrorRetryable': connectionErrorRetryable,
    'connectionErrorCorrelationId': connectionErrorCorrelationId,
    'appliedVersion': appliedVersion,
    'itemCount': items.length,
    'itemIds': [for (final item in items) item.id],
    'presentationItemCount': presentationItems.length,
    'presentationItems': [
      for (final item in presentationItems)
        {
          'id': item.id,
          'kind': item.kind,
          'ordinal': item.ordinal,
          'memberIds': item.memberIds,
          'visibleMemberIds': item.visibleMemberIds,
          'skillPairs': item.skillPairs,
          'expanded': item.expanded,
          'activeCount': item.activeCount,
          'issueCount': item.issueCount,
        },
    ],
    'olderCursor': olderCursor,
    'hasOlder': hasOlder,
    'loadingOlder': loadingOlder,
    'olderError': olderError,
    'olderErrorCode': olderErrorCode?.name,
    'hasNewOutput': hasNewOutput,
    'preparingLive': preparingLive,
    'items': [for (final item in items) item.toJson()],
  };
}

extension TimelineItemFactsJson on TimelineItemFacts {
  Map<String, Object?> toJson() => {
    'id': id,
    'ordinal': ordinal,
    'revision': revision,
    'saved': saved,
    'terminal': terminal,
    'omittedBytes': omittedBytes,
    'kind': kind,
    'status': status,
    'text': text,
    'channel': channel?.name,
    'details': [
      for (final detail in details)
        {
          'field': detail.field,
          'revision': detail.revision,
          'totalBytes': detail.totalBytes,
          'previewBytes': detail.previewBytes,
        },
    ],
    'attachments': [for (final attachment in attachments) attachment.toJson()],
    if (tool case final tool?) 'tool': tool.toJson(),
    if (userInput case final userInput?)
      'userInput': {
        'interactionId': userInput.interactionId,
        'state': userInput.state,
        'isPlanConfirmation': userInput.isPlanConfirmation,
        'planDecision': userInput.planDecision,
      },
  };
}

extension TimelineToolFactsJson on TimelineToolFacts {
  Map<String, Object?> toJson() => {
    'name': name,
    'status': status,
    'callId': callId,
    'arguments': arguments,
    'result': result,
    // Existing sampling field for the same bounded preview, not another body.
    'output': result,
    'progressBytes': progressBytes,
    'itemRevision': itemRevision,
    'denialReason': denialReason,
    'workingDirectory': workingDirectory,
    'exitCode': exitCode,
    'attachments': [
      for (final attachment in attachments)
        {
          'id': attachment.id,
          'modality': attachment.modality,
          'filename': attachment.filename,
          'byteSize': attachment.byteSize,
        },
    ],
  };
}

extension TimelineAttachmentFactsJson on TimelineAttachmentFacts {
  Map<String, Object?> toJson() => {
    'id': id,
    'modality': modality,
    'filename': filename,
    'byteSize': byteSize,
    if (source != null) 'source': source,
  };
}

extension TimelineScrollDiagnosticJson on TimelineScrollDiagnostic {
  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'generation': generation,
    'pixels': pixels,
    'minScrollExtent': minScrollExtent,
    'maxScrollExtent': maxScrollExtent,
    'viewportDimension': viewportDimension,
    'extentBefore': extentBefore,
    'extentAfter': extentAfter,
    'atLiveEdge': atLiveEdge,
    'isScrolling': isScrolling,
  };
}
