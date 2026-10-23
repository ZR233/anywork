import 'dart:convert';
import 'dart:math' as math;

import '../../../resources.dart';
import '../../../resources_ports.dart' show resourceProtocol;
import '../domain/mode_values.dart';
import 'modes_port.dart';

Future<ThreadModeDescriptor> readModeDescriptor(ModeCatalogReadConnection scope, ThreadModeDescriptorRead value) async => ThreadModeDescriptor(id: value.id, displayName: await readModeText(scope, value.displayName), description: await readModeText(scope, value.description), order: value.order, hasWorkflow: value.hasWorkflow, readOnly: value.readOnly);

Future<String> readModeText(ModeCatalogReadConnection scope, ReadText value) async {
  if (value case InlineReadText(:final text)) {
    if (utf8.encode(text).length > 4096) throw resourceProtocol('An inline Mode field exceeds its transport limit.');
    return text;
  }
  final field = value as DeferredReadText;
  if (field.utf8Bytes < 0) throw resourceProtocol('A Mode field has an invalid length.');
  var offset = 0;
  final output = StringBuffer();
  while (offset < field.utf8Bytes) {
    final limit = math.min(65536, field.utf8Bytes - offset);
    final chunk = await scope.text(field.fieldId, offset: offset, maxBytes: limit);
    final bytes = utf8.encode(chunk.text).length;
    final end = offset + bytes;
    if (chunk.fieldId != field.fieldId || chunk.offset != offset || bytes == 0 || bytes > limit || end < offset || end > field.utf8Bytes || chunk.nextOffset != (end == field.utf8Bytes ? null : end)) throw resourceProtocol('A Mode text chunk does not match its pinned field.');
    output.write(chunk.text);
    offset = end;
  }
  return output.toString();
}
