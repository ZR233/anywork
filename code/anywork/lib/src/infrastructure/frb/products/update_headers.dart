import 'package:anywork_client/updates.dart';

import '../../../rust/api/studio/products/feed/updates.dart' as native;
import '../shared/exact_numbers.dart';
import 'update_references.dart';

UpdatesBrief updatesBriefFromBridge(
  native.BridgeUpdatesBrief value,
) => switch (value) {
  native.BridgeUpdatesBrief_Disabled(:final revision, :final updatedAt) =>
    UpdatesBrief.disabled(
      revision: exactU64(revision, 'updates revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
    ),
  native.BridgeUpdatesBrief_Idle(:final revision, :final updatedAt) =>
    UpdatesBrief.idle(
      revision: exactU64(revision, 'updates revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
    ),
  native.BridgeUpdatesBrief_Checking(:final revision, :final startedAt) =>
    UpdatesBrief.checking(
      revision: exactU64(revision, 'updates revision'),
      startedAt: exactI64(
        BigInt.from(startedAt),
        'updates started Unix seconds',
      ),
    ),
  native.BridgeUpdatesBrief_UpToDate(:final revision, :final checkedAt) =>
    UpdatesBrief.upToDate(
      revision: exactU64(revision, 'updates revision'),
      checkedAt: exactI64(
        BigInt.from(checkedAt),
        'updates checked Unix seconds',
      ),
    ),
  native.BridgeUpdatesBrief_Available(:final revision, :final checkedAt) =>
    UpdatesBrief.available(
      revision: exactU64(revision, 'updates revision'),
      checkedAt: exactI64(
        BigInt.from(checkedAt),
        'updates checked Unix seconds',
      ),
    ),
  native.BridgeUpdatesBrief_Downloading(
    :final revision,
    :final updatedAt,
    :final downloaded,
    :final total,
  ) =>
    UpdatesBrief.downloading(
      revision: exactU64(revision, 'updates revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
      downloaded: exactU64(downloaded, 'update downloaded bytes'),
      total: exactU64(total, 'update total bytes'),
    ),
  native.BridgeUpdatesBrief_Verifying(
    :final revision,
    :final updatedAt,
    :final downloaded,
    :final total,
  ) =>
    UpdatesBrief.verifying(
      revision: exactU64(revision, 'updates revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
      downloaded: exactU64(downloaded, 'update downloaded bytes'),
      total: exactU64(total, 'update total bytes'),
    ),
  native.BridgeUpdatesBrief_Ready(:final revision, :final readyAt) =>
    UpdatesBrief.ready(
      revision: exactU64(revision, 'updates revision'),
      readyAt: exactI64(BigInt.from(readyAt), 'updates ready Unix seconds'),
    ),
  native.BridgeUpdatesBrief_InstallerLaunched(
    :final revision,
    :final launchedAt,
  ) =>
    UpdatesBrief.installerLaunched(
      revision: exactU64(revision, 'updates revision'),
      launchedAt: exactI64(
        BigInt.from(launchedAt),
        'installer launched Unix seconds',
      ),
    ),
  native.BridgeUpdatesBrief_CheckFailed(
    :final revision,
    :final failedAt,
    :final retryable,
  ) =>
    UpdatesBrief.checkFailed(
      revision: exactU64(revision, 'updates revision'),
      failedAt: exactI64(BigInt.from(failedAt), 'update failure Unix seconds'),
      retryable: retryable,
    ),
  native.BridgeUpdatesBrief_InstallFailed(
    :final revision,
    :final failedAt,
    :final retryable,
  ) =>
    UpdatesBrief.installFailed(
      revision: exactU64(revision, 'updates revision'),
      failedAt: exactI64(BigInt.from(failedAt), 'update failure Unix seconds'),
      retryable: retryable,
    ),
};

UpdatesHeader updatesHeaderFromBridge(native.BridgeUpdatesHeader value) =>
    UpdatesHeader(
      reference: updatesReadRefFromBridge(value.reference),
      brief: updatesBriefFromBridge(value.brief),
      summary: value.summary == null
          ? null
          : updateSummaryRefFromBridge(value.summary!),
      operation: value.operation == null
          ? null
          : updateOperationRefFromBridge(value.operation!),
      error: value.error == null
          ? null
          : updateErrorRefFromBridge(value.error!),
      details: value.details == null
          ? null
          : updateDetailsRefFromBridge(value.details!),
    );
