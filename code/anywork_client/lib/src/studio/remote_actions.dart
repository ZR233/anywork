import '../../models.dart';
import '../../studio_ports.dart';
import 'commands/command_lane.dart';

/// Typed remote queries and user commands. Presentation never holds transport.
final class RemoteActions {
  RemoteActions(this._transport);
  final StudioTransport _transport;
  final CommandLane _tasks = CommandLane();
  Future<void> close() {
    _tasks.seal();
    return _tasks.join();
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
  }) => _tasks.run(() => _transport.browseRemoteDirectories(alias, path: path));
}
