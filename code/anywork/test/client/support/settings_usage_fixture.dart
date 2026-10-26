import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/account_usage_fixture.dart';

export '../../../../anywork_client/test/support/account_usage_fixture.dart';

const settingsUsageFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The native usage check was rejected',
  retryable: true,
  correlationId: 'settings-usage-rejected',
);

Future<AccountUsageFixture> settingsUsageFixture(
  Map<String, int> accounts,
) async {
  final fixture = AccountUsageFixture();
  addTearDown(() async {
    await rejectSettingsUsageChecks(fixture);
    final report = await fixture.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(report.unresolved, isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  await fixture.establish(accounts);
  return fixture;
}

Future<void> rejectSettingsUsageChecks(AccountUsageFixture fixture) async {
  final tickets = [
    for (final check in fixture.usage.checks.value.values) check.ticket,
  ];
  for (final call in fixture.usagePort.calls) {
    if (!call.reply.isCompleted) {
      call.reply.completeError(
        const CommandDispatchFailure.rejected(failure: settingsUsageFailure),
      );
    }
  }
  await Future.wait([for (final ticket in tickets) ticket.result]);
}
