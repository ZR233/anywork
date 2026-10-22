import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExternalUrlLauncher = Future<void> Function(String url);

const _maxExternalUrlBytes = 8 * 1024;
final _urlControlCharacters = RegExp(r'[\u0000-\u001F\u007F-\u009F]');

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) => openExternalUrl,
);

Future<void> openExternalUrl(String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    // Registration URLs can contain tickets; never include them in failures.
    throw StateError('The system could not open the link');
  }
}

/// Returns a browser-safe web destination or `null` for unsupported links.
String? safeExternalWebUrl(String value) {
  if (utf8.encode(value).length > _maxExternalUrlBytes) {
    return null;
  }
  final sanitized = value.replaceAll(_urlControlCharacters, '');
  final uri = Uri.tryParse(sanitized);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' ? sanitized : null;
}
