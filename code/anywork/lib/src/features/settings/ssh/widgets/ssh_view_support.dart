import 'package:anywork_client/remote.dart';
import 'package:flutter/widgets.dart';

import '../../../../l10n/studio_l10n.dart';

/// Connection-state copy for the server row.
///
/// An entry with no connection yet reads as `disconnected`, matching the
/// pre-refactor row instead of showing an empty placeholder.
String sshConnectionStateText(
  BuildContext context,
  SshConnectionState? state,
) => context.sshConnectionStateLabel(switch (state) {
  null || DisconnectedSshConnectionState() => 'disconnected',
  ConnectingSshConnectionState() => 'connecting',
  ReadySshConnectionState() => 'ready',
  ReconnectingSshConnectionState() => 'reconnecting',
  FailedSshConnectionState() => 'failed',
});
