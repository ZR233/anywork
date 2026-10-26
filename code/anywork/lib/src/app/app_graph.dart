import 'package:anywork_client/acp.dart';
import 'package:anywork_client/account_usage.dart'
    show AccountUsageRepository, SessionCostsRepository;
import 'package:anywork_client/bots.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources_ports.dart' show ResourceBudget;
import 'package:anywork_client/skills.dart';
import 'package:anywork_client/statistics.dart' show StatisticsRepository;
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart';

import '../diagnostics/contracts/timeline_diagnostics.dart';
import '../features/conversation/presentation_api.dart'
    show ConversationTimelineDiagnostics, TimelineCoordinator;
import 'bootstrap/application_bootstrap.dart';
import 'bootstrap/automatic_updates_startup.dart';
import 'lifecycle/application_exit_coordinator.dart';
import 'lifecycle/exit_participant.dart';
import 'lifecycle/native_exit_host.dart';
import 'composition/resident_bots_demand.dart';

/// An assembled application instance, not a forwarding Client. Composition
/// creates these real domain/resource owners in dependency order, then injects
/// this graph before building any feature VM. It must never reuse another
/// graph's repositories, budget, drafts, operations or presentation coordinator.
final class AppGraph {
  AppGraph.assembled({
    required this.configuration,
    required this.models,
    required this.modes,
    required this.accountUsage,
    required this.statistics,
    required this.sessionCosts,
    required this.workspace,
    required this.startup,
    required this.conversation,
    required this.drafts,
    required this.remote,
    required this.mcp,
    required this.lsp,
    required this.acpAuth,
    required this.acpInstall,
    required this.skills,
    required this.bots,
    required this.recovery,
    required this.persistence,
    required this.updates,
    required this.operations,
    required this.budget,
    required this.timeline,
    required this.editProducers,
    required this.bootstrap,
    required this.automaticUpdates,
    required this.residentBots,
    required this.exitCoordinator,
    required this.host,
  }) : timelineDiagnostics = ConversationTimelineDiagnostics(timeline);

  final ConfigurationRepository configuration;
  final ModelsRepository models;
  final ModesRepository modes;
  final AccountUsageRepository accountUsage;
  final StatisticsRepository statistics;

  /// Root-session costs keep their own repository inside the account-usage
  /// domain; they are not a statistics read.
  final SessionCostsRepository sessionCosts;
  final WorkspaceRepository workspace;
  final StartupRepository startup;
  final ConversationRepository conversation;
  final DraftsRepository drafts;
  final RemoteRepository remote;
  final McpRepository mcp;
  final LspRepository lsp;
  final AcpAuthRepository acpAuth;
  final AcpInstallRepository acpInstall;
  final SkillsRepository skills;
  final BotsRepository bots;
  final RecoveryRepository recovery;
  final PersistenceRepository persistence;
  final UpdatesRepository updates;
  final Operations operations;
  final ResourceBudget budget;
  final TimelineCoordinator timeline;
  final TimelineDiagnosticsSource timelineDiagnostics;
  final ApplicationEditProducerRegistry editProducers;
  final ApplicationBootstrap bootstrap;
  final AutomaticUpdatesStartup automaticUpdates;

  /// Resident Bots demand: established after RuntimeReady, released with the
  /// graph. Settings visits never own or close it.
  final ResidentBotsDemand residentBots;
  final ApplicationExitCoordinator exitCoordinator;
  final NativeExitHost host;
}
