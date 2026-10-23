import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/remote_values.dart';

part 'remote_port.freezed.dart';

abstract interface class RemotePort {
  Future<List<SshServerRuntimeEntry>> reloadServers();
  Future<SshServerRuntimeEntry> save(
    SshServerProfile profile,
    SshPasswordUpdate password,
  );
  Future<void> delete(String alias);
  Future<SshConnectionSnapshot> authenticate(
    String alias,
    String password, {
    required bool rememberPassword,
  });
  Future<SshConnectionSnapshot> test(String alias);
  Future<SshConnectionSnapshot> reconnect(String alias);
  Future<RemoteDirectoryReadConnection> openDirectory(
    String alias, {
    String? path,
    String? cursor,
  });
  Future<void> closeDirectory(String alias, String cursor);
}

@Freezed(toStringOverride: false)
abstract class RemoteDirectoryReadHeader with _$RemoteDirectoryReadHeader {
  const factory RemoteDirectoryReadHeader({
    required String scopeId,
    required ReadText path,
    required ReadText? parent,
    required ReadText? nextCursor,
    required int pageEntryCount,
  }) = _RemoteDirectoryReadHeader;
}

@Freezed(toStringOverride: false)
abstract class RemoteDirectoryEntryRead with _$RemoteDirectoryEntryRead {
  const factory RemoteDirectoryEntryRead({
    required ReadText name,
    required ReadText path,
    required bool isDirectory,
    required bool isSymlink,
  }) = _RemoteDirectoryEntryRead;
}

@Freezed(toStringOverride: false)
abstract class RemoteDirectoryEntryPage with _$RemoteDirectoryEntryPage {
  const factory RemoteDirectoryEntryPage({
    required String scopeId,
    required int offset,
    required List<RemoteDirectoryEntryRead> items,
    required int? nextOffset,
  }) = _RemoteDirectoryEntryPage;
}

/// Pins one native v9 page. Entries offset never rescans the remote directory.
abstract interface class RemoteDirectoryReadConnection {
  Future<RemoteDirectoryReadHeader> header();
  Future<RemoteDirectoryEntryPage> entries({int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
