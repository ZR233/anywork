import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/composition/workspace_conversation_binding.dart';
import 'package:anywork/src/app/composition/workspace_archive_binding.dart';
import 'package:anywork/src/app/lifecycle/exit_participant.dart';
import 'package:anywork/src/features/status/status.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../../anywork_client/test/support/drafts_native_fixture.dart';
import '../../../../anywork_client/test/support/modes_fixture.dart';
import '../../../../anywork_client/test/support/profile_native_pin.dart';
import '../../../../anywork_client/test/support/profile_recovery_port.dart';
import '../../../../anywork_client/test/support/timeline_transport.dart';
import 'selector_configuration_port.dart';
import 'selector_conversation_port.dart';
import 'selector_directory_port.dart';
import 'selector_models_port.dart';

/// A narrow application assembly for selector/directory contracts. All domain
/// state and operations use the real public factories. Native ports supply only
/// declared material and gates; there is no legacy Client facade or store setter.
final class SelectorEnvironment {
  SelectorEnvironment() {
    operations = OperationRegistry(clientId: 'selectors', budget: budget);
    final modelsAssembly = createModelsRepository(
      port: modelsPort,
      budget: budget,
    );
    models = modelsAssembly.repository;
    configuration = createConfigurationRepository(
      port: configurationPort,
      budget: budget,
      operations: operations,
      modelTargets: modelsAssembly.targets,
    );
    modes = createModesRepository(
      port: modesPort,
      budget: budget,
      operations: operations,
    );
    recovery = createRecoveryRepository(
      port: recoveryPort,
      budget: budget,
      operations: operations,
    );
    final conversationAssembly = createConversationRepository(
      port: conversationPort,
      commands: commands,
      context: context,
      timeline: timeline,
      budget: budget,
      operations: operations,
      agentDirectory: () => workspace.agents,
    );
    conversations = conversationAssembly.repository;
    demand = conversationAssembly.demand;
    final workspaceAssembly = createWorkspaceRepository(
      port: directory,
      budget: budget,
      operations: operations,
      recovery: recovery.state,
      archiveCapture: archive,
    );
    workspace = workspaceAssembly.repository;
    context.metadata = workspace.thread;
    final draftsAssembly = createDraftsRepository(
      configuration: configuration,
      workspace: workspace,
      submissionSelection: workspaceAssembly.submissionSelection,
      conversations: conversations,
      conversationDemand: demand,
      conversationCommands: commands,
      attachments: attachments,
      creations: creations,
      binary: binary,
      budget: budget,
      operations: operations,
    );
    drafts = draftsAssembly.repository;
    archive.bind(
      conversations: conversationAssembly.archive,
      drafts: draftsAssembly.archive,
    );
    binding = WorkspaceConversationBinding(
      workspace: workspace,
      demand: demand,
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: domainOverrides,
    );
  }

  List<Override> get domainOverrides => [
    configurationRepositoryProvider.overrideWithValue(configuration),
    modelsRepositoryProvider.overrideWithValue(models),
    modesRepositoryProvider.overrideWithValue(modes),
    workspaceRepositoryProvider.overrideWithValue(workspace),
    conversationRepositoryProvider.overrideWithValue(conversations),
    draftsRepositoryProvider.overrideWithValue(drafts),
    recoveryRepositoryProvider.overrideWithValue(recovery),
    applicationEditProducerRegistryProvider.overrideWithValue(edits),
    prepareConversationPresentationProvider.overrideWithValue((_) async {}),
  ];

  final budget = ResourceBudget();
  final configurationPort = SelectorConfigurationPort();
  final modelsPort = SelectorModelsPort();
  final modesPort = FixtureModesPort();
  final recoveryPort = ProfileRecoveryPort();
  final directory = SelectorDirectoryPort();
  final context = FixtureConversationContext();
  final conversationPort = SelectorConversationPort();
  final commands = SelectorCommands();
  final timeline = TimelineOpenQueue();
  final attachments = DraftAdmissionPort();
  final creations = DraftCreationPort();
  final binary = DraftBinaryPort();
  final edits = ApplicationEditProducerRegistry();
  final archive = WorkspaceArchiveBinding();
  late final OperationRegistry operations;
  late final ConfigurationRepository configuration;
  late final ModelsRepository models;
  late final ModesRepository modes;
  late final RecoveryRepository recovery;
  late final WorkspaceRepository workspace;
  late final ConversationRepository conversations;
  late final ConversationDemand demand;
  late final DraftsRepository drafts;
  late final WorkspaceConversationBinding binding;
  late final ProviderContainer container;
  ProviderSubscription<Object?>? _catalog;
  bool _closed = false;

  Future<void> establish({bool catalog = true}) async {
    final configReads = Future.wait([
      configuration.loadAccountsPage(),
      configuration.loadProfilesPage(),
    ]);
    final modelRead = models.loadAccountsPage();
    final modeRead = modes.loadModesPage();
    final projects = workspace.loadProjectsPage();
    await Future.wait([
      configurationPort.base.feed.listened.future,
      configurationPort.base.profilesFeed.listened.future,
      modelsPort.base.feed.listened.future,
      modesPort.feed.listened.future,
    ]);
    modesPort.catalogs[1] = const [
      ThreadModeDescriptorRead(
        id: ThreadModeId.simple,
        displayName: ReadText.inline(text: '简洁'),
        description: ReadText.inline(text: 'Simple'),
        order: 0,
        hasWorkflow: false,
        readOnly: true,
      ),
      ThreadModeDescriptorRead(
        id: ThreadModeId.task,
        displayName: ReadText.inline(text: '任务'),
        description: ReadText.inline(text: 'Task'),
        order: 1,
        hasWorkflow: true,
        readOnly: true,
      ),
    ];
    configurationPort.base.baseline();
    modelsPort.base.baseline();
    modesPort.feed.emit(
      ModeCatalogFrame.data(
        deliverySequence: 1,
        event: ModeCatalogEvent.baseline(
          identity: profileIdentity(
            modesPort.feed.feedId,
            modesFixtureOrigin,
            ProductResource.modeCatalog,
          ),
          stamp: profileStamp(modesFixtureOrigin, 1),
          value: ModeCatalogBaseline(
            header: modeCatalogHeader(1),
            collection: modeCollection(1, 2),
          ),
        ),
      ),
    );
    await Future.wait([
      configReads,
      modelRead,
      modeRead,
      projects,
      recoveryPort.establish(recovery),
    ]);
    await recovery.loadSourceStatus();
    await configuration.loadModeRoutes();
    if (catalog) {
      _catalog = container.listen(selectorCatalogViewModelProvider, (_, _) {});
      await container.read(selectorCatalogViewModelProvider.future);
      await container
          .read(selectorCatalogViewModelProvider.notifier)
          .loadMore();
    }
  }

  Future<void> selectStart() async {
    expect(
      await workspace.beginNewThread('project').result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    await prepareStart();
  }

  /// Supplies a single explicit original native resolve result. The requested
  /// mode/model/effort remain in the production draft and are not applied here.
  Future<void> prepareStart({
    ModelSelection route = selectorInitialRoute,
  }) async {
    final work = drafts.start('project').prepareRoute();
    final opening = configurationPort.opens.isEmpty
        ? await configurationPort.firstStartOpen.future
        : configurationPort.opens.last;
    final pin = opening.native ?? opening.accept();
    final pending = pin.calls
        .where((call) => !call.reply.isCompleted)
        .firstOrNull;
    final call = pending ?? await pin.called(pin.calls.length);
    call.reply.complete(
      StartRouteRead.ready(
        sources: opening.sources,
        query: call.query,
        intent: call.query is SelectModelStartRouteQuery
            ? call.query.intent.copyWith(
                model: (call.query as SelectModelStartRouteQuery).selected,
                effort: route.effort,
              )
            : call.query.intent,
        route: route,
        defaults: selectorDefaults,
      ),
    );
    await work;
  }

  Future<void> selectThread(String id, {bool bind = true}) async {
    expect(
      await workspace.selectThread(id).result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    if (bind) binding.start();
    if (bind) {
      await waitLatest(
        conversations.active,
        (session) => session?.threadId == id,
      );
    }
  }

  Future<void> close({bool checkBudget = true}) async {
    if (_closed) return;
    _closed = true;
    _catalog?.close();
    container.dispose();
    binding.seal();
    drafts.seal();
    workspace.seal();
    conversations.seal();
    configuration.seal();
    models.seal();
    modes.seal();
    recovery.seal();
    // Settle only externally held calls. No successful command is invented by
    // cleanup, and no operation result is silently relabeled as accepted.
    const failure = StudioFailure(
      code: StudioFailureCode.cancelled,
      message: 'Selector fixture closed',
      retryable: false,
      correlationId: 'selector-cleanup',
    );
    for (final opening in configurationPort.opens) {
      final pin = opening.native ?? opening.accept();
      pin.requestClose();
      for (final call in pin.calls) {
        if (!call.reply.isCompleted) call.reply.completeError(failure);
      }
    }
    for (final call in commands.routes.values) {
      if (!call.reply.isCompleted) call.reply.completeError(failure);
    }
    for (final call in commands.modes.values) {
      if (!call.reply.isCompleted) call.reply.completeError(failure);
    }
    for (final call in commands.interrupts.values) {
      if (!call.reply.isCompleted) call.reply.completeError(failure);
    }
    for (final call in commands.continues.values) {
      if (!call.reply.isCompleted) call.reply.completeError(CommandDispatchFailure.rejected(failure: failure));
    }
    for (final call in commands.continuationReads.values) {
      if (!call.reply.isCompleted) call.reply.complete(null);
    }
    for (final call in commands.prompts.values) {
      if (!call.reply.isCompleted) call.reply.completeError(failure);
    }
    for (final call in creations.begins.values) {
      if (!call.reply.isCompleted) {
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: failure),
        );
      }
    }
    for (final opening in timeline.requests) {
      if (!opening.result.isCompleted) {
        opening.result.complete(
          TestTimelineConnection(
            initial: baseline(
              1,
              items: [timelineItem(1, threadId: opening.threadId)],
            ),
          ),
        );
      }
    }
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      binding.close(deadline: deadline),
      drafts.close(deadline: deadline),
      workspace.close(deadline: deadline),
      conversations.close(deadline: deadline),
      configuration.close(deadline: deadline),
      models.close(deadline: deadline),
      modes.close(deadline: deadline),
      recovery.close(deadline: deadline),
    ]);
    // 该 close() 常运行在受保护异步区间（pump 未结束时），受保护的 expect 会触发
    // Guarded function conflict；同步断言语义不变。
    expectSync([for (final report in reports) ...report.unresolved], isEmpty);
    operations.seal();
    if (checkBudget) expectSync(budget.usage, isEmpty);
  }
}

Future<T> waitLatest<T>(
  ReadonlyLatestValue<T> source,
  bool Function(T) matches,
) {
  final done = Completer<T>();
  final watched = source.watchLatest((value) {
    if (!done.isCompleted && matches(value)) done.complete(value);
  });
  if (!done.isCompleted && matches(watched.value)) done.complete(watched.value);
  return done.future.whenComplete(watched.observation.cancel);
}
