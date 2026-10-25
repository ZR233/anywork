import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'profile_command_fixture.dart';

final class RecordedProfileReload {
  RecordedProfileReload(this.request, this.native);
  final ConfigurationReloadRequest request;
  final ScriptedProfileReloadCall native;
  final beginReply = Completer<ConfigurationReloadCall>();
  bool accepted = false;

  void accept() {
    accepted = true;
    beginReply.complete(native);
  }
}

final class RecordedProfileReloadLookup {
  RecordedProfileReloadLookup(this.operationId);
  final OperationId operationId;
  final reply = Completer<ConfigurationReloadCall?>();
}

/// Reload deliberately has a distinct typed result with no CommitReceipt.
final class ScriptedProfileReloadCall
    extends ScriptedProfileNativeCall<ConfigurationReloadResult>
    implements ConfigurationReloadCall {
  ScriptedProfileReloadCall({
    required super.callId,
    required super.operationId,
  });
}
