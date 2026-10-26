import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';

/// 飞书中国版开发者后台固定入口；仅本机点击打开，不携带凭据或票据。
const botDeveloperConsoleUrl = 'https://open.feishu.cn/app';

/// Opens the fixed official console page. The user still has to pick the
/// application and request permissions there; this only reaches the safe HTTPS
/// entry. Failures stay a localized retry hint and never echo the underlying
/// exception or the URL.
Future<void> openBotDeveloperConsole(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failure = context.l10n.settingsBotsOpenConsoleFailed;
  try {
    final safe = safeExternalWebUrl(botDeveloperConsoleUrl);
    if (safe == null) throw StateError('unsupported console link');
    await ref.read(externalUrlLauncherProvider)(safe);
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(failure)));
  }
}

/// Opens one Bot/Chat AppLink or its browser form.
///
/// Returns false when the link is absent or the platform rejected it, so the
/// caller can keep its own localized retry entry. The underlying exception may
/// carry the link or a system path and is never presented.
Future<bool> openBotAppLink(WidgetRef ref, String? url) async {
  if (url == null) return false;
  try {
    await ref.read(externalUrlLauncherProvider)(url);
    return true;
  } catch (_) {
    return false;
  }
}
