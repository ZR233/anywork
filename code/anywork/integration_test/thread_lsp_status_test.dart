import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'support/production_studio_harness.dart';
import 'support/sidebar_fixture.dart';

// Only native boundaries live here: real FRB topic/command round trips and LSP
// process reclamation. Presentation, menu lifecycle and command state are
// covered by the production component tests in test/ui.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native LSP topics and reset preserve directory binding', (
    _,
  ) async {
    expect(Platform.operatingSystem, 'linux');
    final sandbox = Directory(
      _requiredEnvironment('ANYWORK_THREAD_LSP_SANDBOX'),
    );
    final root = await sandbox.resolveSymbolicLinks();
    final home = _requiredEnvironment('ANYWORK_HOME');
    final projectAPath = _requiredEnvironment('ANYWORK_THREAD_LSP_PROJECT_A');
    final projectBPath = _requiredEnvironment('ANYWORK_THREAD_LSP_PROJECT_B');
    final output = _requiredEnvironment('ANYWORK_THREAD_LSP_OUTPUT');
    final fixture = _requiredEnvironment('ANYWORK_THREAD_LSP_FIXTURE');
    expect(p.equals(home, p.join(root, 'studio-home')), isTrue);
    for (final entry in {
      projectAPath: 'project-a',
      projectBPath: 'project-b',
      output: 'artifacts',
    }.entries) {
      expect(p.equals(entry.key, p.join(root, entry.value)), isTrue);
      expect(
        await FileSystemEntity.type(entry.key),
        FileSystemEntityType.notFound,
      );
    }
    // The native launcher may already own runtime.lock and its startup log.
    // Freshness is established by the external owner before launching it.
    await for (final entry in sandbox.list()) {
      expect(p.equals(entry.path, home), isTrue);
    }
    expect(await File(fixture).exists(), isTrue);
    await Directory(home).create();
    final projectA = await Directory(projectAPath).create();
    final projectB = await Directory(projectBPath).create();
    await Directory(output).create();
    final coordinateA = p.join(root, 'lsp-a-process.json');
    final coordinateB = p.join(root, 'lsp-b-process.json');
    await _writeLspConfig(
      project: projectA,
      displayName: 'A',
      command: fixture,
      args: ['--lsp-stdio', '--coord-file', coordinateA],
    );
    await _writeLspConfig(
      project: projectB,
      displayName: 'B',
      command: p.join(root, 'missing-lsp-command'),
    );

    ProductionStudioHarness? harness;
    SidebarProviderFixture? provider;
    BridgeTopicLeaseBundle? topics;
    AccountDemand? accounts;
    final evidence = <String, Object?>{'platform': Platform.operatingSystem};
    addTearDown(() async {
      final failures = <String>[];
      for (final close in <Future<void> Function()>[
        if (topics != null) topics.release,
        if (accounts != null)
          () async {
            accounts!.release();
          },
        if (harness != null) harness.close,
        if (provider != null) provider.close,
      ]) {
        try {
          await close();
        } catch (error) {
          failures.add(error.toString());
        }
      }
      final remaining = <Object?>[];
      for (final raw in evidence['ownedLspProcesses'] as List? ?? const []) {
        final process = (raw as Map).cast<String, Object?>();
        if (await _sameLinuxProcess(process)) remaining.add(process);
      }
      evidence['ownedLspProcessesStillPresent'] = remaining;
      evidence['cleanupFailures'] = failures;
      await File(p.join(output, 'thread-lsp-status.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(evidence),
        flush: true,
      );
      expect(failures, isEmpty);
      expect(
        remaining,
        isEmpty,
        reason: 'Production shutdown must reclaim LSP descendants',
      );
    });

    try {
      provider = await SidebarProviderFixture.start();
      harness = await ProductionStudioHarness.start(
        binding: binding,
        artifactsEnvironmentVariable: 'ANYWORK_THREAD_LSP_OUTPUT',
      );
      final graph = harness.graph;
      accounts = graph.accounts.observeSummaries();
      await graph.accounts.state.waitFor((state) => state.loaded);
      await graph.accounts.loadTemplates();
      final template = graph.accounts.state.value.templates.templates
          .where((candidate) => candidate.protocol == 'open_ai_compatible')
          .single;
      const accountId = 'thread-lsp-local-fixture';
      const identity = NativeAccountIdentity(accountId);
      final created = await graph.accounts.create(
        CreateAccountCommand(
          identity: identity,
          name: 'Thread LSP local fixture',
          protocol: template.protocol,
          templateId: template.id,
          baseUrl: '${provider.origin}/v1',
          secret: const AccountSecretCommand.clear(),
          customModels: const [
            AccountModelCommand(
              modelId: SidebarFixture.modelId,
              displayName: 'Local fixture',
              wireApi: 'responses',
              contextWindow: 65536,
              maxOutputTokens: 4096,
            ),
          ],
        ),
      );
      expect(created.error, isNull);
      expect(created.observed, isTrue);
      const route = ModeModelRouteView(
        modeId: ThreadModeId.simple,
        accountId: accountId,
        modelId: SidebarFixture.modelId,
        effort: '',
      );
      final a = await _openProject(graph, projectAPath);
      final threadA = await _submitRoot(
        graph,
        a.id,
        inputId: 'lsp-a',
        route: route,
      );
      final b = await _openProject(graph, projectBPath);
      final threadB = await _submitRoot(
        graph,
        b.id,
        inputId: 'lsp-b',
        route: route,
      );
      topics = graph.client.channels.acquireTopics([
        ThreadLspTopic(threadId: threadA.id),
        ThreadLspTopic(threadId: threadB.id),
      ]);
      final storeA = graph.client.existingThreadLsp(threadA.id)!;
      final storeB = graph.client.existingThreadLsp(threadB.id)!;
      final stateA = await storeA.source
          .waitFor(
            (state) =>
                state.value?.servers.singleOrNull?.state is LspAvailableState,
          )
          .timeout(const Duration(seconds: 30));
      final stateB = await storeB.source
          .waitFor(
            (state) =>
                state.value?.servers.singleOrNull?.state is LspUnavailableState,
          )
          .timeout(const Duration(seconds: 30));
      final snapshotA = stateA.value!;
      final snapshotB = stateB.value!;
      final serverA = snapshotA.servers.single;
      final serverB = snapshotB.servers.single;
      expect(serverA.id, serverB.id);
      expect(serverA.configurationPath, contains(projectAPath));
      expect(serverB.configurationPath, contains(projectBPath));
      expect(snapshotA.bindingId, isNotNull);
      expect(snapshotB.bindingId, isNot(snapshotA.bindingId));
      final processA = await _readCoord(coordinateA);
      _recordOwnedProcesses(evidence, processA, threadA.id, 'A');
      evidence['before'] = [_snapshotJson(snapshotA), _snapshotJson(snapshotB)];

      await _writeLspConfig(
        project: projectB,
        displayName: 'B recovered',
        command: fixture,
        args: ['--lsp-stdio', '--coord-file', coordinateB],
      );
      await graph.client.directoryCommands.resetThreadLspServer(
        threadId: threadB.id,
        bindingId: snapshotB.bindingId!,
        serverId: serverB.id,
      );
      final recovered = await storeB.source
          .waitFor(
            (state) =>
                state.value?.servers.singleOrNull?.state is LspAvailableState,
          )
          .timeout(const Duration(seconds: 30));
      expect(recovered.value!.bindingId, snapshotB.bindingId);
      expect(_snapshotJson(storeA.state.value!), _snapshotJson(snapshotA));
      expect(await _readCoord(coordinateA), processA);
      _recordOwnedProcesses(
        evidence,
        await _readCoord(coordinateB),
        threadB.id,
        'B',
      );
      evidence['recovered'] = _snapshotJson(recovered.value!);
    } catch (error) {
      evidence['failure'] = error.toString();
      rethrow;
    }
  });
}

Future<StudioProject> _openProject(AppGraph graph, String path) async {
  await graph.client.directoryCommands.openProject(path);
  final id = graph.client.selection.state.selectedProjectId;
  final state = await graph.client.project.source.waitFor(
    (state) =>
        state.projects?.values.any((project) => project.id == id) == true,
  );
  return state.projects!.values.singleWhere((project) => project.id == id);
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) throw StateError('Supply $name');
  return value;
}

Future<File> _writeLspConfig({
  required Directory project,
  required String displayName,
  required String command,
  List<String> args = const [],
}) async {
  final directory = Directory(p.join(project.path, '.anywork', 'lsp'));
  await directory.create(recursive: true);
  final config = File(p.join(directory.path, 'thread-lsp-status-probe.toml'));
  await config.writeAsString(
    [
      'schema_version = 1',
      'id = "thread-lsp-status-probe"',
      'display_name = ${jsonEncode(displayName)}',
      'command = ${jsonEncode(command)}',
      'args = ${jsonEncode(args)}',
      'language_ids = ["anywork-thread-lsp-fixture"]',
      'extensions = ["lspfixture"]',
      'detection = []',
      '',
    ].join('\n'),
    flush: true,
  );
  return config;
}

Future<StudioThread> _submitRoot(
  AppGraph graph,
  String workspaceId, {
  required String inputId,
  required ModeModelRouteView route,
}) async {
  final result = await graph.client.threadCommands.submitNewThread(
    workspaceId: workspaceId,
    input: StudioPromptInput(
      inputId: inputId,
      text: 'Create an isolated LSP status test session.',
      attachmentDraftIds: const [],
    ),
    mode: ThreadModeId.simple,
    route: route,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    onProgress: (_) {},
  );
  if (result == null) {
    throw StateError('The local fixture did not create a Native Thread');
  }
  return result.thread;
}

Map<String, Object?> _snapshotJson(ThreadLspStateSnapshot snapshot) => {
  'threadId': snapshot.threadId,
  'revision': snapshot.revision,
  'bindingId': snapshot.bindingId,
  'servers': snapshot.servers
      .map(
        (server) => {
          'id': server.id,
          'displayName': server.displayName,
          'configurationPath': server.configurationPath,
          'phase': server.phase,
          'state': _serverStateJson(server.state),
        },
      )
      .toList(growable: false),
};

Map<String, Object?> _serverStateJson(LspServerState state) => switch (state) {
  LspAvailableState(
    :final checkedAt,
    :final diagnosticCount,
    :final activity,
  ) =>
    {
      'kind': 'available',
      'checkedAt': checkedAt,
      'diagnosticCount': diagnosticCount,
      'activity': activity.runtimeType.toString(),
    },
  LspUnavailableState(
    :final checkedAt,
    :final code,
    :final message,
    :final retryable,
  ) =>
    {
      'kind': 'unavailable',
      'checkedAt': checkedAt,
      'code': code,
      'message': message,
      'retryable': retryable,
    },
  LspCheckingState(:final message) => {'kind': 'checking', 'message': message},
  LspDisabledState(:final message) => {'kind': 'disabled', 'message': message},
};

Future<Map<String, Object?>> _readCoord(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('The expected LSP process record is missing: $path');
  }
  return (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
}

void _recordOwnedProcesses(
  Map<String, Object?> evidence,
  Map<String, Object?> coord,
  String threadId,
  String generation,
) {
  final processes = evidence.putIfAbsent(
    'ownedLspProcesses',
    () => <Map<String, Object?>>[],
  ) as List<Map<String, Object?>>;
  for (final role in ['lsp', 'grandchild']) {
    final pid = coord['${role}Pid'];
    final startTicks = coord['${role}StartTicks'];
    if (pid is! int || startTicks is! int) {
      throw StateError(
        'The LSP fixture omitted PID/start-time identity for $role',
      );
    }
    processes.add({
      'threadId': threadId,
      'generation': generation,
      'role': role,
      'pid': pid,
      'startTicks': startTicks,
    });
  }
}

Future<bool> _sameLinuxProcess(Map<String, Object?> process) async {
  if (Platform.operatingSystem != 'linux') return false;
  final pid = process['pid'] as int;
  final expectedStartTicks = process['startTicks'] as int;
  final stat = File('/proc/$pid/stat');
  if (!await stat.exists()) return false;
  final content = await stat.readAsString();
  final commandEnd = content.lastIndexOf(')');
  if (commandEnd < 0) return true;
  final fields = content.substring(commandEnd + 1).trim().split(RegExp(r'\s+'));
  // The suffix starts at proc stat field 3; starttime is field 22.
  if (fields.length <= 19) return true;
  return int.tryParse(fields[19]) == expectedStartTicks;
}
