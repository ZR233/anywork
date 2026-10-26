import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_bindings.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../status/status.dart';
import '../../connectors/settings_failure_text.dart';
import '../state/bot_setup_state.dart';
import '../view_models/bot_model_availability.dart';
import '../view_models/bot_setup_view_model.dart';
import '../views/bot_secret_owner.dart';
import '../views/bot_setup_view.dart';
import 'bot_console_link.dart';

/// Hosts one bot create/edit session: creation is the in-page setup section and
/// editing is the "编辑配置" dialog.
///
/// The App Secret lives in this connector's [BotSecretOwner] for exactly the
/// lifetime of the open editor; it is scrubbed after a successful save, on
/// cancel and on dispose, and it never reaches the ViewModel's state.
class BotSetupConnector extends ConsumerStatefulWidget {
  const BotSetupConnector({
    required this.target,
    required this.onClose,
    required this.onStartRegistration,
    super.key,
  });

  final BotSetupKey target;

  /// Reports whether the editor ended with a settled save.
  final ValueChanged<bool> onClose;

  /// Hands the frozen name to the canonical registration entry on the page.
  final ValueChanged<String> onStartRegistration;

  @override
  ConsumerState<BotSetupConnector> createState() => _BotSetupConnectorState();
}

class _BotSetupConnectorState extends ConsumerState<BotSetupConnector> {
  late final BotSecretOwner _secret;

  /// The create section states the default model availability, so it reads the
  /// mode routes and one bounded catalog page once per open editor.
  bool _requestedModelEvidence = false;

  /// Creation is an in-page section and editing is a dialog; only the latter
  /// owns a route that closing can pop.
  bool get _inline => widget.target.botId == null;

  @override
  void initState() {
    super.initState();
    _secret = BotSecretOwner()..controller.addListener(_secretChanged);
    unawaited(_ensureModelEvidence());
  }

  Future<void> _ensureModelEvidence() async {
    if (_requestedModelEvidence) return;
    _requestedModelEvidence = true;
    try {
      await ref.read(configurationRepositoryProvider).loadModeRoutes();
    } on StudioFailure {
      // Without a current read the availability stays unknown; the section then
      // states the actionable setup requirement instead of claiming a route.
    }
    if (!mounted) return;
    unawaited(ref.read(selectorCatalogViewModelProvider.notifier).loadMore());
  }

  @override
  void dispose() {
    _secret.controller.removeListener(_secretChanged);
    _secret.dispose();
    super.dispose();
  }

  void _secretChanged() {
    if (!mounted) return;
    ref
        .read(botSetupViewModelProvider(widget.target).notifier)
        .secretPresenceChanged(_secret.hasValue);
  }

  @override
  Widget build(BuildContext context) {
    final provider = botSetupViewModelProvider(widget.target);
    return ref
        .watch(provider)
        .when(
          loading: () => _inline
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const AlertDialog(
                  content: Center(
                    heightFactor: 2,
                    child: CircularProgressIndicator(),
                  ),
                ),
          error: (error, stack) {
            if (error is! StudioFailure) {
              Error.throwWithStackTrace(error, stack);
            }
            final message = SelectableText(settingsFailureText(error));
            final dismiss = TextButton(
              onPressed: () => widget.onClose(false),
              child: Text(
                _inline
                    ? context.l10n.settingsBotsSetupClose
                    : context.l10n.settingsBotsDismiss,
              ),
            );
            return _inline
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [message, dismiss],
                    ),
                  )
                : AlertDialog(content: message, actions: [dismiss]);
          },
          data: (state) {
            final vm = ref.read(provider.notifier);
            final catalog = ref.watch(selectorCatalogViewModelProvider).value;
            final availability = catalog == null
                ? BotModelAvailability.unknown
                : botModelAvailability(catalog);
            return BotSetupView(
              state: state,
              secret: _secret,
              modelAvailability: availability == BotModelAvailability.ready
                  ? context.l10n.settingsBotsModelReady
                  : context.l10n.settingsBotsModelMissing,
              errors: [
                if (state.saveAction?.error case final error?)
                  settingsFailureText(error),
                if (state.saveAction?.observationError case final error?)
                  settingsFailureText(error),
                if (state.saveAction?.operation?.evidenceError
                    case final error?)
                  settingsFailureText(error),
                if (state.sourceError case final error?)
                  settingsFailureText(error),
              ],
              onName: vm.setName,
              onAppId: vm.setAppId,
              onRiskAcknowledged: vm.setRiskAcknowledged,
              onManual: vm.openManual,
              onSecretIntent: (intent) {
                // Clearing the field is part of revoking the secret, so the
                // buffer is dropped before the intent leaves this connector.
                if (intent == BotSecretIntent.clear) _secret.release();
                vm.setSecretIntent(intent);
              },
              onStartRegistration: () {
                final name = state.name.trim();
                if (name.isEmpty) return;
                widget.onClose(false);
                widget.onStartRegistration(name);
              },
              onOpenConsole: () =>
                  unawaited(openBotDeveloperConsole(context, ref)),
              onCancel: () => widget.onClose(false),
              onSave: () => unawaited(_save(vm)),
            );
          },
        );
  }

  Future<void> _save(BotSetupViewModel vm) async {
    final target = widget.target;
    final lifetime = vm.lifetime;
    final saved = await vm.save(secret: _secret.take());
    if (!saved || !mounted) return;
    // A late save for a replaced editor must not close the newer dialog.
    if (widget.target != target || !vm.ownsEditor(lifetime, target)) return;
    _secret.release();
    widget.onClose(true);
  }
}
