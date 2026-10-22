import '../../models.dart';
import '../../studio_ports.dart';
import 'commands/command_lane.dart';

/// Typed remote queries and user commands. Presentation never holds transport.
final class RemoteActions {
  RemoteActions(this._transport);
  final StudioTransport _transport;
  final CommandLane _tasks = CommandLane();
  final Set<(String, String)> _directories = {};
  Future<void> close() async {
    _tasks.seal();
    await _tasks.join();
    await Future.wait(
      _directories.toList().map((entry) async {
        await _transport.closeRemoteDirectory(entry.$1, entry.$2);
        _directories.remove(entry);
      }),
    );
  }

  Future<List<SshServer>> listSshServers() =>
      _tasks.run(_transport.listSshServers);
  Future<SshServer> saveSshServer(SaveSshServerCommand command) =>
      _tasks.run(() => _transport.saveSshServer(command));
  Future<void> deleteSshServer(String alias) =>
      _tasks.run(() => _transport.deleteSshServer(alias));
  Future<SshConnectionView> authenticateSshServer(
    AuthenticateSshServerCommand command,
  ) => _tasks.run(() => _transport.authenticateSshServer(command));
  Future<SshConnectionView> testSshConnection(String alias) =>
      _tasks.run(() => _transport.testSshConnection(alias));
  Future<SshConnectionView> reconnectSshServer(String alias) =>
      _tasks.run(() => _transport.reconnectSshServer(alias));
  Future<RemoteDirectoryListing> browseRemoteDirectories(
    String alias, {
    String? path,
    String? cursor,
  }) => _tasks.run(() async {
    final listing = await _transport.browseRemoteDirectories(
      alias,
      path: path,
      cursor: cursor,
    );
    if (cursor != null) _directories.remove((alias, cursor));
    if (listing.nextCursor case final next?) _directories.add((alias, next));
    return listing;
  });

  Future<void> closeRemoteDirectory(String alias, String cursor) =>
      _tasks.run(() async {
        await _transport.closeRemoteDirectory(alias, cursor);
        _directories.remove((alias, cursor));
      });
}
