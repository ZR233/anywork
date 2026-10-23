import 'dart:convert';

import 'package:anywork_client/conversation.dart' show OpaqueArtifactJson;

/// This is the only JSON interpretation boundary for deliberately open tool
/// artifacts. Known DTOs, tool.arguments and Raw payload strings never enter it.
List<String> extractArtifactLinks(Iterable<OpaqueArtifactJson> artifacts) {
  final links = <String>{};

  void visit(Object? value) {
    if (links.length >= 6) return;
    switch (value) {
      case String():
        final candidate = value.trim();
        // Preserve the original prefix-only rule. In particular do not parse a
        // URI, rewrite its scheme, normalize case or demand a valid host here.
        if (candidate.startsWith('http://') || candidate.startsWith('https://')) links.add(candidate);
      case List<Object?>():
        for (final child in value) { visit(child); if (links.length >= 6) break; }
      case Map<String, Object?>():
        for (final child in value.values) { visit(child); if (links.length >= 6) break; }
      case null || bool() || num(): break;
    }
  }

  for (final artifact in artifacts) {
    final Object? value;
    try { value = jsonDecode(artifact.json); } on FormatException {
      // Never retain/print FormatException: it may contain the original payload.
      throw const ArtifactLinksDecodeFailure();
    }
    visit(value);
  }
  return List.unmodifiable(links);
}

final class ArtifactLinksDecodeFailure implements Exception {
  const ArtifactLinksDecodeFailure();
  @override
  String toString() => 'ArtifactLinksDecodeFailure';
}
