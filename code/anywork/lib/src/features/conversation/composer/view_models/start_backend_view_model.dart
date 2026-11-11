import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/start_session_controller.dart';

final _serviceDemandProvider = Provider.autoDispose<void>((ref) {
  final demand = ref.read(accountsRepositoryProvider).observeSummaries();
  ref.onDispose(() {
    unawaited(demand.release().catchError((Object _, StackTrace _) {}));
  });
});

final startBackendViewModelProvider = Provider.autoDispose
    .family<StartBackendViewModel, String?>((ref, workspaceId) {
      ref.watch(_serviceDemandProvider);
      final accounts = ref.watch(accountsStateProvider);
      final selected = ref.watch(
        startSessionControllerProvider.select(
          (state) =>
              (state.forProject(workspaceId).acpAccountId, state.submitting),
        ),
      );
      final owner = ref.read(anyworkClientProvider).drafts.startDraft;
      return StartBackendViewModel(
        services: [
          for (final account in accounts.accounts)
            if (account.identity is AcpAccountIdentity)
              (
                id: account.identity.accountId,
                name: account.name,
                enabled: account.acpEnabled == true,
              ),
        ],
        diagnostics: accounts.acpDiagnostics,
        accountId: selected.$1,
        enabled: workspaceId != null && !selected.$2,
        loading: !accounts.loaded,
        failure: accounts.failure?.message,
        select: (id) {
          if (id != null &&
              accounts.accounts
                      .where(
                        (item) =>
                            item.identity == AcpAccountIdentity(id) &&
                            item.acpEnabled == true,
                      )
                      .firstOrNull ==
                  null) {
            return;
          }
          if (workspaceId != null && !selected.$2) {
            owner.setAcpService(workspaceId, id);
          }
        },
      );
    });

final class StartBackendViewModel {
  const StartBackendViewModel({
    required this.services,
    required this.diagnostics,
    required this.accountId,
    required this.enabled,
    required this.loading,
    required this.failure,
    required this.select,
  });

  final List<({String id, String name, bool enabled})> services;
  final List<AcpDefinitionDiagnosticView> diagnostics;
  final String? accountId;
  final bool enabled;
  final bool loading;
  final String? failure;
  final void Function(String?) select;

  String? get serviceName =>
      services.where((item) => item.id == accountId).firstOrNull?.name;
}
