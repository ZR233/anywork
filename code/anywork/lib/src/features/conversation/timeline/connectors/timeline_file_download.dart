import 'package:flutter/widgets.dart';

import '../../../../domain/timeline_file_download.dart';

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
