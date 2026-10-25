import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'profile_configuration_port.dart';
import 'profile_model_port.dart';

/// Real Repository owners and a real OperationRegistry. Only immutable native
/// DTOs, feeds and independently scripted native calls are supplied by the
/// environment. Unscripted writes are typed admission refusals, never Noop calls.
final class ProfileEditorFixture {
  ProfileEditorFixture({
    String ownerEpoch = 'profile-native',
    int accountCount = 2,
    Set<String>? textEligibleAccounts,
    AgentProfileSnapshot? profile,
  }) {
    final accounts = List.generate(accountCount, (index) => 'account-$index');
    origin = ProductReadOrigin(ownerEpoch: ownerEpoch, incarnation: 1);
    modelPort = ProfileModelsPort(
      origin: origin,
      accounts: accounts,
      textEligibleAccounts: textEligibleAccounts ?? accounts.toSet(),
    );
    configurationPort = ProfileConfigurationPort(
      origin: origin,
      accounts: accounts,
      profile: profile,
    );
    operations = OperationRegistry(
      clientId: 'profile-test-$ownerEpoch',
      budget: budget,
    );
    final assembly = createModelsRepository(port: modelPort, budget: budget);
    models = assembly.repository;
    configuration = createConfigurationRepository(
      port: configurationPort,
      budget: budget,
      operations: operations,
      modelTargets: assembly.targets,
    );
  }
  final budget = ResourceBudget();
  late final ProductReadOrigin origin;
  late final ProfileModelsPort modelPort;
  late final ProfileConfigurationPort configurationPort;
  late final OperationRegistry operations;
  late final ModelsRepository models;
  late final ConfigurationRepository configuration;

  Future<void> establish() async {
    final settings = configuration.loadAccountsPage();
    final profiles = configuration.loadProfilesPage();
    // Open the real catalog without loading its first account page. The VM's
    // build demands that page, so the >32 scenario retains its real boundary.
    final catalog = models.loadWebSearch();
    await Future.wait([
      configurationPort.feed.listened.future,
      configurationPort.profilesFeed.listened.future,
      modelPort.feed.listened.future,
    ]);
    configurationPort.baseline();
    modelPort.baseline();
    await Future.wait<void>([settings, profiles, catalog.then<void>((_) {})]);
    await Future.wait([
      configurationPort.feed.acknowledged(1),
      configurationPort.profilesFeed.acknowledged(1),
      modelPort.feed.acknowledged(1),
    ]);
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    final reports = await Future.wait([
      configuration.close(deadline: deadline),
      models.close(deadline: deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}
