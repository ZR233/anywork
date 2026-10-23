import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/skills_values.dart';
import 'skills_port.dart';
import 'skills_reads.dart';

/// Business mapping within one original immutable project catalog scope.
final class SkillsReader {
  SkillsReader(this.scope) : _text = ((field, offset) =>
    scope.text(field, offset: offset, maxBytes: 65536));
  final SkillsReadConnection scope;
  final Future<TextChunk> Function(int fieldId, int offset) _text;

  Future<SkillsReadHeader> header({required String projectId, required int catalogRevision,
      required bool complete, required int total}) async {
    final value = await scope.header();
    if (await materializeReadText(value.projectId, read: _text) != projectId ||
        value.catalogRevision != catalogRevision || value.catalog.complete != complete ||
        value.catalog.skills.listId < 0 || value.catalog.skills.total != total) {
      throw resourceProtocol('Skills root header changed its original project catalog.');
    }
    return value;
  }

  Future<SkillSummary> skill(SkillSummaryRead value) async => SkillSummary(
    name: await materializeReadText(value.name, read: _text),
    description: await materializeReadText(value.description, read: _text),
    category: value.category == null ? null : await materializeReadText(value.category!, read: _text),
    platforms: await strings(value.platforms), source: value.source,
    providerId: await materializeReadText(value.providerId, read: _text),
    invocation: SkillInvocationPolicy(modelInvocable: value.invocation.modelInvocable,
      userInvocable: value.invocation.userInvocable),
    resourceBase: await resourceBase(value.resourceBase));

  Future<SkillResourceBase> resourceBase(SkillResourceBaseRead value) async => switch (value) {
    DirectorySkillResourceBaseRead(:final path) =>
      SkillResourceBase.directory(path: await materializeReadText(path, read: _text)),
    UrlSkillResourceBaseRead(:final url) =>
      SkillResourceBase.url(url: await materializeReadText(url, read: _text)),
    OpaqueSkillResourceBaseRead(:final description) =>
      SkillResourceBase.opaque(description: await materializeReadText(description, read: _text)),
  };

  Future<List<String>> strings(TypedListRef ref) async {
    if (ref.listId < 0 || ref.total < 0) throw resourceProtocol('Invalid Skills string list.');
    final values = <String>[];
    var offset = 0;
    while (offset < ref.total) {
      final page = await scope.strings(ref.listId, offset: offset);
      final items = List.of(page.items);
      final end = offset + items.length;
      if (page.listId != ref.listId || page.offset != offset || page.total != ref.total ||
          items.isEmpty || items.length > 32 || end > ref.total ||
          page.nextOffset != (end == ref.total ? null : end)) {
        throw resourceProtocol('Skills string page changed its frozen list.');
      }
      for (final item in items) {
        values.add(await materializeReadText(item.value, read: _text));
      }
      offset = end;
    }
    return List.unmodifiable(values);
  }
}
