import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

import '../../../rust/api/studio/types/shutdown.dart' as native;
import '../shared/exact_numbers.dart';
import '../shared/shutdown_issue_converters.dart';

StudioExitReport exitReportFromBridge(native.BridgeExitReport value) =>
    StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: switch (value.shutdown.outcome) {
          native.BridgeShutdownOutcome.notStarted => ShutdownOutcome.notStarted,
          native.BridgeShutdownOutcome.clean => ShutdownOutcome.clean,
          native.BridgeShutdownOutcome.degraded => ShutdownOutcome.degraded,
        },
        issues: List.unmodifiable([
          for (final issue in value.shutdown.issues) shutdownIssueFromBridge(issue),
        ]),
        persistence: switch (value.shutdown.persistence) {
          native.BridgePendingPersistence_Unknown() =>
            const PendingPersistence.unknown(),
          native.BridgePendingPersistence_Pending(:final count) =>
            PendingPersistence.pending(count: exactU64(count, 'pending persistence count')),
          native.BridgePendingPersistence_Drained() =>
            const PendingPersistence.drained(),
        },
      ),
      updateHandoff: switch (value.updateHandoff) {
        native.BridgeUpdateHandoff_NotRequested() => const UpdateHandoff.notRequested(),
        native.BridgeUpdateHandoff_Launched(:final version) =>
          UpdateHandoff.launched(version: version),
        native.BridgeUpdateHandoff_Failed(:final error) =>
          UpdateHandoff.failed(error: SourceStateError(
            code: error.code,
            message: error.message,
            retryable: error.retryable,
          )),
      },
    );
