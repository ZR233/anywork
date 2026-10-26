import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/account_usage.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../catalog_references.dart';
import 'account_usage_feed.dart';
import 'account_usage_read_connection.dart';
import 'source_status_connection.dart';

AccountUsagePort createAccountUsagePort() => const FrbAccountUsagePort();

/// A transport leaf; query identity, demand and operation evidence belong to
/// AccountUsageRepository. Construction does not open feeds or check accounts.
final class FrbAccountUsagePort implements AccountUsagePort {
  const FrbAccountUsagePort();

  @override
  Future<FeedConnection<AccountUsageFrame>> openAccountUsage() async {
    final connection = FrbAccountUsageConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<AccountUsageReadConnection> openAccountUsageRead(
    AccountUsageReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbAccountUsageReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbAccountUsageSourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<AccountUsageCheckResult> check(
    String accountId, {
    required int expectedUsageQueryRevision,
  }) async {
    final BigInt revision;
    try {
      revision = nativeU64(
        expectedUsageQueryRevision,
        'account usage query revision',
      );
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: _callFailure(error)),
        stack,
      );
    }
    final native.BridgeAccountUsageCheckResult value;
    try {
      value = await native.checkAccountUsageCas(
        accountId: accountId,
        expectedUsageQueryRevision: revision,
      );
    } on Object catch (error, stack) {
      // This RPC includes the network query and merge, not only admission.
      // Even a BridgeError is not proof that no work was performed.
      Error.throwWithStackTrace(
        CommandDispatchFailure.unknownOutcome(failure: _callFailure(error)),
        stack,
      );
    }
    try {
      final result = AccountUsageCheckResult(
        target: accountUsageTargetFromBridge(value.target),
        accountId: value.accountId,
        usageQueryRevision: exactU64(
          value.usageQueryRevision,
          'account usage query revision',
        ),
      );
      if (result.accountId != accountId ||
          result.usageQueryRevision != expectedUsageQueryRevision ||
          result.target.origin.ownerEpoch.isEmpty ||
          result.target.origin.incarnation < 1) {
        throw adapterProtocol('account-usage-check-identity');
      }
      return result;
    } on Object catch (error, stack) {
      // Native returned its own target, but this API has no CommitReceipt.
      // Do not synthesize one to claim committedButUnobserved.
      Error.throwWithStackTrace(
        CommandDispatchFailure.confirmedWithoutUsableReceipt(
          failure: _callFailure(error),
        ),
        stack,
      );
    }
  }
}

StudioFailure _callFailure(Object error) {
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(
      mappingError,
      operation: 'account-usage-command-error',
    );
  }
}
