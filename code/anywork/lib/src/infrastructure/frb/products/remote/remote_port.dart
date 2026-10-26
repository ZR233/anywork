import 'package:anywork_client/remote_ports.dart';

import '../../../../rust/api/studio/handlers/ssh.dart' as ssh;
import '../../../../rust/api/studio/products/read/remote_directory.dart'
    as directory;
import '../../../../rust/api/studio/types/ssh.dart' as inputs;
import '../../remote/remote_converters.dart';
import '../../shared/bridge_failure.dart';
import 'directory_read_connection.dart';

/// Reuses the existing SSH adapter and the authorized native directory scope.
/// No filesystem API, credential cache or alternate SSH client is introduced.
final class FrbRemotePort implements RemotePort {
  const FrbRemotePort();

  @override
  Future<List<SshServerRuntimeEntry>> reloadServers() => bridgeQuery(
    () async => List<SshServerRuntimeEntry>.unmodifiable(
      (await ssh.listSshServers()).map(sshServerFromBridge),
    ),
  );

  @override
  Future<SshServerRuntimeEntry> save(
    SshServerProfile profile,
    SshPasswordUpdate password,
  ) => bridgeQuery(
    () async => sshServerFromBridge(
      await ssh.saveSshServer(request: sshServerToBridge(profile, password)),
    ),
  );

  @override
  Future<void> delete(String alias) =>
      bridgeQuery(() => ssh.deleteSshServer(alias: alias));

  @override
  Future<SshConnectionSnapshot> authenticate(
    String alias,
    String password, {
    required bool rememberPassword,
  }) => bridgeQuery(
    () async => sshConnectionFromBridge(
      await ssh.authenticateSshServer(
        request: inputs.AuthenticateSshServerRequest(
          alias: alias,
          password: password,
          rememberPassword: rememberPassword,
        ),
      ),
    ),
  );

  @override
  Future<SshConnectionSnapshot> test(String alias) => bridgeQuery(
    () async =>
        sshConnectionFromBridge(await ssh.testSshConnection(alias: alias)),
  );

  @override
  Future<SshConnectionSnapshot> reconnect(String alias) => bridgeQuery(
    () async =>
        sshConnectionFromBridge(await ssh.reconnectSshServer(alias: alias)),
  );

  @override
  Future<RemoteDirectoryReadConnection> openDirectory(
    String alias, {
    String? path,
    String? cursor,
  }) async {
    final connection = FrbRemoteDirectoryReadConnection(
      alias,
      path: path,
      cursor: cursor,
    );
    await connection.opened;
    return connection;
  }

  @override
  Future<void> closeDirectory(String alias, String cursor) =>
      bridgeQuery(() => directory.closeDirectory(alias: alias, cursor: cursor));
}
