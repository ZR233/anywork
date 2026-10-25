import 'package:anywork_client/resources_ports.dart';

import '../domain/update_values.dart';
import '../domain/updates_state.dart';
import 'updates_port.dart';
import 'updates_reads.dart';

typedef UpdateTextRead = Future<TextChunk> Function(int fieldId, int offset);

Future<UpdateSummary> readUpdateSummary(
  UpdateSummaryRead value,
  UpdateTextRead read,
) async => UpdateSummary(
  version: await materializeReadText(value.version, read: read),
  publishedAt: value.publishedAt,
  notesUrl: await materializeReadText(value.notesUrl, read: read),
);

Future<SourceStateError> readUpdateError(
  SourceStateErrorRead value,
  UpdateTextRead read,
) async => SourceStateError(
  code: await materializeReadText(value.code, read: read),
  message: await materializeReadText(value.message, read: read),
  retryable: value.retryable,
);

Future<UpdateDetails> readUpdateDetails(
  UpdateDetailsRead value,
  UpdateTextRead read,
) async {
  if (value.installer.size < 0)
    throw resourceProtocol('The original installer size is negative.');
  return UpdateDetails(
    summary: await readUpdateSummary(value.summary, read),
    installer: UpdateAsset(
      url: await materializeReadText(value.installer.url, read: read),
      size: value.installer.size,
      sha256: await materializeReadText(value.installer.sha256, read: read),
      signature: await materializeReadText(
        value.installer.signature,
        read: read,
      ),
    ),
  );
}

void validateUpdatesBrief(UpdatesBrief value) {
  if (value.revision < 0)
    throw resourceProtocol(
      'The original Updates business revision is negative.',
    );
  switch (value) {
    case DownloadingUpdatesBrief(:final downloaded, :final total) ||
        VerifyingUpdatesBrief(:final downloaded, :final total):
      if (downloaded < 0 || total < downloaded)
        throw resourceProtocol('Updates byte progress is invalid.');
    default:
      break;
  }
}

UpdatesBrief updatesReadBrief(UpdatesReadHeader value) => switch (value) {
  DisabledUpdatesReadHeader(:final revision, :final updatedAt) =>
    UpdatesBrief.disabled(revision: revision, updatedAt: updatedAt),
  IdleUpdatesReadHeader(:final revision, :final updatedAt) => UpdatesBrief.idle(
    revision: revision,
    updatedAt: updatedAt,
  ),
  CheckingUpdatesReadHeader(:final revision, :final startedAt) =>
    UpdatesBrief.checking(revision: revision, startedAt: startedAt),
  UpToDateUpdatesReadHeader(:final revision, :final checkedAt) =>
    UpdatesBrief.upToDate(revision: revision, checkedAt: checkedAt),
  AvailableUpdatesReadHeader(:final revision, :final checkedAt) =>
    UpdatesBrief.available(revision: revision, checkedAt: checkedAt),
  DownloadingUpdatesReadHeader(
    :final revision,
    :final updatedAt,
    :final downloaded,
    :final total,
  ) =>
    UpdatesBrief.downloading(
      revision: revision,
      updatedAt: updatedAt,
      downloaded: downloaded,
      total: total,
    ),
  VerifyingUpdatesReadHeader(
    :final revision,
    :final updatedAt,
    :final downloaded,
    :final total,
  ) =>
    UpdatesBrief.verifying(
      revision: revision,
      updatedAt: updatedAt,
      downloaded: downloaded,
      total: total,
    ),
  ReadyUpdatesReadHeader(:final revision, :final readyAt) => UpdatesBrief.ready(
    revision: revision,
    readyAt: readyAt,
  ),
  InstallerLaunchedUpdatesReadHeader(:final revision, :final launchedAt) =>
    UpdatesBrief.installerLaunched(revision: revision, launchedAt: launchedAt),
  CheckFailedUpdatesReadHeader(
    :final revision,
    :final failedAt,
    :final error,
  ) =>
    UpdatesBrief.checkFailed(
      revision: revision,
      failedAt: failedAt,
      retryable: error.retryable,
    ),
  InstallFailedUpdatesReadHeader(
    :final revision,
    :final failedAt,
    :final error,
  ) =>
    UpdatesBrief.installFailed(
      revision: revision,
      failedAt: failedAt,
      retryable: error.retryable,
    ),
};

/// Stable typed subfields can be combined with later canonical progress only
/// after the mirror has verified their original origin and exact field refs.
UpdatesValue? updatesFromBrief(
  UpdatesBrief value, {
  UpdateSummary? summary,
  String? operationId,
  SourceStateError? error,
}) {
  switch (value) {
    case CheckFailedUpdatesBrief(:final retryable) ||
        InstallFailedUpdatesBrief(:final retryable):
      if (error != null && error.retryable != retryable) {
        throw resourceProtocol(
          'Updates error retryability disagrees with its original brief.',
        );
      }
    default:
      break;
  }
  return switch (value) {
    DisabledUpdatesBrief(:final revision, :final updatedAt) =>
      UpdatesValue.disabled(revision: revision, updatedAt: updatedAt),
    IdleUpdatesBrief(:final revision, :final updatedAt) => UpdatesValue.idle(
      revision: revision,
      updatedAt: updatedAt,
    ),
    CheckingUpdatesBrief(:final revision, :final startedAt) =>
      operationId == null
          ? null
          : UpdatesValue.checking(
              revision: revision,
              startedAt: startedAt,
              operationId: operationId,
            ),
    UpToDateUpdatesBrief(:final revision, :final checkedAt) =>
      UpdatesValue.upToDate(revision: revision, checkedAt: checkedAt),
    AvailableUpdatesBrief(:final revision, :final checkedAt) =>
      summary == null
          ? null
          : UpdatesValue.available(
              revision: revision,
              checkedAt: checkedAt,
              update: summary,
            ),
    DownloadingUpdatesBrief(
      :final revision,
      :final updatedAt,
      :final downloaded,
      :final total,
    ) =>
      summary == null
          ? null
          : UpdatesValue.downloading(
              revision: revision,
              updatedAt: updatedAt,
              downloaded: downloaded,
              total: total,
              update: summary,
            ),
    VerifyingUpdatesBrief(
      :final revision,
      :final updatedAt,
      :final downloaded,
      :final total,
    ) =>
      summary == null
          ? null
          : UpdatesValue.verifying(
              revision: revision,
              updatedAt: updatedAt,
              downloaded: downloaded,
              total: total,
              update: summary,
            ),
    ReadyUpdatesBrief(:final revision, :final readyAt) =>
      summary == null
          ? null
          : UpdatesValue.ready(
              revision: revision,
              readyAt: readyAt,
              update: summary,
            ),
    InstallerLaunchedUpdatesBrief(:final revision, :final launchedAt) =>
      summary == null
          ? null
          : UpdatesValue.installerLaunched(
              revision: revision,
              launchedAt: launchedAt,
              update: summary,
            ),
    CheckFailedUpdatesBrief(:final revision, :final failedAt) =>
      error == null
          ? null
          : UpdatesValue.checkFailed(
              revision: revision,
              failedAt: failedAt,
              error: error,
            ),
    InstallFailedUpdatesBrief(:final revision, :final failedAt) =>
      summary == null || error == null
          ? null
          : UpdatesValue.installFailed(
              revision: revision,
              failedAt: failedAt,
              update: summary,
              error: error,
            ),
  };
}

Future<UpdatesValue> readUpdatesValue(
  UpdatesReadConnection scope, {
  UpdatesHeader? expected,
}) async {
  final value = await scope.header();
  final brief = updatesReadBrief(value);
  validateUpdatesBrief(brief);
  if (expected != null && brief != expected.brief) {
    throw resourceProtocol('Updates value changed its original header.');
  }
  final read = (int field, int offset) =>
      scope.text(field, offset: offset, maxBytes: 65536);
  final summary = switch (value) {
    AvailableUpdatesReadHeader(:final update) ||
    DownloadingUpdatesReadHeader(:final update) ||
    VerifyingUpdatesReadHeader(:final update) ||
    ReadyUpdatesReadHeader(:final update) ||
    InstallerLaunchedUpdatesReadHeader(:final update) ||
    InstallFailedUpdatesReadHeader(
      :final update,
    ) => await readUpdateSummary(update.summary, read),
    _ => null,
  };
  final operation = value is CheckingUpdatesReadHeader
      ? await materializeReadText(value.operationId, read: read)
      : null;
  final error = switch (value) {
    CheckFailedUpdatesReadHeader(:final error) ||
    InstallFailedUpdatesReadHeader(
      :final error,
    ) => await readUpdateError(error, read),
    _ => null,
  };
  // Installer fields are deliberately untouched here: loadDetails alone asks
  // for that separate capability. CheckFailed never requests a summary scope.
  return updatesFromBrief(
    brief,
    summary: summary,
    operationId: operation,
    error: error,
  )!;
}

UpdateSummary? updatesSummary(UpdatesValue value) => switch (value) {
  AvailableUpdatesValue(:final update) ||
  DownloadingUpdatesValue(:final update) ||
  VerifyingUpdatesValue(:final update) ||
  ReadyUpdatesValue(:final update) ||
  InstallerLaunchedUpdatesValue(:final update) ||
  InstallFailedUpdatesValue(:final update) => update,
  _ => null,
};

SourceStateError? updatesError(UpdatesValue value) => switch (value) {
  CheckFailedUpdatesValue(:final error) ||
  InstallFailedUpdatesValue(:final error) => error,
  _ => null,
};
