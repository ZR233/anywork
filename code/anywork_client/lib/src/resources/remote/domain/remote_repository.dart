import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'remote_values.dart';

part 'remote_repository.freezed.dart';

/// Explicit command results only, not a made-up Product source revision.
@Freezed(toStringOverride: false)
abstract class RemoteState with _$RemoteState {
  const factory RemoteState({
    required List<SshServerRuntimeEntry>? servers,
    required Map<String, SshConnectionSnapshot> connections,
  }) = _RemoteState;
}

@Freezed(toStringOverride: false)
abstract class RemoteDirectoryState with _$RemoteDirectoryState {
  const factory RemoteDirectoryState({
    required String alias,
    required String path,
    required String? parent,
    required List<RemoteDirectoryEntry> entries,
    required String? nextCursor,
    required bool loading,
    required StudioFailure? error,
  }) = _RemoteDirectoryState;
}

abstract interface class RemoteRepository {
  ReadonlyLatestValue<RemoteState> get state;
  OperationTicket<List<SshServerRuntimeEntry>> reloadServers();
  OperationTicket<SshServerRuntimeEntry> save(
    SshServerProfile profile,
    SshPasswordUpdate password,
  );
  OperationTicket<Unit> delete(String alias);
  OperationTicket<SshConnectionSnapshot> authenticate(
    String alias,
    String password, {
    required bool rememberPassword,
  });
  OperationTicket<SshConnectionSnapshot> test(String alias);
  OperationTicket<SshConnectionSnapshot> reconnect(String alias);
  Future<RemoteDirectoryQuery> openDirectory(String alias, {String? path});
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class RemoteDirectoryQuery {
  ReadonlyLatestValue<RemoteDirectoryState> get state;
  Future<void> loadMore();
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
