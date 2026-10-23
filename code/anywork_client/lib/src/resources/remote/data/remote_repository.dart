import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/remote_repository.dart';
import '../domain/remote_values.dart';
import 'remote_commands.dart';
import 'remote_directory_owner.dart';
import 'remote_observation.dart';
import 'remote_port.dart';

RemoteRepository createRemoteRepository({
  required RemotePort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _RemoteRepository(port, budget, operations);

final class _RemoteRepository implements RemoteRepository {
  _RemoteRepository(this._port, this._budget, OperationRecorder operations)
    : _commands = RemoteCommands(operations) {
    _source = RemoteValue(
      const RemoteState(servers: null, connections: {}), _budget, 'remote-state',
    );
  }

  final RemotePort _port;
  final ResourceBudget _budget;
  final RemoteCommands _commands;
  late final RemoteValue<RemoteState> _source;
  final Map<AttemptId, RemoteDirectoryOwner> _queries = {};
  final Map<AttemptId, Completer<void>> _opens = {};
  final Map<AttemptId, (Object, StackTrace)> _cleanupCauses = {};
  final List<UnresolvedResource> _terminalIssues = [];
  Future<void>? _cleanup;
  int _sequence = 0;
  bool _sealed = false;
  bool _closed = false;

  @override
  ReadonlyLatestValue<RemoteState> get state => _source.readonly;

  void _ensureOpen() {
    if (_sealed) throw remoteCancelled();
  }

  @override
  OperationTicket<List<SshServerRuntimeEntry>> reloadServers() {
    _ensureOpen();
    return _commands.run(
      target: 'remote-servers',
      lanes: {'configuration'},
      dispatch: () async => List<SshServerRuntimeEntry>.unmodifiable(await _port.reloadServers()),
      onReturned: (value) {
        if (!_sealed) _source.publish(_source.value.copyWith(servers: value));
      },
    );
  }

  void _checkManaged(String alias) {
    for (final entry in _source.value.servers ?? const <SshServerRuntimeEntry>[]) {
      if (entry.profile.alias == alias && !entry.managed) {
        throw const StudioFailure(
          code: StudioFailureCode.permissionDenied,
          message: 'Handwritten SSH entries are read-only.',
          retryable: false,
          correlationId: '',
        );
      }
    }
  }

  @override
  OperationTicket<SshServerRuntimeEntry> save(
    SshServerProfile profile,
    SshPasswordUpdate password,
  ) {
    _ensureOpen();
    _checkManaged(profile.alias);
    if (password case ReplaceSshPasswordUpdate(:final value)) {
      _checkPassword(value);
    }
    final alias = profile.alias;
    return _commands.run(
      target: 'remote-server:$alias',
      lanes: {'configuration', 'alias:$alias'},
      dispatch: () => _port.save(profile, password),
      onReturned: (value) {
        if (value.profile.alias != alias) throw remoteProtocol('SSH save returned another alias');
        if (_sealed) return;
        final current = _source.value.servers;
        // Without a loaded full list, one command result cannot invent it.
        if (current == null) return;
        _source.publish(_source.value.copyWith(servers: List.unmodifiable([
          for (final entry in current)
            if (entry.profile.alias != alias) entry,
          value,
        ])));
      },
    );
  }

  @override
  OperationTicket<Unit> delete(String alias) {
    _ensureOpen();
    _checkManaged(alias);
    return _commands.run(
      target: 'remote-server:$alias',
      lanes: {'configuration', 'alias:$alias'},
      dispatch: () async {
        await _port.delete(alias);
        return const Unit();
      },
      onReturned: (_) {
        if (_sealed) return;
        final value = _source.value;
        _source.publish(value.copyWith(
          servers: value.servers == null ? null : List.unmodifiable([
            for (final entry in value.servers!)
              if (entry.profile.alias != alias) entry,
          ]),
          connections: Map.unmodifiable({
            for (final entry in value.connections.entries)
              if (entry.key != alias) entry.key: entry.value,
          }),
        ));
      },
    );
  }

  @override
  OperationTicket<SshConnectionSnapshot> authenticate(
    String alias,
    String password, {
    required bool rememberPassword,
  }) {
    _ensureOpen();
    _checkPassword(password);
    // Password replacement/rollback and remembering remain the native owner's
    // responsibility. This immutable closure retains the exact original input.
    return _connection(alias, () => _port.authenticate(
      alias, password, rememberPassword: rememberPassword,
    ));
  }

  @override
  OperationTicket<SshConnectionSnapshot> test(String alias) =>
      _connection(alias, () => _port.test(alias));

  @override
  OperationTicket<SshConnectionSnapshot> reconnect(String alias) =>
      _connection(alias, () => _port.reconnect(alias));

  OperationTicket<SshConnectionSnapshot> _connection(
    String alias,
    Future<SshConnectionSnapshot> Function() dispatch,
  ) {
    _ensureOpen();
    return _commands.run(
      target: 'remote-connection:$alias',
      lanes: {'alias:$alias'},
      dispatch: dispatch,
      onReturned: (value) {
        if (value.alias != alias) throw remoteProtocol('SSH connection returned another alias');
        if (!_sealed) {
          _source.publish(_source.value.copyWith(connections: Map.unmodifiable({
            ..._source.value.connections, alias: value,
          })));
        }
      },
    );
  }

  static void _checkPassword(String value) {
    if (value.trim().isEmpty) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'SSH password must not be empty.',
        retryable: false,
        correlationId: '',
      );
    }
  }

  @override
  Future<RemoteDirectoryQuery> openDirectory(String alias, {String? path}) {
    _ensureOpen();
    final ResourcePermit permit;
    try {
      permit = _budget.acquire(
        ResourceKind.readModel,
        owner: 'remote-directory',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final query = RemoteDirectoryOwner(
      port: _port,
      budget: _budget,
      alias: alias,
      initialPath: path,
      id: AttemptId(++_sequence),
      permit: permit,
      onClean: (owner) {
        if (identical(_queries[owner.id], owner)) _queries.remove(owner.id);
      },
    );
    _queries[query.id] = query;
    final opening = Completer<void>();
    _opens[query.id] = opening;
    return _open(query, opening);
  }

  Future<RemoteDirectoryQuery> _open(
    RemoteDirectoryOwner query,
    Completer<void> opening,
  ) async {
    try {
      await query.initialize();
      if (_sealed) throw remoteCancelled();
      return query;
    } catch (error, stack) {
      query.requestClose();
      // On application close the repository, not this late open callback,
      // owns the global handoff-before-cursor-close barrier.
      if (!_sealed) await query.close();
      if (error is StudioFailure) rethrow;
      Error.throwWithStackTrace(remoteProtocol('Opening the remote directory failed'), stack);
    } finally {
      opening.complete();
      if (identical(_opens[query.id], opening)) _opens.remove(query.id);
    }
  }

  @override
  void seal() {
    if (_sealed) return;
    _sealed = true;
    _commands.seal();
    _source.close();
    for (final query in List.of(_queries.values)) {
      query.requestClose();
    }
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) {
    seal();
    if (!_closed) {
      _closed = true;
      _beginCleanup(retry: false);
    }
    return _wait(deadline);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    if (!_closed) throw remoteProtocol('Close remote resources before retrying cleanup');
    _beginCleanup(retry: true);
    return _wait(deadline);
  }

  void _beginCleanup({required bool retry}) {
    if (_cleanup != null) return;
    final id = AttemptId(++_sequence);
    final work = _join(retry);
    _cleanup = work;
    unawaited(work.then<void>((_) {
      if (identical(_cleanup, work)) _cleanup = null;
    }, onError: (Object error, StackTrace stack) {
      _cleanupCauses[id] = (error, stack);
      _terminalIssues.add(UnresolvedResource(
        owner: 'remote-repository',
        attemptId: id,
        issues: [remoteIssue(error, 'remote-repository-join', CleanupRecovery.terminal)],
      ));
      if (identical(_cleanup, work)) _cleanup = null;
    }));
  }

  Future<void> _join(bool retry) async {
    final queries = List.of(_queries.values);
    final openings = List.of(_opens.values);
    for (final query in queries) {
      query.requestClose();
    }
    // Install every admitted-work join before awaiting any one owner.
    final handoffWork = Future.wait([
      for (final query in queries) query.settleAccepted(retry: retry),
    ]);
    final admittedWork = Future.wait([
      _commands.join(),
      for (final opening in openings) opening.future,
    ]);
    final handoffs = await handoffWork;
    await admittedWork;
    if (handoffs.any((complete) => !complete)) return;
    // No new page/native cursor can escape this barrier. Close independent
    // query cursor sets in parallel; failed sets stay in _queries for recovery.
    for (final query in queries) {
      query.beginCleanup(retry: retry);
    }
    await Future.wait([
      for (final query in queries) query.close(),
    ]);
  }

  Future<CloseReport> _wait(DateTime? deadline) async {
    final work = _cleanup;
    if (work != null) {
      try {
        if (deadline == null) {
          await work;
        } else {
          final remaining = deadline.difference(DateTime.now());
          await work.timeout(remaining.isNegative ? Duration.zero : remaining);
        }
      } on TimeoutException {
        // Keep the original admitted work and native cursor ownership intact.
      } catch (_) {
        // _beginCleanup's already-registered handler retains the original
        // cause and typed terminal issue; do not replace CloseReport by throw.
      }
    }
    return CloseReport(unresolved: [
      ..._commands.unresolved,
      for (final query in _queries.values) ...query.report.unresolved,
      for (final entry in _opens.entries)
        if (!entry.value.isCompleted)
          UnresolvedResource(
            owner: 'remote-open',
            attemptId: entry.key,
            issues: [const FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'remote-open',
                code: 'awaitingCompletion',
                message: 'An accepted remote opening has not completed.',
                retryable: true,
                correlationId: '',
              ),
              recovery: CleanupRecovery.awaitCompletion,
            )],
          ),
      ..._terminalIssues,
    ]);
  }
}
