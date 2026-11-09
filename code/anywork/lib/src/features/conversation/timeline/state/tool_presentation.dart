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

/// Only markers whose existing card parsers are implemented here. Tools without
/// a specialized parser intentionally stay generic, even if their names look
/// familiar. No prefix matching or old contract aliases.
const specializedToolContracts = {
  'builtin.exec@2',
  'builtin.write_stdin@1',
  'builtin.read_session_note@1',
  'builtin.search_session_note@1',
  'builtin.write_session_note@1',
  'builtin.apply_session_note_patch@1',
  'builtin.stat_path@1',
  'builtin.write_file@1',
  'builtin.apply_patch@1',
  'builtin.create_directory@1',
  'builtin.delete_path@1',
  'builtin.copy_path@1',
  'builtin.move_path@1',
  'builtin.spawn_agent@1',
  'builtin.send_message@1',
  'builtin.wait@1',
  'builtin.sleep@1',
  'builtin.view_image@1',
  'builtin.lsp_query@1',
  'builtin.lsp_capabilities@1',
  'builtin.plan_current@1',
  'builtin.plan_next@1',
  'builtin.plan_history@1',
  'builtin.plan_submit@1',
  'builtin.plan_restart@1',
  'builtin.workflow_current@1',
  'builtin.workflow_next@1',
  'builtin.workflow_graph@1',
  'builtin.workflow_history@1',
  'builtin.workflow_transition@1',
  'builtin.workflow_restart@1',
  'builtin.web_search@1',
  'builtin.deepseek_web_search@1',
  'builtin.deepseek_web_fetch@1',
};
