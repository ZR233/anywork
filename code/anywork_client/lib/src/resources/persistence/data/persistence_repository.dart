import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_repository.dart';
import '../domain/persistence_state.dart';
import '../domain/persistence_values.dart';
import 'persistence_actions.dart';
import 'persistence_field_reads.dart';
import 'persistence_mirror.dart';
import 'persistence_port.dart';
import 'persistence_queue_mirror.dart';
import 'persistence_queue_pages.dart';

PersistenceRepository createPersistenceRepository({
  required PersistencePort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _PersistenceRepository(port, ResourceLifetime(budget), operations);

final class _PersistenceRepository implements PersistenceRepository {
  _PersistenceRepository(PersistencePort port, this.lifetime, OperationRecorder operations) {
    values = PersistenceMirror(port, lifetime);
    queues = PersistenceQueueMirror(port, lifetime);
    reads = PersistenceReads(port, values, queues, lifetime);
    pages = PersistenceQueuePages(queues, reads, lifetime);
    actions = PersistenceActions(port, values, lifetime, operations);
    values.adopted = reads.adoptedValue;
    queues.adopted = (binding) { reads.adoptedQueue(binding); pages.adopted(binding); };
  }
  final ResourceLifetime lifetime;
  late final PersistenceMirror values;
  late final PersistenceQueueMirror queues;
  late final PersistenceReads reads;
  late final PersistenceQueuePages pages;
  late final PersistenceActions actions;
  bool _closed = false;

  @override
  ReadonlyLatestValue<PersistenceState> get state => values.source.readonly;
  @override
  ReadonlyLatestValue<PersistenceQueueState> get queue => queues.source.readonly;
  @override
  Future<void> loadValue() => reads.value();
  @override
  Future<void> loadQueuePage({int limit = 32}) => pages.load(limit: limit);
  @override
  Future<void> loadQueueLastError() => reads.lastError();
  @override
  OperationTicket<PersistenceReadTarget> retry() => actions.retry();
  @override
  OperationTicket<PersistenceQueueSnapshot> retryThreadHistory(String threadId, int faultGeneration) =>
    actions.history(threadId, faultGeneration, resume: false);
  @override
  OperationTicket<PersistenceQueueSnapshot> resumeThreadHistory(String threadId, int faultGeneration) =>
    actions.history(threadId, faultGeneration, resume: true);
  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, retry: false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => _close(deadline, retry: true);

  Future<CloseReport> _close(DateTime? deadline, {required bool retry}) async {
    final resources = await lifetime.close(deadline: deadline, retry: retry);
    final report = CloseReport(unresolved: [...resources.unresolved, ...actions.unresolved]);
    if (report.complete && !_closed) {
      _closed = true;
      values.source.close(); queues.source.close();
    }
    return report;
  }
}
