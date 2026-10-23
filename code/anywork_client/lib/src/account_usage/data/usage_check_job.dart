import 'dart:async';

import '../../../operations.dart';
import '../../../operations_ports.dart' show OperationWriter;
import '../../../resources.dart';
import '../../../resources_ports.dart' show ResourcePermit;
import '../domain/account_usage_repository.dart';
import '../domain/usage_values.dart';
import 'account_usage_port.dart';
import 'usage_identity.dart';

final class UsageCheckJob {
  UsageCheckJob(this.accountId, this.preparation, this.writer, this.attempt, this.permit, {required this.manual});
  final String accountId;
  final UsagePreparation preparation;
  final OperationWriter<AccountUsageRecord> writer;
  final AttemptId attempt;
  final ResourcePermit permit;
  // An explicit caller may join an automatic identity preparation and retain
  // its one ticket while authorizing a manual retry after identity is known.
  bool manual;
  Observation? observation;
  AccountUsageQueryIdentity? identity;
  UsageNetworkAttempt? network;
  Future<void>? completion;
  Future<void>? recovery;
  bool finished = false;
  bool preparing = true;
  bool get proven { final state = writer.ticket.state.value; return state.failurePhase == OperationFailurePhase.rejected || state.acknowledged && state.observed; }
  late final AccountUsageCheck borrow = _UsageCheckBorrow(this);
}

/// One actual network call may satisfy preparations that independently resolve
/// to the same identity. Its Future is never replaced or retried after unknown.
final class UsageNetworkAttempt {
  UsageNetworkAttempt(this.identity);
  final AccountUsageQueryIdentity identity;
  final Completer<AccountUsageCheckResult> response = Completer();
  final Set<UsageCheckJob> jobs = Set.identity();
  bool dispatched = false;
  bool settled = false;
  AccountUsageCheckResult? reply;
  ResourcePermit? permit;
}

final class _UsageCheckBorrow implements AccountUsageCheck {
  _UsageCheckBorrow(this.job);
  final UsageCheckJob job;
  @override
  String get accountId => job.accountId;
  @override
  AccountUsageQueryIdentity? get identity => job.identity;
  @override
  OperationTicket<AccountUsageRecord> get ticket => job.writer.ticket;
}
