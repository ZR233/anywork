import 'dart:async';

import 'package:anywork_client/bots.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../platform/feishu_app_links.dart';
import '../../connectors/settings_failure_text.dart';
import '../view_models/bots_settings_view_model.dart';
import '../views/bots_registration_view.dart';

/// Connects the canonical registration attempt to the page.
///
/// The attempt is published by the Bots topic, so the panel survives closing
/// the setup editor and re-entering settings. Only the copy/open entries touch
/// the platform; the verification link itself stays local UI material.
class BotsRegistrationConnector extends ConsumerWidget {
  const BotsRegistrationConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(botsSettingsViewModelProvider).value;
    if (state == null) return const SizedBox.shrink();
    final attempt = state.registration;
    if (attempt == null) {
      if (!state.registrationPending) return const SizedBox.shrink();
      return const LinearProgressIndicator();
    }
    final vm = ref.read(botsSettingsViewModelProvider.notifier);
    final url = switch (attempt.status) {
      BotRegistrationWaiting(:final verificationUrl) => verificationUrl,
      BotRegistrationSlowDown(:final verificationUrl) => verificationUrl,
      _ => null,
    };
    final canOpenFeishu =
        ref.watch(feishuClientAvailableProvider).asData?.value == true;
    final browser = url == null ? null : safeExternalWebUrl(url);
    final client = url == null || !canOpenFeishu
        ? null
        : feishuRegistrationAppLink(url);
    return BotsRegistrationView(
      attempt: attempt,
      verificationUrl: url,
      browserLink: browser,
      clientLink: client,
      pending: state.registrationPending,
      editable: state.editable && !state.registrationBlocked,
      errors: [
        if (state.registrationAction?.error case final error?)
          settingsFailureText(error),
        if (state.registrationAction?.observationError case final error?)
          settingsFailureText(error),
        if (state.registrationAction?.operation?.evidenceError
            case final error?)
          settingsFailureText(error),
      ],
      onCancel: () => unawaited(vm.cancelRegistration()),
      onOpenLink: browser == null
          ? null
          : () => unawaited(_open(context, ref, browser)),
      onOpenFeishu: client == null
          ? null
          : () => unawaited(_open(context, ref, client)),
      onCopyLink: url == null
          ? null
          : () => unawaited(Clipboard.setData(ClipboardData(text: url))),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String link) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failure = context.l10n.settingsBotsOpenLinkFailed;
    try {
      await ref.read(externalUrlLauncherProvider)(link);
    } catch (_) {
      // The original error may carry the authorization URL or a system path.
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}
