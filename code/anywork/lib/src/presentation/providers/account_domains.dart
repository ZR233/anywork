import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_graph.dart';
import 'observe_client.dart';

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => ref.read(appGraphProvider).accounts,
);
final modelsRepositoryProvider = Provider<ModelsRepository>(
  (ref) => ref.read(appGraphProvider).models,
);
final accountUsageRepositoryProvider = Provider<AccountUsageRepository>(
  (ref) => ref.read(appGraphProvider).accountUsage,
);
final acpServiceProvider = Provider<AcpService>(
  (ref) => ref.read(appGraphProvider).acp,
);

void _releaseOnDispose(Ref ref, AccountDemand demand) {
  // Failed native retirement remains registered with its application owner;
  // provider disposal owns no business cancellation or shutdown authority.
  ref.onDispose(() {
    unawaited(
      demand.release().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  });
}

final accountsStateProvider = Provider.autoDispose<AccountsState>((ref) {
  final accounts = ref.read(accountsRepositoryProvider);
  return observeClient(ref, accounts.state, (_) => ref.invalidateSelf());
});

final _modelSelectionDemandProvider = Provider.autoDispose<void>((ref) {
  _releaseOnDispose(
    ref,
    ref.read(accountsRepositoryProvider).observeSummaries(),
  );
  _releaseOnDispose(ref, ref.read(modelsRepositoryProvider).observeDirectory());
});

final modelDirectoryStateProvider = Provider.autoDispose<ModelDirectoryState>((
  ref,
) {
  final models = ref.read(modelsRepositoryProvider);
  return observeClient(ref, models.state, (_) => ref.invalidateSelf());
});

/// Shared selectors request the directory explicitly. Merely watching an
/// account list does not materialize every account's model descriptors.
final modelSelectionAccountsProvider =
    Provider.autoDispose<List<ModelSelectionAccount>>((ref) {
      ref.watch(_modelSelectionDemandProvider);
      final accounts = ref.watch(accountsStateProvider);
      final directory = ref.watch(modelDirectoryStateProvider);
      return modelSelectionAccounts(accounts, directory);
    });

final accountUsageStateProvider =
    Provider.autoDispose<
      AccountResource<Map<NativeAccountIdentity, AccountUsageObservation>>
    >((ref) {
      final usage = ref.read(accountUsageRepositoryProvider);
      return observeClient(ref, usage.state, (_) => ref.invalidateSelf());
    });

/// Transport diagnostics remain separate from canonical provider health.
final accountUsageQueryFailuresProvider =
    Provider.autoDispose<Map<NativeAccountIdentity, StudioFailure>>((ref) {
      final usage = ref.read(accountUsageRepositoryProvider);
      return observeClient(
        ref,
        usage.queryFailures,
        (_) => ref.invalidateSelf(),
      );
    });

final acpAuthStateProvider =
    Provider.autoDispose<AccountResource<AcpAuthSnapshotView>>((ref) {
      final service = ref.read(acpServiceProvider);
      return observeClient(ref, service.auth, (_) => ref.invalidateSelf());
    });

final acpInstallStateProvider =
    Provider.autoDispose<AccountResource<AcpInstallSnapshotView>>((ref) {
      final service = ref.read(acpServiceProvider);
      return observeClient(ref, service.install, (_) => ref.invalidateSelf());
    });
