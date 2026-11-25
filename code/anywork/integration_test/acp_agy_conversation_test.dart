import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_composer_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_content_view_model.dart';
import 'package:anywork/src/features/conversation/composer/views/start_model_selector_view.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/statistics.dart' show StatisticsSample;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/agy_remote_workspace.dart';
import 'support/agy_phase_runner.dart';
import 'support/agy_load_only.dart';
import 'support/agy_title_only.dart';
import 'support/observed.dart';
import 'support/presentation_capture.dart';
import 'support/production_studio_harness.dart';

// Explicit live acceptance only. HOME is deliberately untouched: official agy
// owns authentication. The caller must provide an empty, disposable Studio home
// under ANYWORK_AGY_SANDBOX. A local project is under the same sandbox; the
// explicit SSH variant uses an independently provisioned remote fixture.
// Neither variant attempts login or writes SSH configuration.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'logged-in agy through the complete production ACP conversation shell',
    (tester) async {
      if (Platform.environment['ANYWORK_AGY_LIVE'] != '1') {
        throw StateError('Explicit live opt-in requires ANYWORK_AGY_LIVE=1');
      }
      final titleOnly = Platform.environment['ANYWORK_AGY_TITLE_ONLY'] == '1';
      if (titleOnly &&
          (!Platform.isLinux ||
              Platform.environment['ANYWORK_AGY_MANAGED'] == '1' ||
              Platform.environment.containsKey('ANYWORK_AGY_SSH_ALIAS') ||
              Platform.environment.containsKey('ANYWORK_AGY_SSH_TARGET') ||
              Platform.environment.containsKey('ANYWORK_AGY_LOAD_THREAD') ||
              Platform.environment.containsKey('ANYWORK_AGY_LOAD_SESSION'))) {
        throw StateError('Title-only requires local, non-managed Linux New');
      }
      final load = AgyLoadRequest.fromEnvironment(Platform.environment);
      if (load != null) {
        await runAgyLoadOnly(binding: binding, request: load);
        return;
      }
      String requiredEnvironment(String name) {
        final value = Platform.environment[name]?.trim();
        if (value == null || value.isEmpty) throw StateError('Supply $name');
        return value;
      }

      final sandbox = await Directory(
        requiredEnvironment('ANYWORK_AGY_SANDBOX'),
      ).resolveSymbolicLinks();
      final home = await Directory(requiredEnvironment('ANYWORK_HOME'))
          .resolveSymbolicLinks();
      final remote = AgyRemoteWorkspace.fromEnvironment();
      final projectPath =
          remote?.path ??
          await Directory(requiredEnvironment('ANYWORK_AGY_PROJECT'))
              .resolveSymbolicLinks();
      expect(p.equals(home, p.join(sandbox, 'studio-home')), isTrue);
      if (remote == null) {
        expect(p.equals(projectPath, p.join(sandbox, 'project')), isTrue);
      }
      final existing = await Directory(home).list().toList();
      expect(
        existing.map((entry) => p.basename(entry.path)),
        everyElement('studio'),
      );
      expect(await Directory(p.join(home, 'data')).exists(), isFalse);
      expect(await File(p.join(home, 'config.toml')).exists(), isFalse);
      expect(await Directory(p.join(home, 'acp')).exists(), isFalse);
      if (remote == null) {
        expect(
          await File(p.join(projectPath, 'README.md')).readAsString(),
          'Disposable ACP live acceptance workspace. No private data.\n',
        );
      } else {
        await remote.verifyFixture();
      }
      // Managed acceptance uses the product template and a verified installation
      // prepared under this isolated home's studio directory, never a raw command.
      final managed = Platform.environment['ANYWORK_AGY_MANAGED'] == '1';
      final verifySpeed = remote == null && !managed && !titleOnly;
      if (remote != null && managed) {
        throw StateError(
          'Remote process evidence requires an explicit local '
          'ANYWORK_AGY_COMMAND; managed installation is a separate scenario',
        );
      }
      final command = managed
          ? null
          : requiredEnvironment('ANYWORK_AGY_COMMAND');
      List<String>? commandArgs;
      if (command != null) {
        expect(p.isAbsolute(command), isTrue);
        expect(await File(command).exists(), isTrue);
        final arguments = jsonDecode(
          Platform.environment['ANYWORK_AGY_ARGS'] ?? '["acp"]',
        ) as List<dynamic>;
        commandArgs = arguments.cast<String>();
        if (titleOnly) {
          // No login, permission bypass, alternate config or other CLI actions.
          expect(commandArgs, orderedEquals(['acp']));
        }
        if (remote != null) {
          expect(commandArgs.first, 'acp');
          expect(commandArgs, isNot(contains('--login')));
          expect(
            commandArgs,
            isNot(contains('--dangerously-skip-permissions')),
          );
        }
      }
      final harness = await ProductionStudioHarness.start(
        binding: binding,
        artifactsEnvironmentVariable: 'ANYWORK_AGY_ARTIFACTS',
      );
      Future<void>? shutdown;
      Future<void> closeHarness() => shutdown ??= harness.close();
      addTearDown(closeHarness);
      final scene = await harness.mount(tester);
      addTearDown(scene.dispose);
      final graph = harness.graph;
      final accounts = graph.accounts.observeSummaries();
      addTearDown(accounts.release);
      final evidence = titleOnly
          ? <String, Object?>{
              'kind': 'agy-title-only',
              'platform': Platform.operatingSystem,
              'startedUtc': DateTime.now().toUtc().toIso8601String(),
              'promptCount': 0,
              'verdict': 'running',
              'shutdown': 'notAttempted',
            }
          : <String, Object?>{
              'platform': Platform.operatingSystem,
              'launchKind': managed ? 'managedAntigravityTemplate' : 'agyCli',
              'workspaceKind': remote == null ? 'local' : 'ssh',
              if (remote != null) 'remoteProjectPath': remote.path,
              if (remote != null) 'sshAlias': remote.alias,
              'coverage': remote == null ? 'text-only conversation' : 'remote file/command/STDIN/cancel/ACP child/process closure',
              'verdict': 'running',
              'overallAcceptance':
                  'Native mixed-direction regression is separate',
              'guiPid': pid,
              'promptCount': 0,
              'permission': remote == null
                  ? 'not requested by the text-only prompt; not covered'
                  : 'no auto-approval; unexpected permission requests fail',
              'cancellation': remote == null
                  ? 'not attempted'
                  : 'pending evidence',
              'preparation':
                  'public Client save/openProject; all business controls UI',
            };
      Future<void> record(String stage) async {
        evidence['stage'] = stage;
        await File(p.join(harness.artifacts.path, 'agy-live-report.json'))
            .writeAsString(
              const JsonEncoder.withIndent('  ').convert(evidence),
              flush: true,
            );
        debugPrint('AGY_LIVE $stage');
      }

      await record('production-shell-mounted');
      if (remote != null) {
        await remote.verifyServer(await graph.client.remote.listSshServers());
      }
      if (!titleOnly) {
        evidence['geometry'] = await configurePresentationWindow(
          tester,
          logicalWidth: 1440,
          logicalHeight: 1000,
          // The local speed assertion uses the produced widget values and works
          // at the current viewport, including a native integration runner on Xvfb.
          requireNativeResize: !verifySpeed,
        );
        await record('native-viewport-ready');
      }
      const serviceId = 'agy-live-acceptance';
      const serviceName = 'AGY live acceptance';
      const childProfileId = 'agy-live-acceptance-child';
      final saved = await graph.acp.save(
        AcpAccountUpdateView(
          accountId: serviceId,
          name: serviceName,
          template: managed ? AcpProviderView.antigravity : null,
          command: command,
          args: commandArgs,
        ),
        expectedDocumentRevision: null,
      );
      expect(saved.failurePhase, isNull);
      await record('isolated-account-save-returned');
      await scene.until(
        () => graph.accounts.state.value.accounts.any(
          (account) =>
              account.identity.accountId == serviceId &&
              account.acpEnabled == true,
        ),
        'saved isolated ACP definition is observed',
      );
      await record('isolated-account-directory-observed');
      if (remote != null) {
        // Isolated Studio configuration only, through the ordinary public
        // command also used by Settings. Never touch the operator's profiles.
        await graph.client.settingsCommands.saveUserAgentProfile(
          const AgentProfileDraft(
            definition: AgentDefinitionView(
              definitionId: childProfileId,
              displayName: 'AGY acceptance child',
              description: 'Synthetic remote ACP collaboration acceptance',
              whenToUse: 'Only for the disposable live acceptance workspace',
              source: '',
              revision: '',
              contentHash: '',
            ),
            binding: AcpAgentBindingView(accountId: serviceId),
          ),
        );
        await scene.until(
          () =>
              graph.client.settings.state.agentProfiles?.data.profiles.any(
                (profile) =>
                    profile.id == childProfileId &&
                    profile.enabled &&
                    profile.binding is AcpAgentBindingView,
              ) ==
              true,
          'isolated ACP child Profile is canonical before root creation',
        );
      }
      final authDemand = graph.acp.observeAuth();
      addTearDown(authDemand.release);
      const identity = AcpAccountIdentity(serviceId);
      final revision = graph.accounts.state.value
          .account(identity)!
          .acpConnectionRevision!;
      Future<void> backgroundReady() => untilObserved(graph.acp.auth, (
        resource,
      ) {
        if (resource.failure case final failure?) throw failure;
        final account = resource.value?.account(
          serviceId,
          connectionRevision: revision,
        );
        final auth = account?.state;
        if (auth is AcpRequiredState) {
          throw StateError('Existing agy credentials require explicit login');
        }
        if (account?.connection case AcpConnectionBlockedState(
          :final failure,
        )) {
          throw StateError(
            'Background connection blocked: ${failure.code.name}',
          );
        }
        if (auth is AcpFailedState) {
          throw StateError('Background auth failed: ${auth.failure.code}');
        }
        return account?.connection is AcpConnectionReadyState &&
            auth is AcpVerifiedState &&
            account?.activeOperation == null;
      }).timeout(const Duration(seconds: 90));
      await backgroundReady();
      evidence['backgroundPreparedWithoutExplicitCheck'] = true;
      final accountProcesses = !titleOnly && !managed && Platform.isLinux
          ? AgyLocalProcesses()
          : null;
      LinuxProcessIdentity? sharedInstance;
      if (accountProcesses != null) {
        final original = await accountProcesses.accountInstance(command!);
        evidence['initialAccountInstance'] = original.evidence;
        final current = LinuxProcessIdentity.parse(
          await File('/proc/${original.pid}/stat').readAsString(),
        );
        expect(original.sameProcess(current), isTrue);
        // Fault injection targets only this isolated GUI's own current ACP child.
        expect(Process.killPid(original.pid, ProcessSignal.sigkill), isTrue);
        await scene.until(
          () =>
              graph.acp.auth.value.value
                      ?.account(serviceId, connectionRevision: revision)
                      ?.connection
                  is AcpConnectionRetryingState,
          'unexpected agy exit schedules automatic reconnect',
          timeout: const Duration(seconds: 30),
        );
        await backgroundReady();
        sharedInstance = await accountProcesses.accountInstance(command);
        expect(sharedInstance.sameProcess(original), isFalse);
        evidence['reconnectedAccountInstance'] = sharedInstance.evidence;
        evidence['automaticReconnectWithoutLoginOrPromptReplay'] = true;
      }
      await record(
        managed ? 'managed-connection-verified' : 'account-background-ready',
      );
      final project = await harness.openProject(
        scene,
        projectPath,
        sshAlias: remote?.alias,
      );
      await record('isolated-project-opened');
      await scene.until(
        () => find.byType(StartModelSelectorView).evaluate().length == 1,
        'project start page exposes the unified model selector',
      );
      await record('project-model-selector-visible');
      if (!titleOnly) await scene.capture('ordinary-start-card');
      await tester.tap(
        find.descendant(
          of: find.byType(StartModelSelectorView),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(serviceName).last);
      await scene.until(
        () => find.byType(AcpStartComposerView).evaluate().length == 1,
        'ACP service selected through production start page',
      );
      await scene.until(
        () {
          final phase =
              graph.client.drafts.startDraft.state.acpPreparations[project.id];
          if (phase is AcpDraftFailed) {
            throw StateError('ACP draft failed: ${phase.error}');
          }
          return phase is AcpDraftReady;
        },
        'real ACP draft is configurable before first input',
        timeout: const Duration(seconds: 90),
      );
      final initialPreparation =
          graph.client.drafts.startDraft.state.acpPreparations[project.id]
              as AcpDraftReady;
      var owner = graph.client.acpSessions.conversationForThread(
        initialPreparation.threadId,
      )!;
      expect(owner.state.lastCompleted, isNull);
      if (titleOnly) {
        await runAgyTitleOnly(
          scene: scene,
          owner: owner,
          project: project,
          evidence: evidence,
          record: record,
          closeHarness: closeHarness,
        );
        return;
      }
      evidence['initialConfig'] = _configuration(owner.state);
      await scene.capture('agy-draft-ready');
      if (accountProcesses != null) {
        final current = await accountProcesses.accountInstance(command!);
        expect(current.sameProcess(sharedInstance!), isTrue);
        evidence['draftReusesBackgroundInstance'] = current.evidence;
      }

      var pendingObserved = false;
      final configWatch = owner.source.watch((state) {
        if (state.configPending) pendingObserved = true;
      });
      addTearDown(configWatch.cancel);
      final options = owner.state.configOptions;
      if (remote != null) {
        expect(
          options,
          isNotNull,
          reason: 'Remote acceptance requires real configOptions',
        );
      }
      if (options != null) {
        final selects = options.where((option) {
          final kind = option.kind;
          return kind is AcpSelectConfigView &&
              _values(kind).any((value) => value.value != kind.currentValue);
        }).toList();
        expect(selects, isNotEmpty, reason: 'No real alternate select config');
        final option = selects.reduce(
          (a, b) =>
              _values(a.kind as AcpSelectConfigView).length <=
                  _values(b.kind as AcpSelectConfigView).length
              ? a
              : b,
        );
        final kind = option.kind as AcpSelectConfigView;
        final alternate = _values(kind)
            .firstWhere((value) => value.value != kind.currentValue);
        await tester.tap(
          find.descendant(
            of: find.byKey(
              ValueKey(AcpViewKeyValues.configControl(option.id.value)),
            ),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
        await scene.capture('agy-draft-options');
        await tester.tap(
          find.byKey(
            ValueKey(
              AcpViewKeyValues.configChoice(
                option.id.value,
                alternate.value.value,
              ),
            ),
          ),
        );
        await scene.until(
          () => !owner.state.configPending && pendingObserved,
          'real configuration request leaves pending',
        );
        expect(owner.state.configError, isNull);
        final confirmed = owner.state.configOptions!.singleWhere(
          (value) => value.id == option.id,
        );
        expect(
          (confirmed.kind as AcpSelectConfigView).currentValue,
          alternate.value,
        );
        evidence['changedConfigId'] = option.id.value;
        evidence['changedConfigValue'] = alternate.value.value;
      } else {
        final modes = owner.state.modes!;
        final alternate = modes.availableModes.firstWhere(
          (mode) => mode.id != modes.currentModeId,
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey(AcpViewKeyValues.configLegacyMode)),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              AcpViewKeyValues.configChoice(
                AcpViewKeyValues.configLegacyMode,
                alternate.id.value,
              ),
            ),
          ),
        );
        await scene.until(
          () => !owner.state.configPending && pendingObserved,
          'real legacy mode request leaves pending',
        );
        expect(owner.state.configError, isNull);
        expect(owner.state.modes!.currentModeId, alternate.id);
        evidence['changedModeId'] = alternate.id.value;
      }
      expect(owner.state.error, isNull);
      expect(owner.state.activeRun, isNull);
      expect(owner.state.lastCompleted, isNull);
      evidence['configPendingObserved'] = pendingObserved;
      evidence['confirmedConfig'] = _configuration(owner.state);
      await scene.capture('agy-draft-configured');
      await record('real-configuration-confirmed');
      if (remote == null) {
        final previousOwner = owner;
        final previousConfig = owner.configIntents;
        await tester.tap(find.byKey(StudioDriverKeys.sessionWorkspaceMode));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            StudioDriverKeys.sessionWorkspaceModeOption(
              ThreadWorkspaceMode.worktree.id,
            ),
          ),
        );
        await scene.until(
          () {
            final phase = graph
                .client
                .drafts
                .startDraft
                .state
                .acpPreparations[project.id];
            if (phase is AcpDraftFailed ||
                phase is AcpDraftNeedsConfiguration) {
              throw StateError('Worktree draft failed: $phase');
            }
            return phase is AcpDraftReady &&
                phase.threadId != initialPreparation.threadId;
          },
          'worktree change prepares a new draft and confirms retained configuration',
          timeout: const Duration(seconds: 90),
        );
        final phase =
            graph.client.drafts.startDraft.state.acpPreparations[project.id]
                as AcpDraftReady;
        owner = graph.client.acpSessions.conversationForThread(phase.threadId)!;
        expect(
          owner.state.remoteSessionId,
          isNot(previousOwner.state.remoteSessionId),
        );
        expect(owner.configIntents, previousConfig);
        expect(
          graph.client.acpSessions.conversationForThread(
            initialPreparation.threadId,
          ),
          isNull,
        );
        expect(owner.state.lastCompleted, isNull);
        evidence['directoryChange'] = {
          'oldRemoteSessionId': previousOwner.state.remoteSessionId?.value,
          'newRemoteSessionId': owner.state.remoteSessionId?.value,
          'configurationReapplied': true,
        };
        await scene.capture('agy-draft-worktree-ready');
      }
      final preparedRemoteSessionId = owner.state.remoteSessionId;
      final preparedThreadId = owner.state.target!.threadId;
      await record('draft-prepared-before-first-send');
      final marker = 'ACP284LIVEOK${DateTime.now().millisecondsSinceEpoch}';
      final prompt = remote?.promptA('${marker}A') ?? 'hi';
      final startupMarker = '${marker}READY';
      const speedPrompt =
          'Respond with a numbered list of 40 original short '
          'sentences about clouds. Reply only with the list. Do not use tools.';
      final observedSpeeds = <AcpTextPerformanceView>{};
      if (verifySpeed) {
        final samples = owner.source.watch((state) {
          if (state.activeRun != null || state.sendPending) {
            if (state.textPerformance case final sample?) {
              observedSpeeds.add(sample);
            }
          }
        });
        addTearDown(samples.cancel);
      }
      final startupPrompt = remote == null
          ? (verifySpeed ? speedPrompt : 'hi')
          : 'Reply with exactly $startupMarker and nothing else. '
                'Do not call tools, run commands, use the network, or read or write any files.';
      evidence['promptCount'] = 1;
      await tester.enterText(
        find.descendant(
          of: find.byType(AcpStartComposerView),
          matching: find.byType(TextField),
        ),
        startupPrompt,
      );
      await tester.pumpAndSettle();
      await scene.capture('agy-live-start-card');
      await tester.tap(
        find.byKey(ValueKey(AcpViewKeyValues.startSubmit(project.id))),
      );
      await scene.until(
        () {
          final failure = graph.client.drafts.attachments.state
              .newThread(project.id)
              .failure;
          if (failure != null) throw StateError('ACP create failed: $failure');
          return find.byType(AcpComposerConnector).evaluate().length == 1;
        },
        'the first send creates a session and admits its prompt',
        // A live server starts its external harness here. It can take longer
        // than the local fixture's default deadline; this never retries new.
        timeout: const Duration(seconds: 90),
      );
      final threadId = tester
          .widget<AcpComposerConnector>(find.byType(AcpComposerConnector))
          .threadId;
      expect(threadId, preparedThreadId);
      expect(
        graph.client.acpSessions.conversationForThread(threadId),
        same(owner),
      );
      expect(owner.state.remoteSessionId, preparedRemoteSessionId);
      await scene.until(
        () => owner.state.ready && !owner.state.openPending,
        'real ACP owner ready',
      );
      final metadata = graph.client.threadDirectory.observeThread(threadId);
      await scene.until(
        () => metadata.state.value.frame?.row != null,
        'committed ACP directory is observable',
      );
      final row = metadata.state.value.frame!.row!;
      final reference = (row.backend as AcpAgentBackendView).reference;
      expect(reference.acpSessionId, preparedRemoteSessionId!.value);
      if (remote == null) {
        expect(row.workspaceMode, ThreadWorkspaceMode.worktree);
        expect(reference.cwd, row.workspacePath);
        expect(reference.cwd, isNot(projectPath));
        expect(
          await File(p.join(reference.cwd, 'README.md')).readAsString(),
          'Disposable ACP live acceptance workspace. No private data.\n',
        );
        evidence['committedWorktree'] = {
          'cwd': reference.cwd,
          'samePreparedSession': true,
        };
      }
      await metadata.release();
      void checkOwner() {
        expect(graph.client.drafts.composer(threadId).state.error, isNull);
        expect(owner.state.error, isNull);
        expect(owner.state.observationGap, isNull);
        expect(owner.state.disconnected, isFalse);
        expect(owner.state.observationEnded, isFalse);
      }

      checkOwner();
      await record('first-send-reused-prepared-session');
      try {
        await scene.until(
          () {
            checkOwner();
            if (owner.state.pendingPermissions.isNotEmpty) {
              throw StateError(
                'Text-only startup unexpectedly requested permission',
              );
            }
            return owner.state.lastCompleted != null &&
                owner.state.activeRun == null &&
                !owner.state.sendPending;
          },
          'startup prompt completes before configuring the next request',
          timeout: const Duration(seconds: 120),
        );
      } finally {
        evidence['startupState'] = {
          'error': owner.state.error?.toString(),
          'activeRun': owner.state.activeRun?.sequence.toString(),
          'completed': owner.state.lastCompleted != null,
          'sendPending': owner.state.sendPending,
          'permissions': owner.state.pendingPermissions.length,
          'content': owner.state.content
              .map((item) => item.runtimeType.toString())
              .toList(),
          'toolCalls': [
            for (final item
                in owner.state.content.whereType<AcpConversationToolItem>())
              {'title': item.fields.title, 'status': item.fields.status?.name},
          ],
        };
        await scene.capture('agy-live-startup-observed');
        await record('startup-prompt-observed');
      }
      checkOwner();
      evidence['startupMessages'] = [
        for (final item
            in owner.state.content.whereType<AcpConversationMessageItem>())
          {
            'kind': item.kind.name,
            'visibleText': [
              for (final block in mapAcpMessageBlocks(item, itemId: 'startup'))
                if (block case AcpTextBlockPresentation(:final text)) text,
            ].join(),
            'audiences': [
              for (final chunk in item.chunks)
                chunk.content.annotations?.audience
                    ?.map((role) => role.name)
                    .toList(),
            ],
          },
      ];
      if (remote == null) {
        final user = owner.state.content
            .whereType<AcpConversationMessageItem>()
            .singleWhere(
              (item) => item.kind == AcpConversationMessageKind.user,
            );
        final blocks = mapAcpMessageBlocks(user, itemId: 'startup-user');
        expect(blocks, hasLength(1));
        expect((blocks.single as AcpTextBlockPresentation).text, startupPrompt);
        final visiblePrompt = find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is AcpTimelineEntryView &&
                widget.item is AcpTimelineUserMessage,
          ),
          matching: find.text(startupPrompt, findRichText: true),
        );
        // A streamed reply can move the user's row outside the lazy list.
        await tester.scrollUntilVisible(
          visiblePrompt,
          250,
          scrollable: find
              .descendant(
                of: find.byType(AcpConversationContentView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(visiblePrompt, findsOneWidget);
        expect(owner.state.lastCompleted!.completionSequence, BigInt.one);
      }
      expect(
        owner.state.content.whereType<AcpConversationMessageItem>(),
        isNotEmpty,
      );
      expect(owner.state.content.whereType<AcpConversationToolItem>(), isEmpty);
      evidence['startupNotifications'] = owner.state.content
          .whereType<AcpConversationUpdateItem>()
          .map((item) => item.update.runtimeType.toString())
          .toList();
      if (verifySpeed) {
        final performance = owner.state.lastCompleted!.textPerformance;
        expect(
          performance,
          isNotNull,
          reason: 'Agy produced no text speed sample',
        );
        expect(owner.state.textPerformance, performance);
        final finalSpeed =
            performance!.estimatedOutputTokens *
            1000 /
            performance.responseMillis;
        await tester.pump();
        final readout = tester.widget<TokenThroughputReadout>(
          find.byWidgetPredicate(
            (widget) => widget is TokenThroughputReadout && widget.estimated,
          ),
        );
        expect(readout.tokensPerSecond, closeTo(finalSpeed, 0.0001));
        expect(observedSpeeds, isNotEmpty, reason: 'No pre-completion speed');
        final statistics = graph.statisticsRepository;
        final demand = statistics.acquireVisibleDemand();
        addTearDown(demand.release);
        List<StatisticsSample>? samples() => statistics.state.snapshot?.history
            .where(
              (sample) =>
                  sample.threadId == threadId && sample.isAcpTextEstimate,
            )
            .toList();
        await scene.until(
          () => samples()?.isNotEmpty == true,
          'ACP speed reaches production statistics',
        );
        final sample = samples()!.single;
        expect(sample.completionTokens, performance.estimatedOutputTokens);
        expect(sample.totalResponseMillis, performance.responseMillis);
        expect(sample.tokensPerSecond, closeTo(finalSpeed, 0.0001));
        evidence['textPerformance'] = {
          'liveSamples': observedSpeeds.length,
          'estimatedOutputTokens': performance.estimatedOutputTokens,
          'responseMillis': performance.responseMillis,
          'tokensPerSecond': finalSpeed,
        };
        demand.release();
        await record('real-agy-speed-visible-and-recorded');
      }
      final draft = graph.client.drafts.composer(threadId);
      expect(draft.state.draft, isEmpty);
      await tester.enterText(
        find.descendant(
          of: find.byType(AcpConversationComposerView),
          matching: find.byType(TextField),
        ),
        prompt,
      );
      final caps = owner.state.capabilities!;
      evidence['capabilities'] = {
        'image': caps.image,
        'audio': caps.audio,
        'embeddedContext': caps.embeddedContext,
        'loadSession': caps.loadSession,
        'listSessions': caps.listSessions,
        'resumeSession': caps.resumeSession,
      };
      await scene.capture('agy-live-configured-shell');
      await record('first-send-reused-draft-and-startup-prompt-completed');

      expect(
        graph.client.project.state.projects!.values.any(
          (item) => item.id == project.id,
        ),
        isTrue,
      );
      await runAgyAcceptancePhases(
        scene: scene,
        owner: owner,
        remote: remote,
        command: command,
        marker: marker,
        childProfileId: childProfileId,
        evidence: evidence,
        record: record,
        closeHarness: closeHarness,
      );
      if (accountProcesses != null) {
        await accountProcesses.verifyClosed();
        evidence['accountProcessExitChecks'] = accountProcesses.exitEvidence;
        await record('account-instances-reclaimed');
      }
    },
    // A bounded startup prompt, then three 240-second phases, setup and closure.
    timeout: const Timeout(Duration(minutes: 16)),
  );
}

List<AcpSelectOptionView> _values(AcpSelectConfigView kind) =>
    switch (kind.options) {
      AcpUngroupedOptionsView(:final options) => options,
      AcpGroupedOptionsView(:final groups) => [
        for (final group in groups) ...group.options,
      ],
    };

Map<String, Object?> _configuration(AcpConversationState state) => {
  'options': state.configOptions
      ?.map(
        (option) => {
          'id': option.id.value,
          'name': option.name,
          'kind': switch (option.kind) {
            AcpBooleanConfigView() => 'boolean',
            AcpSelectConfigView() => 'select',
          },
          'current': switch (option.kind) {
            AcpBooleanConfigView(:final currentValue) => currentValue,
            AcpSelectConfigView(:final currentValue) => currentValue.value,
          },
          if (option.kind case final AcpSelectConfigView kind)
            'available': _values(kind)
                .map((value) => {'id': value.value.value, 'name': value.name})
                .toList(),
        },
      )
      .toList(),
  'currentMode': state.modes?.currentModeId.value,
  'availableModes': state.modes?.availableModes
      .map((mode) => {'id': mode.id.value, 'name': mode.name})
      .toList(),
};
