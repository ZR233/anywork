import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/acp_ports.dart';

import 'test_app_lifecycle.dart';

/// Composition-only ports for tests whose subject must not access accounts.
/// Unexpected reads/commands fail instead of manufacturing a ready account.
abstract class UnusedAccountPorts
    implements
        AccountFeedPort,
        AccountConfigurationPort,
        AccountModelsPort,
        AccountUsagePort,
        AcpPort,
        TestLifecycleOwner {
  @override
  final lifecycleRoot = ClientScope(owner: 'unused-account-test');
  late final contentScope = lifecycleRoot.child('transport');
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected account port: ${invocation.memberName}',
  );
}
