import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/host_app_icons.dart';

/// Displays the native artwork for an external host application.
///
/// The artwork is intentionally independent from the launcher availability
/// probe. A missing or malformed icon only uses the Material fallback glyph;
/// it never changes whether the corresponding menu action is enabled.
class HostAppLogo extends ConsumerWidget {
  const HostAppLogo({
    super.key,
    required this.app,
    required this.fallback,
    this.size = 20,
  });

  final HostAppIcon app;
  final IconData fallback;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(hostAppIconProvider(app)).value;
    if (bytes == null) return Icon(fallback, size: size);
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, error, stackTrace) => Icon(fallback, size: size),
    );
  }
}
