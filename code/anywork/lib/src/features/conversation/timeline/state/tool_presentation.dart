import 'package:anywork_client/models.dart';

/// A single decoded current-contract tool card, owned by one Message.metadata.
/// No history ordering, grouping or synthetic timestamps live in this value.
final class TimelineToolPresentation {
  const TimelineToolPresentation({
    required this.id,
    required this.toolCallId,
    required this.name,
    required this.presentationContract,
    required this.statusString,
    required this.arguments,
    required this.output,
    this.createdAt,
    this.completedAt,
    this.error,
    this.taskId,
    this.workingDirectory,
    this.exitCode,
    this.timedOut = false,
    this.attachments = const [],
    this.outputArtifacts = const [],
    this.wait,
    this.executionPresent = true,
    this.frozenObservation = false,
  });
  final String id;
  final String toolCallId;
  final String name;
  final String presentationContract;
  final String statusString;
  final String arguments;
  final String output;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String? error;
  final String? taskId;
  final String? workingDirectory;
  final int? exitCode;
  final bool timedOut;
  final List<ThreadAttachmentView> attachments;
  final List<String> outputArtifacts;
  final ThreadWaitPresentationView? wait;
  final bool executionPresent;
  final bool frozenObservation;
  TimelineToolOutcome? get outcome => switch (statusString) {
    'succeeded' => TimelineToolOutcome.succeeded,
    'failed' => TimelineToolOutcome.failed,
    'denied' => TimelineToolOutcome.rejected,
    'cancelled' => TimelineToolOutcome.cancelled,
    'interrupted' => TimelineToolOutcome.interrupted,
    _ => null,
  };
}

enum TimelineToolOutcome { succeeded, failed, rejected, cancelled, interrupted }
