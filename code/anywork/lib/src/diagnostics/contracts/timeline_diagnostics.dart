import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import 'timeline_item_diagnostics.dart';

export 'timeline_item_diagnostics.dart';

/// A borrowed, synchronous read of this application's actual display owner.
///
/// U2 implements this capability at its public presentation adapter; U3 injects
/// that instance. Capturing does not register a consumer/observer, issue queries,
/// open a Session, change demand, or retain a second content/geometry mirror.
/// The caller serializes and releases the returned values in the same request.
abstract interface class TimelineDiagnosticsSource {
  TimelineDiagnosticsSnapshot capture();
}

/// Only the existing `timeline` and `timelineScroll` Driver whitelist.
///
/// No active display state means both fields are null. A current connection
/// failure before the first display still has [timeline] (ready=false), with the
/// four error scalars captured from that same current error. The Studio query
/// must reject a timeline whose threadId differs from its selected Thread;
/// matching a String ID never authorizes looking up or creating another owner.
final class TimelineDiagnosticsSnapshot {
  const TimelineDiagnosticsSnapshot({
    required this.timeline,
    required this.timelineScroll,
  });

  final TimelineDisplayFacts? timeline;
  final TimelineScrollDiagnostic? timelineScroll;
}

/// Request-local facts from the actual current display and bounded payloads.
///
/// `mode` is the existing wire token `live` or `history`, obtained from the
/// presentation mode's name, not a replacement canonical mode enum. Connection
/// and channel remain their existing typed domain values. Items are the already
/// admitted previews: never read a detail field to populate this snapshot.
final class TimelineDisplayFacts {
  TimelineDisplayFacts({
    required this.threadId,
    required this.generation,
    required this.ready,
    required this.mode,
    required this.connection,
    required this.connectionErrorType,
    required this.connectionErrorCode,
    required this.connectionErrorRetryable,
    required this.connectionErrorCorrelationId,
    required this.appliedVersion,
    required this.olderCursor,
    required this.hasOlder,
    required this.loadingOlder,
    required this.olderError,
    required this.olderErrorCode,
    required this.hasNewOutput,
    required this.preparingLive,
    required List<TimelineItemFacts> items,
    required List<TimelinePresentationFacts> presentationItems,
  }) : items = List.unmodifiable(items),
       presentationItems = List.unmodifiable(presentationItems);

  final String threadId;
  final int generation;
  final bool ready;
  final String mode;
  final TimelineConnectionPhase connection;

  /// Null error -> four nulls. Otherwise type is runtimeType.toString() only;
  /// code/retryable/correlationId are taken only from an actual StudioFailure.
  /// Never call error.toString(), copy message/details/stack, infer a code, or
  /// retain a previous connection's error. In particular false is not null.
  final String? connectionErrorType;
  final StudioFailureCode? connectionErrorCode;
  final bool? connectionErrorRetryable;
  final String? connectionErrorCorrelationId;
  final int? appliedVersion;
  final String? olderCursor;
  final bool hasOlder;
  final bool loadingOlder;

  /// Error presence uses a safe runtime-type token, never exception prose.
  /// The existing olderErrorCode independently retains its typed classification.
  final String? olderError;
  final StudioFailureCode? olderErrorCode;
  final bool hasNewOutput;
  final bool preparingLive;
  final List<TimelineItemFacts> items;
  final List<TimelinePresentationFacts> presentationItems;
}

/// The current mounted standard ScrollPosition, read during capture().
///
/// No display/retired display -> null in the outer snapshot. A display without
/// layout has null geometry. The booleans describe actual current geometry,
/// never a notification cache; atLiveEdge does not imply Live display mode.
final class TimelineScrollDiagnostic {
  const TimelineScrollDiagnostic({
    required this.threadId,
    required this.generation,
    required this.pixels,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.viewportDimension,
    required this.extentBefore,
    required this.extentAfter,
    required this.atLiveEdge,
    required this.isScrolling,
  });

  final String? threadId;
  final int generation;
  final double? pixels;
  final double? minScrollExtent;
  final double? maxScrollExtent;
  final double? viewportDimension;
  final double? extentBefore;
  final double? extentAfter;
  final bool atLiveEdge;
  final bool isScrolling;
}
