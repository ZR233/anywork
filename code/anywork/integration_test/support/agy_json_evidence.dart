import 'dart:convert';

import 'package:crypto/crypto.dart';

// Shared with the exact argument multiset comparator. Only object key order is
// canonicalized; field presence, value types, array order and multiplicity stay.
dynamic agyCanonicalJson(dynamic value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: agyCanonicalJson(value[key])};
  }
  if (value is List) return value.map(agyCanonicalJson).toList();
  return value;
}

// The canonical JSON exists only in memory. No parameter names or values are
// returned. Key digests hash raw UTF-8 keys; key-set/value digests hash JSON.
Map<String, Object?> agyArgumentsFingerprint(Map<String, dynamic> arguments) {
  final keys = arguments.keys.toList()..sort();
  final bytes = utf8.encode(jsonEncode(agyCanonicalJson(arguments)));
  return {
    'sha256': sha256.convert(bytes).toString(),
    'utf8Bytes': bytes.length,
    'topLevelFieldCount': keys.length,
    'keysSha256': sha256.convert(utf8.encode(jsonEncode(keys))).toString(),
    'fields': [for (final key in keys) _fieldFingerprint(key, arguments[key])],
  };
}

Map<String, Object?> _fieldFingerprint(String key, dynamic value) {
  final bytes = utf8.encode(jsonEncode(agyCanonicalJson(value)));
  return {
    'keySha256': sha256.convert(utf8.encode(key)).toString(),
    'valueSha256': sha256.convert(bytes).toString(),
    'valueJsonType': switch (value) {
      null => 'null',
      Map() => 'object',
      List() => 'array',
      String() => 'string',
      bool() => 'boolean',
      int() => 'integer',
      double() => 'decimal',
      _ => throw StateError('Unsupported JSON fingerprint value type'),
    },
    'valueUtf8Bytes': bytes.length,
  };
}
