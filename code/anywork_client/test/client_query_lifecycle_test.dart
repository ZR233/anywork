import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _QueryTransport implements StudioTransport {
  final entered = Completer<void>();
  final reply = Completer<Uint8List>();
  int calls = 0;
  void Function()? onRead;

  @override
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId) {
    calls++;
    entered.complete();
    onRead?.call();
    return reply.future;
  }

  final List<SaveSshServerCommand> savedServers = [];
  final List<AuthenticateSshServerCommand> authCommands = [];

  @override
  Future<SshServer> saveSshServer(SaveSshServerCommand command) async {
    savedServers.add(command);
    return SshServer(
      alias: command.alias,
      hostName: command.hostName,
      port: command.port,
      username: command.username,
      identityFile: command.identityFile,
      managed: true,
      hasPassword: command.password.action == SshPasswordAction.replace,
    );
  }

  @override
  Future<SshConnectionView> authenticateSshServer(
    AuthenticateSshServerCommand command,
  ) async {
    authCommands.add(command);
    return SshConnectionView(
      alias: command.alias,
      state: 'ready',
      helperVersion: '0.1.0',
      architecture: 'x86_64',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused query capability: ${invocation.memberName}',
  );
}

StudioFailure _sshStudioFailure({
  required String message,
  String? detailsJson,
}) {
  return StudioFailure(
    code: StudioFailureCode.permissionDenied,
    message: message,
    retryable: false,
    correlationId: 'ssh-auth',
    detailsJson: detailsJson,
  );
}

void main() {
  test(
    'remote actions forward SSH password updates and session authentication',
    () async {
      final transport = _QueryTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'remote-ssh',
      );
      addTearDown(() => client.close());

      final saved = await client.remote.saveSshServer(
        const SaveSshServerCommand(
          alias: 'lab-node',
          hostName: '192.168.100.12',
          port: 22,
          username: 'tester',
          password: SshPasswordUpdate.replace('secret-pass'),
        ),
      );
      expect(saved.hasPassword, isTrue);
      expect(
        transport.savedServers.single.password.action,
        SshPasswordAction.replace,
      );
      expect(transport.savedServers.single.password.value, 'secret-pass');

      final connection = await client.remote.authenticateSshServer(
        const AuthenticateSshServerCommand(
          alias: 'lab-node',
          password: 'session-pass',
          rememberPassword: false,
        ),
      );
      expect(connection.state, 'ready');
      expect(transport.authCommands.single.alias, 'lab-node');
      expect(transport.authCommands.single.password, 'session-pass');
      expect(transport.authCommands.single.rememberPassword, isFalse);

      expect(
        isSshAuthenticationError(
          StateError(
            'SSH authentication required or failed: Permission denied',
          ),
        ),
        isTrue,
      );
      expect(
        isSshAuthenticationError(StateError('network unreachable')),
        isFalse,
      );
    },
  );

  test(
    'SSH detailsJson is authoritative for auth kind and password prompt',
    () {
      expect(
        sshPasswordAuthenticationOffered(
          _sshStudioFailure(
            message: 'remote host rejected credentials',
            detailsJson: '{"sshPasswordOffered": false}',
          ),
        ),
        isFalse,
      );
      expect(
        sshPasswordAuthenticationOffered(
          _sshStudioFailure(
            message: 'remote host rejected credentials',
            detailsJson: '{"sshPasswordOffered": true}',
          ),
        ),
        isTrue,
      );
      expect(
        sshPasswordAuthenticationOffered(
          _sshStudioFailure(
            message: 'remote host rejected credentials',
            detailsJson: '{"sshErrorKind": "authenticationFailed"}',
          ),
        ),
        isTrue,
      );
      expect(
        sshPasswordAuthenticationOffered(
          _sshStudioFailure(
            message: 'remote host rejected credentials',
            detailsJson: '{not-json',
          ),
        ),
        isTrue,
      );
      expect(
        sshPasswordAuthenticationOffered(StateError('network unreachable')),
        isTrue,
      );
      expect(
        sshPasswordAuthenticationOffered(
          _sshStudioFailure(message: 'remote host rejected credentials'),
        ),
        isTrue,
      );
      expect(
        sshPasswordAuthenticationOffered(
          _sshStudioFailure(
            message: 'remote host rejected credentials',
            detailsJson: '{"sshPasswordOffered": "false"}',
          ),
        ),
        isTrue,
      );

      expect(
        isSshAuthenticationError(StateError('network unreachable')),
        isFalse,
      );
      expect(
        isSshAuthenticationError(
          _sshStudioFailure(
            message: 'remote host rejected credentials',
            detailsJson: '{"sshErrorKind":"authenticationFailed"}',
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'synchronous transport reentry cannot escape the query close join',
    () async {
      final transport = _QueryTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'query-reentry',
      );
      late Future<CloseReport> closing;
      transport.onRead = () {
        closing = client.close(deadline: DateTime.utc(2000));
      };
      final reading = client.readAttachmentBytes('thread', 'attachment');
      final report = await closing;
      expect(report.unresolved.any((item) => item.owner == 'queries'), isTrue);
      transport.reply.complete(Uint8List(0));
      await reading;
      expect((await client.retryCleanup()).complete, isTrue);
    },
  );

  test(
    'close retains admitted query and rejects new queries until actual reply',
    () async {
      final transport = _QueryTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'query-close',
      );
      final reading = client.readAttachmentBytes('thread', 'attachment');
      await transport.entered.future;
      expect(client.budget.used(ResourceKind.pendingOperation), 1);
      final closing = client.close(deadline: DateTime.utc(2000));
      expect(
        identical(closing, client.close(deadline: DateTime.utc(2100))),
        isTrue,
      );
      final report = await closing;
      expect(report.unresolved.any((item) => item.owner == 'queries'), isTrue);
      expect(client.budget.used(ResourceKind.pendingOperation), 1);
      await expectLater(
        client.readAttachmentBytes('thread', 'late'),
        throwsStateError,
      );
      expect(transport.calls, 1);
      transport.reply.complete(Uint8List.fromList([7]));
      expect(await reading, [7]);
      expect((await client.retryCleanup()).complete, isTrue);
      expect(client.budget.usage, isEmpty);
    },
  );
}
