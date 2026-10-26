import 'package:freezed_annotation/freezed_annotation.dart';

part 'remote_values.freezed.dart';

/// Secrets are command inputs only; never serialize or print this value.
@Freezed(toStringOverride: false)
sealed class SshPasswordUpdate with _$SshPasswordUpdate {
  const factory SshPasswordUpdate.preserve() = PreserveSshPasswordUpdate;
  const factory SshPasswordUpdate.replace({required String value}) =
      ReplaceSshPasswordUpdate;
  const factory SshPasswordUpdate.clear() = ClearSshPasswordUpdate;
}

@Freezed(toStringOverride: false)
abstract class SshServerProfile with _$SshServerProfile {
  const factory SshServerProfile({
    required String alias,
    required String hostName,
    required int port,
    required String username,
    required String? identityFile,
  }) = _SshServerProfile;
}

@Freezed(toStringOverride: false)
abstract class SshServerRuntimeEntry with _$SshServerRuntimeEntry {
  const factory SshServerRuntimeEntry({
    required SshServerProfile profile,
    required bool managed,
    required bool hasPassword,
  }) = _SshServerRuntimeEntry;
}

@Freezed(toStringOverride: false)
sealed class SshConnectionState with _$SshConnectionState {
  const factory SshConnectionState.disconnected() =
      DisconnectedSshConnectionState;
  const factory SshConnectionState.connecting() = ConnectingSshConnectionState;
  const factory SshConnectionState.ready({
    required String helperVersion,
    required String architecture,
  }) = ReadySshConnectionState;
  const factory SshConnectionState.reconnecting({
    required int attempt,
    required int delaySeconds,
  }) = ReconnectingSshConnectionState;
  const factory SshConnectionState.failed({
    required String code,
    required String message,
  }) = FailedSshConnectionState;
}

@Freezed(toStringOverride: false)
abstract class SshConnectionSnapshot with _$SshConnectionSnapshot {
  const factory SshConnectionSnapshot({
    required String alias,
    required SshConnectionState state,
  }) = _SshConnectionSnapshot;
}

@Freezed(toStringOverride: false)
abstract class RemoteDirectoryEntry with _$RemoteDirectoryEntry {
  const factory RemoteDirectoryEntry({
    required String name,
    required String path,
    required bool isDirectory,
    required bool isSymlink,
  }) = _RemoteDirectoryEntry;
}

/// One native v9 page. nextCursor is the only continuation authority.
@Freezed(toStringOverride: false)
abstract class RemoteDirectoryListing with _$RemoteDirectoryListing {
  const factory RemoteDirectoryListing({
    required String path,
    required String? parent,
    required List<RemoteDirectoryEntry> entries,
    required String? nextCursor,
  }) = _RemoteDirectoryListing;
}
