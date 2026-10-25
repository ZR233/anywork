import 'package:flutter/material.dart';

/// Native artwork supplied by a Smart connector, independent of launch eligibility.
///
/// Loading the artwork is not a View responsibility. A missing or malformed image
/// only affects this glyph; it never changes availability of a host action.
class HostAppLogo extends StatelessWidget {
  const HostAppLogo({
    required this.fallback,
    this.image,
    this.size = 20,
    super.key,
  });

  final ImageProvider? image;
  final IconData fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final provider = image;
    if (provider == null) return Icon(fallback, size: size);
    return Image(
      image: provider,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, error, stackTrace) => Icon(fallback, size: size),
    );
  }
}
