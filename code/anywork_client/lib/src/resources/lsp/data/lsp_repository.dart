import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_repository.dart';
import '../domain/lsp_state.dart';
import 'lsp_actions.dart';
import 'lsp_field_reads.dart';
import 'lsp_mirror.dart';
import 'lsp_pages.dart';
import 'lsp_port.dart';

LspRepository createLspRepository({
  required LspPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _LspRepository(port, budget, operations);

final class _LspRepository implements LspRepository {
  _LspRepository(LspPort port, ResourceBudget budget, OperationRecorder operations)
      : lifetime = ResourceLifetime(budget) {
    mirror = LspMirror(port, lifetime);
    reads = LspReads(port, mirror, lifetime);
    pages = LspPages(mirror, reads, lifetime);
    actions = LspActions(port: port, lifetime: lifetime, operations: operations,
      synchronize: mirror.synchronize);
    mirror.adopted = (binding) { reads.adopted(binding); pages.adopted(binding); };
  }
  final ResourceLifetime lifetime;
  late final LspMirror mirror;
  late final LspReads reads;
  late final LspPages pages;
  late final LspActions actions;
  bool _closed = false;

  @override
  ReadonlyLatestValue<LspState> get state => mirror.source.readonly;
  @override
  Future<void> loadServersPage({int limit = 32}) => pages.load(limit: limit);
  @override
  Future<void> loadActiveServerIds() => reads.active();
  @override
  Future<void> loadSourceStatus() => reads.sourceStatus();
  @override
  OperationTicket<LspReadTarget> probe(String projectId) => actions.probe(projectId);
  @override
  OperationTicket<LspReadTarget> repair(String projectId, String serverId) => actions.repair(projectId, serverId);
  @override
  OperationTicket<LspReadTarget> resetServer(String projectId, String serverId) => actions.resetServer(projectId, serverId);
  @override
  OperationTicket<LspReadTarget> resetWorkspace(String projectId) => actions.resetWorkspace(projectId);
  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final resources = await lifetime.close(deadline: deadline, retry: retry);
    final report = CloseReport(unresolved: [...resources.unresolved, ...actions.unresolved]);
    if (report.complete && !_closed) {
      _closed = true;
      mirror.source.publish(mirror.source.value.copyWith(projection: mirror.source.value.projection.copyWith(
        sync: const ResourceSyncState(phase: ResourceSyncPhase.closed, error: null, retryExhausted: false))));
      mirror.source.close();
    }
    return report;
  }
}
