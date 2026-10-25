import 'package:anywork/src/app/bootstrap/application_bootstrap.dart';
import 'package:anywork/src/app/bootstrap/automatic_updates_startup.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/startup_port_fixture.dart';
import '../../../../anywork_client/test/support/updates_port_fixture.dart';
import 'bootstrap_workspace_fixture.dart';

/// Real bootstrap, automatic gate, Startup/Updates Repositories and registry.
/// Optional selection components add the actual Workspace/Conversation binding
/// at the same attach seam/order without pretending to assemble a full AppGraph.
final class UpdatesBootstrapFixture {
  UpdatesBootstrapFixture({ResourceBudget? resourceBudget, bool localEnabled = true, bool controlsEnabled = true,
    bool withWorkspaceBinding = false})
    : updates = UpdatesPortFixture(resourceBudget: resourceBudget, enabled: controlsEnabled) {
    selection = withWorkspaceBinding
      ? BootstrapWorkspaceFixture(budget: updates.budget, operations: updates.operations) : null;
    startup = createStartupRepository(port: startupPort, budget: updates.budget, operations: updates.operations);
    automatic = AutomaticUpdatesStartup(updates: updates.repository,
      lifecycle: updates.lifecycle, enabled: localEnabled);
    bootstrap = ApplicationBootstrap(startup: startup, attachDomains: (ready) async {
      attachments.add(ready);
      selection?.binding.start();
      final ticket = await automatic.startAfterRuntimeReady(ready);
      if (ticket != null) tickets.add(ticket);
    });
    addTearDown(close);
  }
  final UpdatesPortFixture updates;
  final startupPort = ScriptedStartupPort();
  late final BootstrapWorkspaceFixture? selection;
  late final StartupRepository startup;
  late final AutomaticUpdatesStartup automatic;
  late final ApplicationBootstrap bootstrap;
  final attachments = <RuntimeReady>[];
  final tickets = <OperationTicket<Unit>>[];
  String? expectedTerminalCorrelation;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    bootstrap.seal(); automatic.seal(); selection?.seal(); startup.seal(); updates.repository.seal();
    startupPort.releasePending(); updates.port.releasePending();
    final reports = await Future.wait([
      bootstrap.close(), automatic.close(), startup.close(),
      if (selection case final components?) components.close(),
      updates.repository.close(),
    ]);
    expect(reports.take(reports.length - 1).every((report) => report.complete), isTrue);
    final correlation = expectedTerminalCorrelation;
    if (correlation == null) {
      expect(reports.last.unresolved, isEmpty);
      expect(updates.budget.usage, isEmpty);
    } else {
      final issues = [for (final resource in reports.last.unresolved) ...resource.issues];
      expect(issues, isNotEmpty);
      expect(issues.every((issue) => issue.recovery == CleanupRecovery.terminal &&
        issue.diagnostic.correlationId == correlation), isTrue,
        reason: 'Joined UnknownOutcome retains its original terminal responsibility, not pending native work or Clean');
      expect(updates.port.automatic.single.native!.closed, isTrue);
      expect(updates.budget.used(ResourceKind.readModel), 1);
    }
  }
}

/// Race an actual environment boundary against premature completion/error of
/// the original work, so a broken gate fails directly instead of just timing
/// out waiting for a native call that the broken implementation suppressed.
Future<T> beforeCompletion<T>(Future<T> boundary, Future<Object?> work, String reason) => Future.any([
  boundary,
  work.then<T>((_) => throw StateError(reason), onError: (Object error, StackTrace stack) =>
    Error.throwWithStackTrace(error, stack)),
]);

Future<StudioFailure> typedFailure(Future<Object?> work) async {
  try { await work; }
  on StudioFailure catch (failure) { return failure; }
  fail('The original work must propagate its typed failure to the caller.');
}
