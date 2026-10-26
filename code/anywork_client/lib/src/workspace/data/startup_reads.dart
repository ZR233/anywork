import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/startup_values.dart';
import 'startup_port.dart';
import 'startup_read_owner.dart';

/// Owns only the startup detail pins, never initializes the library/runtime.
final class StartupReads {
  StartupReads(this.port, this.budget);
  final StartupPort port;
  final ResourceBudget budget;
  final Map<AttemptId, StartupReadOwner> _owners = {};
  int _sequence = 0;
  bool _sealed = false;

  Future<StartupRecovery?> recovery(RuntimeStartupReadRef reference) =>
      _read(reference, (owner, header) async {
        final value = header.startupRecovery;
        if (value == null) return null;
        return StartupRecovery(
          backupPath: await owner.text(value.backupPath),
          reason: await owner.text(value.reason),
          createdAt: value.createdAt,
        );
      });

  Future<StartupActiveTurnPage> activeTurns(
    RuntimeStartupReadRef reference, {
    int offset = 0,
    int limit = 32,
  }) {
    _ensureOpen();
    if (offset < 0 || limit < 1 || limit > 100) {
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message:
              'Startup active-turn page requires offset >= 0 and limit 1..100.',
          retryable: false,
          correlationId: '',
        ),
      );
    }
    return _read(reference, (owner, header) async {
      final page = await owner.activeTurns(offset: offset, limit: limit);
      final end = offset + page.items.length;
      if (page.offset != offset ||
          page.total != header.activeTurnCount ||
          page.items.length > limit ||
          end > page.total ||
          (page.nextOffset == null && end != page.total) ||
          (page.nextOffset != null &&
              (page.items.isEmpty ||
                  page.nextOffset != end ||
                  end >= page.total))) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'Invalid startup active-turn page identity or continuation.',
          retryable: false,
          correlationId: '',
        );
      }
      final items = <StartupActiveTurn>[];
      for (final item in page.items) {
        items.add(
          StartupActiveTurn(
            threadId: await owner.text(item.threadId),
            turnId: await owner.text(item.turnId),
          ),
        );
      }
      return StartupActiveTurnPage(
        reference: reference,
        offset: page.offset,
        total: page.total,
        items: items,
        nextOffset: page.nextOffset,
      );
    });
  }

  void _ensureOpen() {
    if (_sealed) {
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Startup reading is sealed.',
        retryable: false,
        correlationId: '',
      );
    }
  }

  Future<T> _read<T>(
    RuntimeStartupReadRef reference,
    Future<T> Function(StartupReadOwner, RuntimeStartupReadHeader) read,
  ) {
    _ensureOpen();
    final ResourcePermit permit;
    try {
      // The same composition-root budget as every other domain; no extra pool.
      permit = budget.acquire(
        ResourceKind.readModel,
        owner: 'startup-read',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final owner = StartupReadOwner(
      port: port,
      reference: reference,
      permit: permit,
      id: AttemptId(++_sequence),
    );
    _owners[owner.id] = owner;
    return _perform(owner, read);
  }

  Future<T> _perform<T>(
    StartupReadOwner owner,
    Future<T> Function(StartupReadOwner, RuntimeStartupReadHeader) read,
  ) async {
    try {
      return await owner.read((_, header) => read(owner, header));
    } finally {
      await owner.close();
      _release(owner);
    }
  }

  void seal() {
    _sealed = true;
    for (final owner in _owners.values) {
      owner.requestClose();
    }
  }

  Future<void> close({required bool retry}) async {
    seal();
    await Future.wait([
      for (final owner in List.of(_owners.values))
        owner.close(retry: retry).then((_) => _release(owner)),
    ]);
  }

  void _release(StartupReadOwner owner) {
    if (!owner.complete) {
      owner.permit.mark(ResourcePhase.unresolved);
      return;
    }
    owner.permit.release();
    _owners.remove(owner.id);
  }

  List<UnresolvedResource> get unresolved => [
    for (final owner in _owners.values)
      UnresolvedResource(
        owner: 'startup-read',
        attemptId: owner.id,
        issues: [
          ...owner.issues,
          if (owner.pending || owner.issues.isEmpty)
            const FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'startup-read',
                code: 'awaitingCompletion',
                message: 'Accepted startup detail work has not finished.',
                retryable: true,
                correlationId: '',
              ),
              recovery: CleanupRecovery.awaitCompletion,
            ),
        ],
      ),
  ];
}
