import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/remote_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

final class _Requests<T> {
  final values = <T>[];
  final _waiters = <int, Completer<T>>{};
  Future<T> at(int index) => index < values.length
      ? Future.value(values[index])
      : _waiters.putIfAbsent(index, Completer<T>.new).future;
  void add(T value) {
    final index = values.length;
    values.add(value);
    _waiters.remove(index)?.complete(value);
  }
}

final class _SaveCall {
  _SaveCall(this.profile, this.password);
  final SshServerProfile profile;
  final SshPasswordUpdate password;
  final reply = Completer<SshServerRuntimeEntry>();
}

final class _AuthenticationCall {
  _AuthenticationCall(this.alias, this.password, this.rememberPassword);
  final String alias;
  final String password;
  final bool rememberPassword;
  final reply = Completer<SshConnectionSnapshot>();
}

/// Native command boundary only. Ordering, admission, canonical publication and
/// unknown-outcome retention are exercised in the real RemoteRepository.
final class _RemotePort implements RemotePort {
  final saves = _Requests<_SaveCall>();
  final authentications = _Requests<_AuthenticationCall>();
  final reconnects = <String>[];
  final tests = <String>[];
  List<SshServerRuntimeEntry> servers = const [];
  void Function()? onAuthenticate;

  @override
  Future<List<SshServerRuntimeEntry>> reloadServers() => Future.value(servers);
  @override
  Future<SshServerRuntimeEntry> save(
    SshServerProfile profile,
    SshPasswordUpdate password,
  ) {
    final call = _SaveCall(profile, password);
    saves.add(call);
    return call.reply.future;
  }

  @override
  Future<SshConnectionSnapshot> authenticate(
    String alias,
    String password, {
    required bool rememberPassword,
  }) {
    final call = _AuthenticationCall(alias, password, rememberPassword);
    authentications.add(call);
    onAuthenticate?.call();
    return call.reply.future;
  }

  @override
  Future<SshConnectionSnapshot> test(String alias) {
    tests.add(alias);
    return Future.value(_ready(alias));
  }

  @override
  Future<SshConnectionSnapshot> reconnect(String alias) {
    reconnects.add(alias);
    return Future.value(_ready(alias));
  }

  @override
  Future<void> delete(String alias) =>
      throw UnsupportedError('Unexpected SSH delete');
  @override
  Future<RemoteDirectoryReadConnection> openDirectory(
    String alias, {
    String? path,
    String? cursor,
  }) => throw UnsupportedError('Unexpected directory browse');
  @override
  Future<void> closeDirectory(String alias, String cursor) =>
      throw UnsupportedError('Unexpected cursor close');
}

const _profile = SshServerProfile(
  alias: 'lab-node',
  hostName: '192.168.100.12',
  port: 22,
  username: 'tester',
  identityFile: null,
);
SshConnectionSnapshot _ready(String alias) => SshConnectionSnapshot(
  alias: alias,
  state: const SshConnectionState.ready(
    helperVersion: '0.1.0',
    architecture: 'x86_64',
  ),
);

({
  RemoteRepository repository,
  ResourceBudget budget,
  OperationRegistry operations,
})
_remote(_RemotePort port) {
  final budget = ResourceBudget();
  final operations = OperationRegistry(clientId: 'remote-ssh', budget: budget);
  return (
    repository: createRemoteRepository(
      port: port,
      budget: budget,
      operations: operations,
    ),
    budget: budget,
    operations: operations,
  );
}

Future<T> _acknowledged<T>(OperationTicket<T> ticket) async {
  final result = await ticket.result;
  expect(result, isA<AcknowledgedCommandResult<T>>());
  return (result as AcknowledgedCommandResult<T>).value;
}

Matcher _failure(StudioFailureCode code) =>
    isA<StudioFailure>().having((failure) => failure.code, 'code', code);

void main() {
  test('SSH save and session authentication preserve exact password intent and typed results', () async {
    final port = _RemotePort();
    final owner = _remote(port);
    final saving = owner.repository.save(
      _profile,
      const SshPasswordUpdate.replace(value: 'secret-pass'),
    );
    final saved = await port.saves.at(0);
    expect(saved.profile, _profile);
    expect((saved.password as ReplaceSshPasswordUpdate).value, 'secret-pass');
    const server = SshServerRuntimeEntry(
      profile: _profile,
      managed: true,
      hasPassword: true,
    );
    saved.reply.complete(server);
    expect(await _acknowledged(saving), server);
    expect(
      owner.repository.state.value.servers,
      isNull,
      reason: 'One command response cannot fabricate an unloaded full SSH list',
    );

    final authenticating = owner.repository.authenticate(
      'lab-node',
      'session-pass',
      rememberPassword: false,
    );
    final authentication = await port.authentications.at(0);
    expect(authentication.alias, 'lab-node');
    expect(authentication.password, 'session-pass');
    expect(authentication.rememberPassword, isFalse);
    final connection = _ready('lab-node');
    authentication.reply.complete(connection);
    expect(await _acknowledged(authenticating), connection);
    expect(owner.repository.state.value.connections['lab-node'], connection);
    expect((await owner.repository.close()).complete, isTrue);
    expect(owner.budget.usage, isEmpty);
  });

  test('preserve and clear remain distinct while empty replacement is rejected before dispatch', () async {
    final port = _RemotePort();
    final owner = _remote(port);
    expect(
      () => owner.repository.save(
        _profile,
        const SshPasswordUpdate.replace(value: ' \t '),
      ),
      throwsA(_failure(StudioFailureCode.invalidArgument)),
    );
    expect(
      () => owner.repository.authenticate(
        'lab-node',
        ' \n ',
        rememberPassword: true,
      ),
      throwsA(_failure(StudioFailureCode.invalidArgument)),
    );
    expect(port.saves.values, isEmpty);
    expect(port.authentications.values, isEmpty);

    final preserving = owner.repository.save(
      _profile,
      const SshPasswordUpdate.preserve(),
    );
    final preserve = await port.saves.at(0);
    expect(preserve.password, isA<PreserveSshPasswordUpdate>());
    preserve.reply.complete(
      const SshServerRuntimeEntry(
        profile: _profile,
        managed: true,
        hasPassword: true,
      ),
    );
    expect((await _acknowledged(preserving)).hasPassword, isTrue);
    final clearing = owner.repository.save(
      _profile,
      const SshPasswordUpdate.clear(),
    );
    final clear = await port.saves.at(1);
    expect(clear.password, isA<ClearSshPasswordUpdate>());
    clear.reply.complete(
      const SshServerRuntimeEntry(
        profile: _profile,
        managed: true,
        hasPassword: false,
      ),
    );
    expect((await _acknowledged(clearing)).hasPassword, isFalse);
    expect((await owner.repository.close()).complete, isTrue);
    expect(owner.budget.usage, isEmpty);
  });

  test(
    'loaded handwritten profiles cannot be overwritten as managed entries',
    () async {
      final port = _RemotePort()
        ..servers = const [
          SshServerRuntimeEntry(
            profile: _profile,
            managed: false,
            hasPassword: false,
          ),
        ];
      final owner = _remote(port);
      await _acknowledged(owner.repository.reloadServers());
      expect(
        () =>
            owner.repository.save(_profile, const SshPasswordUpdate.preserve()),
        throwsA(_failure(StudioFailureCode.permissionDenied)),
      );
      expect(port.saves.values, isEmpty);
      expect(owner.repository.state.value.servers!.single.managed, isFalse);
      expect((await owner.repository.close()).complete, isTrue);
    },
  );

  test(
    'same-alias actions serialize without blocking another SSH target',
    () async {
      final port = _RemotePort();
      final owner = _remote(port);
      final first = owner.repository.authenticate(
        'a',
        'first-secret',
        rememberPassword: false,
      );
      final firstCall = await port.authentications.at(0);
      final queued = owner.repository.reconnect('a');
      final other = owner.repository.authenticate(
        'b',
        'other-secret',
        rememberPassword: true,
      );
      final otherCall = await port.authentications.at(1);
      expect(otherCall.alias, 'b');
      expect(otherCall.rememberPassword, isTrue);
      expect(port.reconnects, isEmpty);
      otherCall.reply.complete(_ready('b'));
      expect((await _acknowledged(other)).alias, 'b');
      expect(
        owner.repository.state.value.connections.containsKey('a'),
        isFalse,
      );
      expect(queued.state.value.isPending, isTrue);
      firstCall.reply.complete(_ready('a'));
      await _acknowledged(first);
      expect(
        owner.operations.observations.latest('remote-connection:a')!.id,
        queued.id,
        reason: 'An older reply cannot replace the newer operation identity',
      );
      expect((await _acknowledged(queued)).alias, 'a');
      expect(port.reconnects, ['a']);
      expect((await owner.repository.close()).complete, isTrue);
      expect(owner.budget.usage, isEmpty);
    },
  );

  test(
    'unknown authentication stays owned and never replays its frozen secret',
    () async {
      final port = _RemotePort();
      final owner = _remote(port);
      final ticket = owner.repository.authenticate(
        'a',
        'frozen-secret',
        rememberPassword: false,
      );
      final request = await port.authentications.at(0);
      final observation = ticket.state.watch((_) {});
      observation.cancel();
      const error = StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'The dispatch result is unknown',
        retryable: true,
        correlationId: 'ssh-unknown',
      );
      request.reply.completeError(
        const CommandDispatchFailure.unknownOutcome(failure: error),
      );
      final result = await ticket.result;
      expect(result, isA<UnknownOutcomeCommandResult<SshConnectionSnapshot>>());
      expect(
        (result as UnknownOutcomeCommandResult<SshConnectionSnapshot>).error,
        error,
      );
      expect(ticket.state.value.isPending, isTrue);
      expect(
        () => owner.repository.reconnect('a'),
        throwsA(_failure(StudioFailureCode.conflict)),
      );
      expect(port.reconnects, isEmpty);
      final other = owner.repository.test('b');
      expect((await _acknowledged(other)).alias, 'b');
      final report = await owner.repository.close();
      expect(report.complete, isFalse);
      final unresolved = report.unresolved.single.issues.single;
      expect(unresolved.diagnostic.correlationId, 'ssh-unknown');
      expect(unresolved.diagnostic.retryable, isTrue);
      expect(unresolved.recovery, CleanupRecovery.terminal);
      expect((await owner.repository.retryCleanup()).complete, isFalse);
      expect(port.authentications.values, hasLength(1));
      expect(request.password, 'frozen-secret');
      expect(
        owner.repository.state.value.connections.containsKey('a'),
        isFalse,
      );
    },
  );

  for (final reentry in [false, true]) {
    test(
      'close joins admitted authentication with ${reentry ? 'synchronous reentry' : 'a pending reply'}',
      () async {
        final port = _RemotePort();
        final owner = _remote(port);
        late Future<CloseReport> closing;
        if (reentry) {
          port.onAuthenticate = () {
            closing = owner.repository.close(deadline: DateTime.utc(2000));
          };
        }
        final ticket = owner.repository.authenticate(
          'a',
          'pending-secret',
          rememberPassword: false,
        );
        final request = await port.authentications.at(0);
        if (!reentry)
          closing = owner.repository.close(deadline: DateTime.utc(2000));
        final report = await closing;
        expect(report.complete, isFalse);
        expect(report.unresolved.single.owner, 'remote-command');
        expect(
          report.unresolved.single.issues.single.recovery,
          CleanupRecovery.awaitCompletion,
        );
        expect(owner.budget.used(ResourceKind.pendingOperation), 1);
        expect(
          () => owner.repository.test('late'),
          throwsA(_failure(StudioFailureCode.cancelled)),
        );
        expect(port.tests, isEmpty);
        request.reply.complete(_ready('a'));
        expect((await _acknowledged(ticket)).alias, 'a');
        expect(
          owner.repository.state.value.connections,
          isEmpty,
          reason: 'Late completion settles its original operation, not a sealed mirror',
        );
        expect((await owner.repository.retryCleanup()).complete, isTrue);
        expect(owner.budget.usage, isEmpty);
        expect(port.authentications.values, hasLength(1));
      },
    );
  }
}
