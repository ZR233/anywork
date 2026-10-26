import 'package:anywork_client/updates_ports.dart';

import '../../../../rust/api/studio/products/read/updates.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../source_converters.dart';

UpdateSummaryRead updateSummaryReadFromBridge(
  native.BridgeUpdateSummaryRead value,
) => UpdateSummaryRead(
  version: readTextFromBridge(value.version),
  publishedAt: exactI64(
    BigInt.from(value.publishedAt),
    'update published Unix seconds',
  ),
  notesUrl: readTextFromBridge(value.notesUrl),
);

UpdateDetailsRead updateDetailsReadFromBridge(
  native.BridgeUpdateDetailsRead value,
) => UpdateDetailsRead(
  summary: updateSummaryReadFromBridge(value.summary),
  installer: UpdateAssetRead(
    url: readTextFromBridge(value.installer.url),
    size: exactU64(value.installer.size, 'update installer bytes'),
    sha256: readTextFromBridge(value.installer.sha256),
    signature: readTextFromBridge(value.installer.signature),
  ),
);

UpdatesReadHeader updatesReadHeaderFromBridge(
  native.BridgeUpdatesReadHeader value,
) => switch (value) {
  native.BridgeUpdatesReadHeader_Disabled(:final revision, :final updatedAt) =>
    UpdatesReadHeader.disabled(
      revision: exactU64(revision, 'updates business revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
    ),
  native.BridgeUpdatesReadHeader_Idle(:final revision, :final updatedAt) =>
    UpdatesReadHeader.idle(
      revision: exactU64(revision, 'updates business revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
    ),
  native.BridgeUpdatesReadHeader_Checking(
    :final revision,
    :final operationId,
    :final startedAt,
  ) =>
    UpdatesReadHeader.checking(
      revision: exactU64(revision, 'updates business revision'),
      operationId: readTextFromBridge(operationId),
      startedAt: exactI64(
        BigInt.from(startedAt),
        'updates started Unix seconds',
      ),
    ),
  native.BridgeUpdatesReadHeader_UpToDate(:final revision, :final checkedAt) =>
    UpdatesReadHeader.upToDate(
      revision: exactU64(revision, 'updates business revision'),
      checkedAt: exactI64(
        BigInt.from(checkedAt),
        'updates checked Unix seconds',
      ),
    ),
  native.BridgeUpdatesReadHeader_Available(
    :final revision,
    :final checkedAt,
    :final update,
  ) =>
    UpdatesReadHeader.available(
      revision: exactU64(revision, 'updates business revision'),
      checkedAt: exactI64(
        BigInt.from(checkedAt),
        'updates checked Unix seconds',
      ),
      update: updateDetailsReadFromBridge(update),
    ),
  native.BridgeUpdatesReadHeader_Downloading(
    :final revision,
    :final updatedAt,
    :final update,
    :final downloaded,
    :final total,
  ) =>
    UpdatesReadHeader.downloading(
      revision: exactU64(revision, 'updates business revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
      update: updateDetailsReadFromBridge(update),
      downloaded: exactU64(downloaded, 'update downloaded bytes'),
      total: exactU64(total, 'update total bytes'),
    ),
  native.BridgeUpdatesReadHeader_Verifying(
    :final revision,
    :final updatedAt,
    :final update,
    :final downloaded,
    :final total,
  ) =>
    UpdatesReadHeader.verifying(
      revision: exactU64(revision, 'updates business revision'),
      updatedAt: exactI64(
        BigInt.from(updatedAt),
        'updates updated Unix seconds',
      ),
      update: updateDetailsReadFromBridge(update),
      downloaded: exactU64(downloaded, 'update downloaded bytes'),
      total: exactU64(total, 'update total bytes'),
    ),
  native.BridgeUpdatesReadHeader_Ready(
    :final revision,
    :final readyAt,
    :final update,
  ) =>
    UpdatesReadHeader.ready(
      revision: exactU64(revision, 'updates business revision'),
      readyAt: exactI64(BigInt.from(readyAt), 'updates ready Unix seconds'),
      update: updateDetailsReadFromBridge(update),
    ),
  native.BridgeUpdatesReadHeader_InstallerLaunched(
    :final revision,
    :final launchedAt,
    :final update,
  ) =>
    UpdatesReadHeader.installerLaunched(
      revision: exactU64(revision, 'updates business revision'),
      launchedAt: exactI64(
        BigInt.from(launchedAt),
        'installer launched Unix seconds',
      ),
      update: updateDetailsReadFromBridge(update),
    ),
  native.BridgeUpdatesReadHeader_CheckFailed(
    :final revision,
    :final failedAt,
    :final error,
  ) =>
    UpdatesReadHeader.checkFailed(
      revision: exactU64(revision, 'updates business revision'),
      failedAt: exactI64(BigInt.from(failedAt), 'update failure Unix seconds'),
      error: sourceErrorReadFromBridge(error),
    ),
  native.BridgeUpdatesReadHeader_InstallFailed(
    :final revision,
    :final failedAt,
    :final update,
    :final error,
  ) =>
    UpdatesReadHeader.installFailed(
      revision: exactU64(revision, 'updates business revision'),
      failedAt: exactI64(BigInt.from(failedAt), 'update failure Unix seconds'),
      update: updateDetailsReadFromBridge(update),
      error: sourceErrorReadFromBridge(error),
    ),
};
