import 'dart:convert';

/// Presence-aware result data extracted only from the explicit `toolData`
/// output artifact. Text in `tool.result` is never interpreted as program data.
sealed class ToolDataArtifact {
  const ToolDataArtifact();

  static ToolDataArtifact parseArtifacts(
    Iterable<String> sources, {
    bool deferred = false,
  }) {
    Object? value;
    var found = false;
    for (final source in sources) {
      final Object? decoded;
      try {
        decoded = jsonDecode(source);
      } on FormatException {
        return const ToolDataArtifactInvalid('tool.output-artifacts JSON 无效');
      }
      if (decoded is! List) {
        return const ToolDataArtifactInvalid('tool.output-artifacts 必须是数组');
      }
      for (final artifact in decoded) {
        if (artifact is! Map<String, dynamic>) {
          return const ToolDataArtifactInvalid('tool.output-artifacts 项必须是对象');
        }
        if (!artifact.containsKey('toolData')) continue;
        if (found) {
          return const ToolDataArtifactInvalid('toolData artifact 重复');
        }
        found = true;
        value = artifact['toolData'];
      }
    }
    if (found) return ToolDataArtifactPresent(value);
    return deferred
        ? const ToolDataArtifactPending()
        : const ToolDataArtifactAbsent();
  }
}

final class ToolDataArtifactAbsent extends ToolDataArtifact {
  const ToolDataArtifactAbsent();
}

final class ToolDataArtifactPending extends ToolDataArtifact {
  const ToolDataArtifactPending();
}

final class ToolDataArtifactPresent extends ToolDataArtifact {
  const ToolDataArtifactPresent(this.value);

  final Object? value;
}

final class ToolDataArtifactInvalid extends ToolDataArtifact {
  const ToolDataArtifactInvalid(this.message);

  final String message;
}
