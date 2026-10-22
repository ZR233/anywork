import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'external_url_launcher.dart';

/// Availability only controls the client shortcut. QR authorization is always
/// available, including while checking or when the system cannot answer.
final feishuClientAvailableProvider = FutureProvider.autoDispose<bool>(
  (ref) => canLaunchUrl(Uri.parse('feishu://applink/client/op/open')),
);

/// Only production registration destinations may be handed to the real client.
/// A fixture URL remains available through its original browser/QR entry points.
String? feishuRegistrationAppLink(String verificationUrl) {
  if (safeExternalWebUrl(verificationUrl) != verificationUrl) return null;
  final uri = Uri.parse(verificationUrl);
  if (uri.scheme != 'https' ||
      !const {'accounts.feishu.cn', 'open.feishu.cn'}.contains(uri.host) ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  return Uri(
    scheme: 'feishu',
    host: 'applink',
    path: '/client/web_url/open',
    query: 'mode=window&url=${Uri.encodeComponent(verificationUrl)}',
  ).toString();
}

/// The app id remains one query value; it can never select a different route.
String feishuBotAppLink(String appId, {bool browser = false}) => Uri(
  scheme: browser ? 'https' : 'feishu',
  host: browser ? 'applink.feishu.cn' : 'applink',
  path: '/client/bot/open',
  query: 'appId=${Uri.encodeComponent(appId)}',
).toString();
