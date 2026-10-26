import 'dart:async';

import 'package:anywork_client/workspace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/startup_view_model.dart';
import '../views/startup_recovery_banner_view.dart';

class StartupRecoveryBannerConnector extends ConsumerStatefulWidget {
  const StartupRecoveryBannerConnector({super.key});
  @override
  ConsumerState<StartupRecoveryBannerConnector> createState() =>
      _StartupRecoveryBannerConnectorState();
}

class _StartupRecoveryBannerConnectorState
    extends ConsumerState<StartupRecoveryBannerConnector> {
  RuntimeStartupReadRef? _requested;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _readRecovery(ref.read(startupViewModelProvider).asData?.value.startup);
      }
    });
  }

  void _readRecovery(StartupState? startup) {
    if (startup is! ReadyStartupState || _requested == startup.result.details) {
      return;
    }
    _requested = startup.result.details;
    unawaited(ref.read(startupViewModelProvider.notifier).loadRecovery());
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(startupViewModelProvider).asData?.value;
    ref.listen(
      startupViewModelProvider,
      (_, next) => _readRecovery(next.asData?.value.startup),
    );
    if (startup == null || startup.recoveryDismissed) {
      return const SizedBox.shrink();
    }
    final vm = ref.read(startupViewModelProvider.notifier);
    return StartupRecoveryBannerView(
      recovery: startup.recovery,
      failure: startup.recoveryError,
      onDismiss: vm.dismissRecovery,
      onRetry: () => unawaited(vm.loadRecovery()),
    );
  }
}
