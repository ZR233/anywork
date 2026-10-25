import 'package:flutter_test/flutter_test.dart';

import '../../../../xtask/dart/client_boundary_check.dart';

const _artifact = 'code/anywork/lib/src/features/conversation/presentation/artifact_links.dart';

void main() {
  for (final fixture in <({String name, String path, String source})>[
    (
      name: 'SDK mirror cannot interpret opaque artifact JSON',
      path: 'code/anywork_client/lib/src/conversation/data/fixture.dart',
      source: 'Object? read(OpaqueArtifactJson artifact) => jsonDecode(artifact.json);',
    ),
    (
      name: 'another feature file gets no artifact decoding exemption',
      path: 'code/anywork/lib/src/features/conversation/presentation/another.dart',
      source: 'Object? read(OpaqueArtifactJson artifact) => jsonDecode(artifact.json);',
    ),
    (
      name: 'known protocol DTO JSON cannot be decoded by a View',
      path: 'code/anywork/lib/src/features/conversation/views/fixture.dart',
      source: 'Object? read(String raw) => json.decode(raw);',
    ),
    (
      name: 'adapter cannot hide raw known DTO decoding behind JsonDecoder',
      path: 'code/anywork/lib/src/infrastructure/frb/fixture.dart',
      source: 'Object? read(String raw) => new JsonDecoder().convert(raw);',
    ),
    (
      name: 'decoder tear-off cannot bypass typed protocol boundaries',
      path: 'code/anywork_client/lib/src/conversation/data/fixture.dart',
      source: 'final parse = jsonDecode;',
    ),
    (
      name: 'json codec tear-off cannot bypass typed protocol boundaries',
      path: 'code/anywork_client/lib/src/conversation/data/fixture.dart',
      source: 'final parse = json.decode;',
    ),
    (
      name: 'the exact helper path is not an exemption for String input',
      path: _artifact,
      source: 'Object? read(String raw) => jsonDecode(raw);',
    ),
    (
      name: 'a known DTO json property is not an OpaqueArtifactJson input',
      path: _artifact,
      source: 'Object? read(KnownFrame value) => jsonDecode(value.json);',
    ),
    (
      name: 'an unrelated opaque parameter does not authorize other fields',
      path: _artifact,
      source: 'Object? read(OpaqueArtifactJson artifact, KnownFrame frame) => jsonDecode(frame.json);',
    ),
    (
      name: 'tool arguments stay opaque text even in the artifact helper',
      path: _artifact,
      source: 'Object? read(OpaqueArtifactJson artifact, TimelineToolPart tool) => jsonDecode(tool.arguments);',
    ),
    (
      name: 'raw-history content does not become an artifact JSON list',
      path: _artifact,
      source: 'Object? read(RawHistoryPayload value) => jsonDecode(value.content);',
    ),
    (
      name: 'a nested formal can shadow the opaque input without inheriting its exemption',
      path: _artifact,
      source: '''
Object? read(OpaqueArtifactJson artifact) {
  Object? nested(KnownFrame artifact) => jsonDecode(artifact.json);
  return null;
}
''',
    ),
    (
      name: 'a local known DTO cannot reuse an opaque loop variable name',
      path: _artifact,
      source: '''
void read(Iterable<OpaqueArtifactJson> artifacts) {
  for (final artifact in artifacts) {
    { final KnownFrame artifact = frame; jsonDecode(artifact.json); }
  }
}
''',
    ),
  ]) {
    test(fixture.name, () {
      final diagnostics = checkClientSource(path: fixture.path, source: fixture.source);
      expect(diagnostics.where((item) => item.rule == 'SYNTAX'), isEmpty,
          reason: 'A rejected fixture must still be valid Dart syntax');
      expect(diagnostics.map((item) => item.rule), contains('JSON-01'));
    });
  }

  test('only explicit opaque inputs in the approved helper can use the standard decoder', () {
    for (final source in [
      '''
import 'dart:convert' show jsonDecode;
import 'package:anywork_client/conversation.dart' show OpaqueArtifactJson;
Object? read(OpaqueArtifactJson artifact) => jsonDecode(artifact.json);
''',
      '''
import 'dart:convert' as standard;
import 'package:anywork_client/conversation.dart' show OpaqueArtifactJson;
void read(Iterable<OpaqueArtifactJson> artifacts) {
  for (final artifact in artifacts) {
    final Object? value = standard.jsonDecode(artifact.json);
  }
}
''',
      '''
Object? read(OpaqueArtifactJson artifact) => json.decode(artifact.json);
''',
      '''
Object? read(OpaqueArtifactJson artifact) => const JsonDecoder().convert(artifact.json);
''',
    ]) {
      expect(checkClientSource(path: _artifact, source: source), isEmpty);
    }
    expect(checkClientSource(
      path: 'code/anywork_client/lib/src/conversation/domain/fixture.dart',
      source: 'String raw(OpaqueArtifactJson value) => value.json;',
    ), isEmpty, reason: 'Repositories may retain the explicit opaque String without decoding it');
  });
}
