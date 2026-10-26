import 'package:anywork_client/remote.dart';

import '../../../rust/api/studio/types/ssh.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';

SshServerRuntimeEntry sshServerFromBridge(native.SshServerDto value) =>
    SshServerRuntimeEntry(
      profile: SshServerProfile(
        alias: value.alias,
        hostName: value.hostName,
        port: value.port,
        username: value.username,
        identityFile: value.identityFile,
      ),
      managed: value.managed,
      hasPassword: value.hasPassword,
    );

native.SaveSshServerRequest sshServerToBridge(
  SshServerProfile profile,
  SshPasswordUpdate password,
) => native.SaveSshServerRequest(
  alias: profile.alias,
  hostName: profile.hostName,
  port: profile.port,
  username: profile.username,
  identityFile: profile.identityFile,
  password: switch (password) {
    PreserveSshPasswordUpdate() => const native.SshPasswordInput.preserve(),
    ReplaceSshPasswordUpdate(:final value) => native.SshPasswordInput.replace(
      value: value,
    ),
    ClearSshPasswordUpdate() => const native.SshPasswordInput.clear(),
  },
);

/// The native schema currently carries a finite state label plus nullable
/// fields. A missing required payload is Protocol, never a fabricated value.
SshConnectionSnapshot sshConnectionFromBridge(
  native.SshConnectionSnapshotDto value,
) => SshConnectionSnapshot(
  alias: value.alias,
  state: switch (value.state) {
    'disconnected' => const SshConnectionState.disconnected(),
    'connecting' => const SshConnectionState.connecting(),
    'ready' => SshConnectionState.ready(
      helperVersion: _required(value.helperVersion),
      architecture: _required(value.architecture),
    ),
    'reconnecting' => SshConnectionState.reconnecting(
      attempt: _required(value.attempt),
      delaySeconds: exactU64(
        _required(value.delaySeconds),
        'SSH reconnect delay seconds',
      ),
    ),
    'failed' => SshConnectionState.failed(
      code: _required(value.errorCode),
      message: _required(value.errorMessage),
    ),
    _ => throw adapterProtocol('ssh-connection-state'),
  },
);

T _required<T extends Object>(T? value) {
  if (value == null) throw adapterProtocol('ssh-connection-payload');
  return value;
}
