import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';
import 'support/acp_business_port.dart';
import 'support/directory_feed.dart';

const _budget = Duration(seconds: 5);
const _summaries = AccountSummariesTarget();

final class _Transport extends AccountsTestTransport
    with DirectoryFeedFixture {}

final class _Harness {
  _Harness() {
    final coordinator = SettingsWriteCoordinator();
    final board = MutationBoard(clientId: 'acp-open-lifecycle');
    domains = AccountDomainResources(
      feed: transport,
      configuration: transport,
      modelPort: transport,
      usagePort: transport,
      acpPort: transport,
      coordinator: coordinator,
      mutations: board,
      owner: 'acp-open-lifecycle',
    )..adoptOwnerEpoch(transport.epoch);
    client = AnyworkClient(
      transport: transport,
      clientId: 'acp-open-lifecycle',
      settingsWrites: coordinator,
      mutationBoard: board,
      accountDomains: domains,
      acpBusinessPort: port,
    );
    transport.seedThread(
      SessionDirectoryRow(
        sessionId: 'session',
        agentId: 'agent',
        threadId: 'thread',
        workspaceId: 'workspace',
        title: 'Saved ACP conversation',
        mode: null,
        delegationMode: DelegationMode.profile,
        delegationPreference: DelegationPreference.balanced,
        workspacePath: '/project',
        role: 'root',
        backend: const AcpAgentBackendView(
          reference: AcpSessionReferenceView(
            accountId: 'account',
            acpSessionId: 'remote',
            cwd: '/project',
          ),
        ),
        updatedAt: DateTime.utc(2026),
      ),
    );
  }

  final transport = _Transport();
  final port = ControlledAcpBusinessPort();
  late final AccountDomainResources domains;
  late final AnyworkClient client;

  Future<TestAccountObservation> metadataDelivered() async {
    final observation = await transport.attachedAccount(_summaries);
    // This borrows the same real metadata owner, not a fabricated result.
    final metadata = client.threadDirectory.observeThread('thread');
    try {
      await metadata.state.waitFor((state) => state.frame?.row != null);
    } finally {
      await metadata.release();
    }
    expect(domains.accounts.state.value.loaded, isFalse);
    return observation;
  }

  Future<void> close() async {
    final deadline = DateTime.now().add(_budget);
    final reports = await Future.wait([
      client.close(deadline: deadline),
      domains.close(deadline: deadline),
    ]).timeout(_budget);
    for (final report in reports) {
      expect(report.complete, isTrue, reason: '${report.unresolved}');
    }
  }
}

void main() {
  test(
    'external directory preserves cwd and cursor; explicit load never uses New',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.transport.baselines[_summaries] = AccountSummariesFrame(
        testStamp('settings', 4),
        const [
          AccountSummary(
            identity: AcpAccountIdentity('account'),
            name: 'Agent service',
            isDefault: false,
            acpEnabled: true,
            acpConnectionRevision: 37,
            capabilities: AccountCapabilities(
              setDefault: false,
              edit: true,
              remove: true,
              queryUsage: false,
              syncModels: false,
              editModels: false,
              acpAuth: true,
            ),
          ),
        ],
      );
      ControlledAcpObservation source(String threadId, String remote) =>
          ControlledAcpObservation([
            AcpAcceptedFrameView(
              target: AcpSessionTargetView(
                sessionId: 'session-$threadId',
                agentId: 'agent',
                threadId: threadId,
                instance: BigInt.one,
              ),
              hasObservation: true,
            ),
            const AcpEventFrameView(
              AcpInitializedEventView(
                AcpAgentCapabilitiesView(
                  image: false,
                  audio: false,
                  embeddedContext: false,
                  loadSession: true,
                  listSessions: true,
                  resumeSession: true,
                ),
              ),
            ),
            AcpEventFrameView(
              AcpReadyEventView(
                AcpNewSessionResponseView(
                  sessionId: AcpRemoteSessionId(remote),
                ),
              ),
            ),
            const AcpSettledFrameView(AcpSuccessView<void>(null)),
          ]);
      harness.port.sources.add(source('thread', 'remote'));
      final owner = await harness.client
          .openAcpConversation('thread')
          .timeout(_budget);
      await owner.source
          .waitFor((state) => state.ready && !state.openPending)
          .timeout(_budget);
      expect(harness.port.calls.where((call) => call.$1 == 'list'), isEmpty);
      harness.port.listValue = AcpListSessionsResponseView(
        sessions: [
          AcpSessionInfoView(
            sessionId: const AcpRemoteSessionId('external/original'),
            cwd: '/project',
          ),
        ],
        nextCursor: 'opaque/next',
      );
      final page = await harness.client
          .listAcpConversations('thread', cursor: 'opaque/current')
          .timeout(_budget);
      expect(page, same(harness.port.listValue));
      final listed = harness.port.calls.last.$2 as AcpListRequestView;
      expect(listed.target, same(owner.state.target));
      expect(listed.request.cwd, '/project');
      expect(listed.request.cursor, 'opaque/current');
      await expectLater(
        harness.client
            .openExternalAcpConversation(
              'thread',
              const AcpRemoteSessionId('external/original'),
              cwd: '/another-project',
            )
            .timeout(_budget),
        throwsUnsupportedError,
      );
      expect(
        harness.port.calls.where((call) => call.$1 == 'open'),
        hasLength(1),
      );
      harness.port.sources.add(source('external-thread', 'external/original'));
      final external = await harness.client
          .openExternalAcpConversation(
            'thread',
            const AcpRemoteSessionId('external/original'),
            cwd: '/project',
          )
          .timeout(_budget);
      expect(external.state.target!.threadId, 'external-thread');
      final request = harness.port.calls.last.$2 as OpenAcpSessionRequestView;
      expect(request.threadId, isNull);
      expect(request.workspaceId, 'workspace');
      expect(request.expectedConnectionRevision, BigInt.from(37));
      expect(
        request.intent,
        isA<AcpLoadIntentView>().having(
          (intent) => intent.sessionId.value,
          'sessionId',
          'external/original',
        ),
      );
      expect(
        harness.port.calls.where((call) => call.$1 == 'open'),
        hasLength(2),
      );
    },
  );

  test('close rejects cold ACP open waiting for account summaries', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    var finished = false;
    final opening = harness.client.openAcpConversation('thread');
    // Install the error handler before shutdown can reject the opening.
    final rejected = expectLater(
      opening.whenComplete(() => finished = true).timeout(_budget),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('closed'),
        ),
      ),
    );
    final accountObservation = await harness.metadataDelivered().timeout(
      _budget,
    );
    expect(finished, isFalse);
    expect(harness.port.calls, isEmpty);

    // Keep account domains alive until the opening has rejected: closing their
    // read mirror must not accidentally rescue an uncancelled Client query.
    final clientReport = await harness.client
        .close(deadline: DateTime.now().add(_budget))
        .timeout(_budget);
    expect(clientReport.complete, isTrue, reason: '${clientReport.unresolved}');
    await rejected;
    expect(finished, isTrue);
    expect(harness.port.calls, isEmpty);
    expect(accountObservation.closed, isTrue);
    expect(accountObservation.closeCalls, 1);
    expect(harness.transport.observations[_summaries], isEmpty);
    expect(harness.transport.directoryCloseCalls, 1);
    expect(harness.client.threadDirectory.observedWindows, isEmpty);
    await harness.close();
  });

  test(
    'late summaries supply their real revision once and resident is reused',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final source = ControlledAcpObservation([
        AcpAcceptedFrameView(
          target: AcpSessionTargetView(
            sessionId: 'session',
            agentId: 'agent',
            threadId: 'thread',
            instance: BigInt.from(73),
          ),
          hasObservation: true,
        ),
      ]);
      harness.port.sources.add(source);
      final opening = harness.client.openAcpConversation('thread');
      final accountObservation = await harness.metadataDelivered().timeout(
        _budget,
      );
      expect(harness.port.calls, isEmpty);
      harness.transport.emitAccount(
        AccountSummariesFrame(testStamp('settings', 4), const [
          AccountSummary(
            identity: AcpAccountIdentity('account'),
            name: 'Agent service',
            isDefault: false,
            acpEnabled: true,
            acpConnectionRevision: 37,
            capabilities: AccountCapabilities(
              setDefault: false,
              edit: true,
              remove: true,
              queryUsage: false,
              syncModels: false,
              editModels: false,
              acpAuth: true,
            ),
          ),
        ]),
      );
      final owner = await opening.timeout(_budget);
      expect(await harness.client.openAcpConversation('thread'), same(owner));
      final call = harness.port.calls.single;
      expect(call.$1, 'open');
      final request = call.$2 as OpenAcpSessionRequestView;
      expect(request.accountId, 'account');
      expect(request.expectedConnectionRevision, BigInt.from(37));
      expect(request.workspaceId, 'workspace');
      expect(request.threadId, 'thread');
      expect(
        request.intent,
        isA<AcpLoadIntentView>().having(
          (intent) => intent.sessionId,
          'sessionId',
          const AcpRemoteSessionId('remote'),
        ),
      );
      expect(accountObservation.closed, isTrue);
      expect(accountObservation.closeCalls, 1);
      expect(harness.transport.directoryCloseCalls, 1);
      await harness.close();
      expect(source.closeSignals, 1);
      expect(source.closes, 1);
    },
  );
}
