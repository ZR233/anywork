import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Pure native artwork presentation. The connector supplies optional icon bytes.
class HostAppArtwork extends StatelessWidget {
  const HostAppArtwork({
    super.key,
    this.bytes,
    required this.fallback,
    this.size = 20,
  });

  final Uint8List? bytes;
  final IconData fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    if (data == null) return Icon(fallback, size: size);
    return Image.memory(
      data,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, error, stackTrace) => Icon(fallback, size: size),
    );
  }
}
