import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bindings.dart';
import '../app_graph.dart';

/// The caller owns this container. Dispose only after the graph's actual async
/// exit/resource joins; Provider disposal is never a business cleanup command.
/// No feature reads AppGraph or chooses a different default implementation.
ProviderContainer createApplicationContainer(AppGraph graph) =>
    ProviderContainer(
      overrides: [
        configurationRepositoryProvider.overrideWithValue(graph.configuration),
        modelsRepositoryProvider.overrideWithValue(graph.models),
        modesRepositoryProvider.overrideWithValue(graph.modes),
        accountUsageRepositoryProvider.overrideWithValue(graph.accountUsage),
        statisticsRepositoryProvider.overrideWithValue(graph.statistics),
        sessionCostsRepositoryProvider.overrideWithValue(graph.sessionCosts),
        workspaceRepositoryProvider.overrideWithValue(graph.workspace),
        startupRepositoryProvider.overrideWithValue(graph.startup),
        conversationRepositoryProvider.overrideWithValue(graph.conversation),
        draftsRepositoryProvider.overrideWithValue(graph.drafts),
        remoteRepositoryProvider.overrideWithValue(graph.remote),
        mcpRepositoryProvider.overrideWithValue(graph.mcp),
        lspRepositoryProvider.overrideWithValue(graph.lsp),
        acpAuthRepositoryProvider.overrideWithValue(graph.acpAuth),
        acpInstallRepositoryProvider.overrideWithValue(graph.acpInstall),
        skillsRepositoryProvider.overrideWithValue(graph.skills),
        botsRepositoryProvider.overrideWithValue(graph.bots),
        recoveryRepositoryProvider.overrideWithValue(graph.recovery),
        persistenceRepositoryProvider.overrideWithValue(graph.persistence),
        updatesRepositoryProvider.overrideWithValue(graph.updates),
        applicationExitCoordinatorProvider.overrideWithValue(
          graph.exitCoordinator,
        ),
        applicationEditProducerRegistryProvider.overrideWithValue(
          graph.editProducers,
        ),
        applicationBootstrapProvider.overrideWithValue(graph.bootstrap),
        timelineActionsProvider.overrideWithValue(graph.timeline),
        timelineCoordinatorProvider.overrideWithValue(graph.timeline),
        prepareConversationPresentationProvider.overrideWithValue(
          graph.timeline.prepareSend,
        ),
        timelineDiagnosticsSourceProvider.overrideWithValue(
          graph.timelineDiagnostics,
        ),
      ],
    );

/// Driver may keep the container to serve diagnostics, but it must be the one
/// injected from this same graph. Never start one root with another root's VMs.
void requireApplicationContainer(ProviderContainer container, AppGraph graph) {
  final matches =
      identical(
        container.read(configurationRepositoryProvider),
        graph.configuration,
      ) &&
      identical(container.read(modelsRepositoryProvider), graph.models) &&
      identical(container.read(modesRepositoryProvider), graph.modes) &&
      identical(
        container.read(accountUsageRepositoryProvider),
        graph.accountUsage,
      ) &&
      identical(
        container.read(statisticsRepositoryProvider),
        graph.statistics,
      ) &&
      identical(
        container.read(sessionCostsRepositoryProvider),
        graph.sessionCosts,
      ) &&
      identical(container.read(workspaceRepositoryProvider), graph.workspace) &&
      identical(container.read(startupRepositoryProvider), graph.startup) &&
      identical(
        container.read(conversationRepositoryProvider),
        graph.conversation,
      ) &&
      identical(container.read(draftsRepositoryProvider), graph.drafts) &&
      identical(container.read(remoteRepositoryProvider), graph.remote) &&
      identical(container.read(mcpRepositoryProvider), graph.mcp) &&
      identical(container.read(lspRepositoryProvider), graph.lsp) &&
      identical(container.read(acpAuthRepositoryProvider), graph.acpAuth) &&
      identical(
        container.read(acpInstallRepositoryProvider),
        graph.acpInstall,
      ) &&
      identical(container.read(skillsRepositoryProvider), graph.skills) &&
      identical(container.read(botsRepositoryProvider), graph.bots) &&
      identical(container.read(recoveryRepositoryProvider), graph.recovery) &&
      identical(
        container.read(persistenceRepositoryProvider),
        graph.persistence,
      ) &&
      identical(container.read(updatesRepositoryProvider), graph.updates) &&
      identical(
        container.read(applicationExitCoordinatorProvider),
        graph.exitCoordinator,
      ) &&
      identical(
        container.read(applicationEditProducerRegistryProvider),
        graph.editProducers,
      ) &&
      identical(
        container.read(applicationBootstrapProvider),
        graph.bootstrap,
      ) &&
      identical(container.read(timelineActionsProvider), graph.timeline) &&
      identical(container.read(timelineCoordinatorProvider), graph.timeline) &&
      container.read(prepareConversationPresentationProvider) ==
          graph.timeline.prepareSend &&
      identical(
        container.read(timelineDiagnosticsSourceProvider),
        graph.timelineDiagnostics,
      );
  if (!matches) {
    throw StateError(
      'The supplied container belongs to another application graph.',
    );
  }
}
