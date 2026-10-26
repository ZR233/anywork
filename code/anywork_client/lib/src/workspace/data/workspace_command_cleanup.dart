import 'dart:async';

import 'package:anywork_client/resources.dart';

import '../domain/selection.dart';

/// Extra responsibilities retained by the original Workspace command, never a
/// second pending-operation registry or an application shutdown coordinator.
abstract interface class WorkspaceCommandCleanup {
  Future<CloseReport> finish({required bool confirmed, required bool unknown});
  Future<CloseReport> close({DateTime? deadline, bool retry = false});
  CloseReport get report;
  bool holdsRemoval(WorkspaceState state);
}

/// Observe the original work under the caller's unchanged absolute deadline.
Future<bool> waitWorkspaceCompletion(
  Future<void> work,
  DateTime? deadline,
) async {
  var complete = false;
  final settled = work.then<void>((_) {
    complete = true;
  });
  if (deadline == null) {
    await settled;
    return true;
  }
  final alarm = Completer<void>();
  final remaining = deadline.difference(DateTime.now());
  final timer = Timer(
    remaining.isNegative ? Duration.zero : remaining,
    alarm.complete,
  );
  try {
    await Future.any([settled, alarm.future]);
  } finally {
    timer.cancel();
  }
  return complete;
}
