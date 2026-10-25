import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../state/account_model_details_state.dart';
import '../view_models/account_model_details_view_model.dart';
import '../views/account_model_details_view.dart';

/// Mounted only by the explicit model-details action, never by model rows.
class AccountModelDetailsConnector extends ConsumerStatefulWidget {
  const AccountModelDetailsConnector({required this.entry, super.key});
  final AccountModelDetailsEntry entry;

  @override
  ConsumerState<AccountModelDetailsConnector> createState() =>
      _AccountModelDetailsConnectorState();
}

class _AccountModelDetailsConnectorState
    extends ConsumerState<AccountModelDetailsConnector> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadInitial());
    });
  }

  Future<void> _loadInitial() async {
    final entry = widget.entry;
    final provider = accountModelDetailsViewModelProvider(entry);
    final vm = ref.read(provider.notifier);
    await ref.read(provider.future);
    if (!mounted ||
        !identical(widget.entry, entry) ||
        !identical(ref.read(provider.notifier), vm)) {
      return;
    }
    await vm.loadInitial(entry);
  }

  @override
  Widget build(BuildContext context) {
    final provider = accountModelDetailsViewModelProvider(widget.entry);
    return ref
        .watch(provider)
        .when(
          loading: () => AlertDialog(
            key: StudioDriverKeys.modelDetailDialog,
            content: const LinearProgressIndicator(),
            actions: [
              TextButton(
                key: StudioDriverKeys.modelDetailClose,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.modelDetailClose),
              ),
            ],
          ),
          error: (error, stack) {
            if (error is! StudioFailure) {
              Error.throwWithStackTrace(error, stack);
            }
            return AlertDialog(
              key: StudioDriverKeys.modelDetailDialog,
              content: SelectableText(settingsFailureText(error)),
              actions: [
                TextButton(
                  key: StudioDriverKeys.modelDetailClose,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.modelDetailClose),
                ),
              ],
            );
          },
          data: (state) {
            final vm = ref.read(provider.notifier);
            return AccountModelDetailsView(
              state: state,
              errors: [
                for (final error in [
                  state.error,
                  ...state.observationErrors,
                  state.configurationError,
                  state.catalogError,
                ])
                  if (error != null) settingsFailureText(error),
              ],
              onReload: () => unawaited(vm.reload()),
              onClose: () => Navigator.of(context).pop(),
            );
          },
        );
  }
}
