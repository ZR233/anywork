import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/start_session_controller.dart';
import '../state/start_backend_view_state.dart';

part 'start_backend_view_model.g.dart';

@riverpod
void _startBackendAccountDemand(Ref ref) {
  final demand = ref.read(accountsRepositoryProvider).observeSummaries();
  ref.onDispose(() {
    unawaited(
      demand.release().catchError((Object _, StackTrace _) {
        // Releasing a read-only observation on dispose cannot fail UI teardown.
      }),
    );
  });
}

@riverpod
class StartBackendViewModel extends _$StartBackendViewModel {
  @override
  StartBackendViewState build(String? workspaceId) {
    ref.watch(_startBackendAccountDemandProvider);
    final accounts = ref.watch(accountsStateProvider);
    final sessionDraft = ref.watch(startSessionControllerProvider);
    final selected = (
      accountId: sessionDraft.forProject(workspaceId).acpAccountId,
      submitting: sessionDraft.submitting,
    );
    return StartBackendViewState(
      services: [
        for (final account in accounts.accounts)
          if (account.identity is AcpAccountIdentity)
            StartBackendServiceItem(
              id: account.identity.accountId,
              name: account.name,
              brandKey: account.brandKey,
              enabled: account.acpEnabled == true,
            ),
      ],
      diagnostics: [
        for (final diagnostic in accounts.acpDiagnostics)
          StartBackendDiagnosticItem(
            fileName: diagnostic.fileName,
            message: diagnostic.message,
          ),
      ],
      accountId: selected.accountId,
      enabled: workspaceId != null && !selected.submitting,
      loading: !accounts.loaded,
      failure: accounts.failure?.message,
    );
  }

  void select(String? id) {
    final targetWorkspace = workspaceId;
    if (targetWorkspace == null) return;
    final submitting = ref.read(startSessionControllerProvider).submitting;
    if (submitting) return;
    if (id != null) {
      final accounts = ref.read(accountsStateProvider).accounts;
      final matched = accounts
          .where(
            (item) =>
                item.identity == AcpAccountIdentity(id) &&
                item.acpEnabled == true,
          )
          .firstOrNull;
      if (matched == null) return;
    }
    ref
        .read(anyworkClientProvider)
        .drafts
        .startDraft
        .setAcpService(targetWorkspace, id);
  }
}
