import 'package:flutter/widgets.dart';

typedef TimelineFileDownloadStart = TimelineFileDownload Function({
  required String itemId,
  required int index,
  required String destination,
});

abstract interface class TimelineFileDownload {
  /// Single-subscription stream of cumulative bytes written.
  Stream<int> get progress;

  /// Completes successfully after the final file has been committed. Failure
  /// and early termination complete with an error.
  Future<void> get finished;

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

class TimelineFileDownloadScope extends InheritedWidget {
  const TimelineFileDownloadScope({
    super.key,
    required this.start,
    this.pickSavePath,
    required super.child,
  });

  final TimelineFileDownloadStart start;

  /// Preview and widget-test substitute for the native save dialog.
  final Future<String?> Function(String filename)? pickSavePath;

  static TimelineFileDownloadScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TimelineFileDownloadScope>();

  @override
  bool updateShouldNotify(TimelineFileDownloadScope oldWidget) =>
      start != oldWidget.start || pickSavePath != oldWidget.pickSavePath;
}
