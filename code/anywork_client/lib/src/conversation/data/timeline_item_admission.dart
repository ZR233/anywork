import '../../../resources.dart';
import '../domain/thread_content.dart';
import '../domain/timeline_models.dart';

/// Bounded continuity metadata only; no body, shell or field text is retained.
typedef TimelineMemberIdentity = ({int ordinal, int revision, Type stateType});

TimelineMemberIdentity admitTimelineItem(
  String threadId,
  StudioTimelineItem item, {
  TimelineMemberIdentity? previous,
}) {
  final value = item.item;
  if (value.threadId != threadId ||
      value.ordinal < 0 ||
      value.revision < 0 ||
      item.omittedBytes < 0) {
    throw _protocol(
      'A Timeline item does not belong to its original Thread or has invalid metadata.',
    );
  }
  if (previous != null &&
      (value.ordinal != previous.ordinal ||
          value.state.runtimeType != previous.stateType ||
          value.revision < previous.revision)) {
    throw _protocol(
      'An authoritative item changed stable identity or regressed its revision.',
    );
  }
  for (final detail in item.details) {
    if (detail.revision != value.revision ||
        !_validLengths(detail.totalBytes, detail.previewBytes)) {
      throw _protocol(
        'A Timeline detail does not belong to its item revision.',
      );
    }
  }
  return (
    ordinal: value.ordinal,
    revision: value.revision,
    stateType: value.state.runtimeType,
  );
}

TimelineMemberIdentity admitTimelineItemUpdate(
  String threadId,
  StudioTimelineUpdateItem change,
  TimelineMemberIdentity? previous,
) {
  if (previous == null ||
      previous.revision != change.expectedRevision ||
      change.revision < change.expectedRevision ||
      change.omittedBytes < 0) {
    throw _protocol('An item update is not continuous.');
  }
  final shell = change.itemShell;
  if (shell != null &&
      (shell.id != change.itemId ||
          shell.threadId != threadId ||
          shell.ordinal != previous.ordinal ||
          shell.revision != change.revision ||
          shell.state.runtimeType != previous.stateType)) {
    throw _protocol(
      'An item shell changed its original identity, order or target revision.',
    );
  }
  for (final field in change.fields) {
    if (!_validLengths(field.totalBytes, field.previewBytes)) {
      throw _protocol('A Timeline field has invalid preview lengths.');
    }
    if (field.field is ThreadToolOutputArtifactsFieldView &&
        field.change is! RemoveThreadFieldChangeView) {
      final hasOutput = switch (shell?.state) {
        ThreadToolItemStateView(lifecycle: SucceededThreadToolView()) => true,
        ThreadToolItemStateView(
          lifecycle: FailedThreadToolView(:final output),
        ) =>
          output != null,
        _ => false,
      };
      if (!hasOutput)
        throw _protocol(
          'An artifact update requires its same-revision typed output shell.',
        );
    }
  }
  return (
    ordinal: previous.ordinal,
    revision: change.revision,
    stateType: previous.stateType,
  );
}

bool _validLengths(int total, int preview) =>
    total >= 0 && preview >= 0 && preview <= total;

StudioFailure _protocol(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: 'timeline-continuity',
);
