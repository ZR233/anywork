import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/bots.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/remote.dart';
import 'package:anywork_client/skills.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/contracts/timeline_diagnostics.dart';
import '../features/conversation/presentation_api.dart'
    show TimelineActions, TimelineCoordinator;
import 'bootstrap/application_bootstrap.dart';
import 'lifecycle/application_exit_coordinator.dart';
import 'lifecycle/exit_participant.dart';

/// Injection only. These providers do not mirror domain state or own Sessions.
/// Every ProviderContainer must receive its own application-owned instances.
final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  throw StateError('WorkspaceRepository must be injected by the application');
});

final startupRepositoryProvider = Provider<StartupRepository>((ref) {
  throw StateError('StartupRepository must be injected by the application');
});

final configurationRepositoryProvider = Provider<ConfigurationRepository>((
  ref,
) {
  throw StateError(
    'ConfigurationRepository must be injected by the application',
  );
});

final modelsRepositoryProvider = Provider<ModelsRepository>((ref) {
  throw StateError('ModelsRepository must be injected by the application');
});

final modesRepositoryProvider = Provider<ModesRepository>((ref) {
  throw StateError('ModesRepository must be injected by the application');
});

final accountUsageRepositoryProvider = Provider<AccountUsageRepository>((ref) {
  throw StateError(
    'AccountUsageRepository must be injected by the application',
  );
});

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  throw StateError('StatisticsRepository must be injected by the application');
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  throw StateError(
    'ConversationRepository must be injected by the application',
  );
});

final draftsRepositoryProvider = Provider<DraftsRepository>((ref) {
  throw StateError('DraftsRepository must be injected by the application');
});

final remoteRepositoryProvider = Provider<RemoteRepository>((ref) {
  throw StateError('RemoteRepository must be injected by the application');
});

final mcpRepositoryProvider = Provider<McpRepository>((ref) {
  throw StateError('McpRepository must be injected by the application');
});

final lspRepositoryProvider = Provider<LspRepository>((ref) {
  throw StateError('LspRepository must be injected by the application');
});

final skillsRepositoryProvider = Provider<SkillsRepository>((ref) {
  throw StateError('SkillsRepository must be injected by the application');
});

final botsRepositoryProvider = Provider<BotsRepository>((ref) {
  throw StateError('BotsRepository must be injected by the application');
});

final recoveryRepositoryProvider = Provider<RecoveryRepository>((ref) {
  throw StateError('RecoveryRepository must be injected by the application');
});

final persistenceRepositoryProvider = Provider<PersistenceRepository>((ref) {
  throw StateError('PersistenceRepository must be injected by the application');
});

final updatesRepositoryProvider = Provider<UpdatesRepository>((ref) {
  throw StateError('UpdatesRepository must be injected by the application');
});

final applicationEditProducerRegistryProvider =
    Provider<ApplicationEditProducerRegistry>((ref) {
      throw StateError(
        'ApplicationEditProducerRegistry must be injected by the application',
      );
    });

final applicationExitCoordinatorProvider = Provider<ApplicationExitCoordinator>(
  (ref) {
    throw StateError(
      'ApplicationExitCoordinator must be injected by the application',
    );
  },
);

final applicationBootstrapProvider = Provider<ApplicationBootstrap>((ref) {
  throw StateError('ApplicationBootstrap must be injected by the application');
});

/// Before-graph composition capability only, not a fallback Repository or a
/// second startup state. The same StartupViewModel presents and retries it;
/// after a real graph is installed its container uses ApplicationBootstrap.
final applicationAssemblyProvider = Provider<Future<void> Function()?>(
  (ref) => null,
);

final timelineActionsProvider = Provider<TimelineActions>((ref) {
  throw StateError('TimelineActions must be injected by the application');
});

/// Smart TimelineConnector only. VMs consume the narrower TimelineActions.
final timelineCoordinatorProvider = Provider<TimelineCoordinator>((ref) {
  throw StateError('TimelineCoordinator must be injected by the application');
});

final prepareConversationPresentationProvider =
    Provider<Future<void> Function(ConversationSession)>((ref) {
      throw StateError(
        'Conversation presentation preparation must be injected by the application',
      );
    });

final timelineDiagnosticsSourceProvider = Provider<TimelineDiagnosticsSource>((
  ref,
) {
  throw StateError(
    'TimelineDiagnosticsSource must be injected by the application',
  );
});
