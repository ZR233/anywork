import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/mcp_repository.dart';
import '../domain/mcp_state.dart';
import 'mcp_actions.dart';
import 'mcp_field_reads.dart';
import 'mcp_mirror.dart';
import 'mcp_pages.dart';
import 'mcp_port.dart';

McpRepository createMcpRepository({
  required McpPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _McpRepository(port, budget, operations);

final class _McpRepository implements McpRepository {
  _McpRepository(
    McpPort port,
    ResourceBudget budget,
    OperationRecorder operations,
  ) : lifetime = ResourceLifetime(budget) {
    mirror = McpMirror(port, lifetime);
    reads = McpReads(port, mirror, lifetime);
    pages = McpPages(mirror, reads, lifetime);
    actions = McpActions(port, mirror, lifetime, operations);
    mirror.adopted = (binding) {
      reads.adopted(binding);
      pages.adopted(binding);
    };
  }
  final ResourceLifetime lifetime;
  late final McpMirror mirror;
  late final McpReads reads;
  late final McpPages pages;
  late final McpActions actions;
  bool _closed = false;

  @override
  ReadonlyLatestValue<McpState> get state => mirror.source.readonly;
  @override
  Future<void> loadServersPage({int limit = 32}) => pages.load(limit: limit);
  @override
  Future<void> loadActiveServerIds() => reads.active();
  @override
  Future<void> loadDesiredConfigFingerprint() => reads.desired();
  @override
  Future<void> loadAppliedConfigFingerprint() => reads.applied();
  @override
  Future<void> loadSourceStatus() => reads.sourceStatus();
  @override
  OperationTicket<McpReadTarget> resetServer(String serverId) =>
      actions.resetServer(serverId);
  @override
  OperationTicket<McpReadTarget> resetAll() => actions.resetAll();
  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final resources = await lifetime.close(deadline: deadline, retry: retry);
    final report = CloseReport(
      unresolved: [...resources.unresolved, ...actions.unresolved],
    );
    if (report.complete && !_closed) {
      _closed = true;
      mirror.source.publish(
        mirror.source.value.copyWith(
          projection: mirror.source.value.projection.copyWith(
            sync: const ResourceSyncState(
              phase: ResourceSyncPhase.closed,
              error: null,
              retryExhausted: false,
            ),
          ),
        ),
      );
      mirror.source.close();
    }
    return report;
  }
}
