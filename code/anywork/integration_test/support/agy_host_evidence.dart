import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'agy_call_validator.dart';
import 'agy_host_trace.dart';

const agyHostEvidenceFilter =
    'warn,pl_studio_runtime::acp_host_call_evidence=trace';
const _target = 'pl_studio_runtime::acp_host_call_evidence';
const _message = 'host_mcp_call_result';

// Raw values stay private to this acceptance process. They are not ACP fields.
final class AgyHostRecord {
  AgyHostRecord._(
    this.pid,
    this.caller,
    this.hostCallId,
    this.toolId,
    this.arguments,
    this.value,
    this.isError,
    this.file,
    this.line,
  );
  final int pid;
  final String caller;
  final String hostCallId;
  final String toolId;
  final Map<String, dynamic> arguments;
  final dynamic value;
  final bool isError;
  final String file;
  final int line;

  factory AgyHostRecord.parse(
    dynamic data,
    int expectedPid,
    String file,
    int line,
  ) {
    const keys = {
      'kind',
      'version',
      'pid',
      'callerAgentId',
      'hostCallId',
      'toolId',
      'arguments',
      'value',
      'isError',
    };
    if (data is! Map<String, dynamic> ||
        data.length != keys.length ||
        !data.keys.every(keys.contains) ||
        data['kind'] != 'acp_host_call_result' ||
        data['version'] is! int ||
        data['version'] != 1 ||
        data['pid'] is! int ||
        data['pid'] != expectedPid ||
        expectedPid <= 0 ||
        data['arguments'] is! Map<String, dynamic> ||
        data['isError'] is! bool) {
      throw StateError('Invalid directed Host evidence schema/version/pid');
    }
    for (final key in ['callerAgentId', 'hostCallId', 'toolId']) {
      if (data[key] is! String || (data[key] as String).isEmpty) {
        throw StateError('Missing directed Host identity');
      }
    }
    if (!data['toolId'].startsWith('anywork_')) {
      throw StateError('Host directory key is not an anywork_ tool');
    }
    return AgyHostRecord._(
      expectedPid,
      data['callerAgentId'],
      data['hostCallId'],
      data['toolId'],
      _freeze(data['arguments']) as Map<String, dynamic>,
      _freeze(data['value']),
      data['isError'],
      file,
      line,
    );
  }

  Map<String, Object?> diagnostic(Set<String> commands, Set<String> markers) =>
      {
        'origin': 'host-domain-trace',
        'pid': pid,
        'callerAgentId': caller,
        'hostCallId': hostCallId,
        'toolId': toolId,
        'isError': isError,
        'file': file,
        'line': line,
        'arguments': agyEvidenceDiagnostic(
          arguments,
          safeCommands: commands,
          markers: markers,
        ),
        'value': agyEvidenceDiagnostic(
          value,
          safeCommands: commands,
          markers: markers,
        ),
      };
}

final class AgyHostCalls extends AgyCallValidator<AgyHostRecord> {
  AgyHostCalls(Iterable<AgyHostRecord> records, {this.collectionEvidence})
    : records = List.unmodifiable(records);
  final List<AgyHostRecord> records;
  final Map<String, Object?>? collectionEvidence;
  @override
  List<AgyHostRecord> named(String name) =>
      records.where((r) => r.toolId == name).toList();
  @override
  Map<String, dynamic> input(AgyHostRecord call) => call.arguments;
  @override
  dynamic output(AgyHostRecord call) {
    expect(
      call.isError,
      isFalse,
      reason: 'Host domain returned an error; body private',
    );
    return call.value;
  }

  List<Map<String, Object?>> diagnostics(
    Set<String> commands,
    Set<String> markers,
  ) => [for (final r in records) r.diagnostic(commands, markers)];
  void verifyGeneratedResults() {
    expect(records, isNotEmpty, reason: 'Missing Host domain return records');
    for (final call in records) {
      output(call);
    }
  }

  Map<String, Object?> verifyCallerCounter(String caller, int expectedTotal) {
    final queries = named('anywork_list_agents');
    if (queries.length != 1 || queries.single.caller != caller) {
      throw StateError('Missing uniquely scoped final Host counter query');
    }
    final value = output(queries.single);
    final rows = value is List
        ? value.whereType<Map<String, dynamic>>().where(
            (r) => r['id'] == caller,
          )
        : const Iterable<Map<String, dynamic>>.empty();
    final matches = rows.toList();
    final host = matches.length == 1 ? matches.single['hostMcp'] : null;
    if (host is! Map<String, dynamic> ||
        host['injected'] != true ||
        host['observedToolCalls'] is! int ||
        host['observedToolCalls'] != expectedTotal) {
      throw StateError(
        'Host counter differs from captured returns; body private',
      );
    }
    return {
      'callerAgentId': caller,
      'counterQueryHostCallId': queries.single.hostCallId,
      'observedToolCalls': host['observedToolCalls'],
      'capturedReturns': expectedTotal,
    };
  }
}

// Test-local bounded reader only. Rotation is rolling-file's numbered rename,
// not time/ID ordering. No log/protocol writer or business execution lives here.
final class AgyHostEvidenceLog {
  AgyHostEvidenceLog({
    required Directory home,
    required this.guiPid,
    required String rootCaller,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxEvents = 4096,
  }) : directory = Directory(p.join(home.path, 'studio', 'logs')),
       _home = home {
    if (guiPid <= 0 || maxBytes <= 0 || maxEvents <= 0) {
      throw StateError('Invalid Host evidence reader pid/bounds');
    }
    bindCaller(rootCaller);
  }
  final Directory directory;
  final Directory _home;
  final int guiPid;
  final int maxBytes;
  final int maxEvents;
  final Set<String> _callers = {};
  final Set<String> _claimed = {};
  Map<String, List<int>> _priorFiles = {};
  Map<String, String> _priorRecords = {};
  List<AgyHostRecord> _records = [];
  bool pendingTail = false;
  String fingerprint = '';
  List<Map<String, Object?>> diagnostics(
    Set<String> commands,
    Set<String> markers,
  ) => [
    for (final r in _records)
      {
        ...r.diagnostic(commands, markers),
        'claimed': _claimed.contains(r.hostCallId),
        'boundCaller': _callers.contains(r.caller),
      },
  ];

  void bindCaller(String caller) {
    if (caller.isEmpty) throw StateError('Empty bound Host caller');
    _callers.add(caller);
  }

  Future<void> read() async {
    final canonicalHome = await _home.resolveSymbolicLinks();
    if (await directory.resolveSymbolicLinks() !=
        p.join(canonicalHome, 'studio', 'logs')) {
      throw StateError('Host log directory escaped the specified home');
    }
    Map<String, List<int>>? snapshot;
    for (var attempt = 0; attempt < 3; attempt++) {
      final current = <String, List<int>>{};
      var bytes = 0;
      try {
        final before = await _files();
        final beforeSignature = await _signature(before);
        for (final file in before) {
          final size = await file.length();
          if (bytes + size > maxBytes) {
            throw StateError('Host evidence total byte bound exceeded');
          }
          final input = await file.open();
          late final List<int> data;
          try {
            // Bound the allocation even if the writer appends after length().
            data = await input.read(maxBytes - bytes + 1);
          } finally {
            await input.close();
          }
          bytes += data.length;
          if (bytes > maxBytes) {
            throw StateError('Host evidence total byte bound exceeded');
          }
          current[p.basename(file.path)] = data;
        }
        final after = await _files();
        if (beforeSignature == await _signature(after)) {
          snapshot = current;
          break;
        }
      } on FileSystemException {
        if (attempt == 2) rethrow;
      } on _RotationPending catch (error) {
        if (attempt == 2) throw StateError(error.message);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (snapshot == null) {
      throw StateError('Host rotation did not yield a complete snapshot');
    }
    for (final prior in _priorFiles.values.where((b) => b.isNotEmpty)) {
      if (snapshot.values.where((bytes) => _prefix(bytes, prior)).length != 1) {
        throw StateError(
          'Host rolling history was lost, rewritten or ambiguous',
        );
      }
    }
    final records = <AgyHostRecord>[];
    final hashes = <String, String>{};
    var tail = false;
    for (final entry in snapshot.entries) {
      final bytes = entry.value;
      final end = bytes.lastIndexOf(10) + 1;
      tail |= end != bytes.length;
      String complete;
      try {
        complete = utf8.decode(bytes.sublist(0, end));
      } on FormatException {
        throw StateError('Invalid UTF-8 in a complete Host log line');
      }
      var lineNumber = 0;
      for (final line in const LineSplitter().convert(complete)) {
        lineNumber++;
        final record = parseLine(line, guiPid, entry.key, lineNumber);
        if (record == null) continue;
        if (hashes.containsKey(record.hostCallId)) {
          throw StateError('Duplicate Host call ID');
        }
        if (records.length >= maxEvents) {
          throw StateError('Host evidence event bound exceeded');
        }
        final hash = _identity(record);
        if (_priorRecords.containsKey(record.hostCallId) &&
            _priorRecords[record.hostCallId] != hash) {
          throw StateError('Host record changed');
        }
        hashes[record.hostCallId] = hash;
        records.add(record);
      }
    }
    if (!_priorRecords.keys.every(hashes.containsKey)) {
      throw StateError('Host records lost during rotation');
    }
    _records = List.unmodifiable(records);
    _priorRecords = hashes;
    _priorFiles = snapshot;
    pendingTail = tail;
    fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              for (final e in snapshot.entries)
                e.key: sha256.convert(e.value).toString(),
            }),
          ),
        )
        .toString();
  }

  Future<List<File>> _files() async {
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (!RegExp(r'^studio\.log(?:\.[1-7])?$').hasMatch(name)) {
        if (name.startsWith('studio.log.')) {
          throw StateError('Unsupported Studio rotation filename');
        }
        continue;
      }
      if (entity is! File || await FileSystemEntity.isLink(entity.path)) {
        throw StateError('Host evidence log is not an ordinary file');
      }
      files.add(entity);
    }
    if (files.isEmpty ||
        !files.any((f) => p.basename(f.path) == 'studio.log')) {
      throw const _RotationPending(
        'Missing current Studio log; evidence is not zero',
      );
    }
    final indexes = files.map((f) => _index(f.path)).toSet();
    if (indexes.length != indexes.reduce((a, b) => a > b ? a : b) + 1) {
      throw const _RotationPending('Incomplete numbered Studio rotation');
    }
    files.sort((a, b) => _index(b.path).compareTo(_index(a.path)));
    return files;
  }

  Future<String> _signature(List<File> files) async => jsonEncode([
    for (final file in files)
      [
        file.path,
        ...await file.stat().then(
          (stat) => [stat.type.toString(), stat.size, stat.modified.toString()],
        ),
      ],
  ]);

  static AgyHostRecord? parseLine(
    String line,
    int pid,
    String file,
    int number,
  ) {
    final header = RegExp(
      r'^(?:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s+)?TRACE\s+(?:ThreadId\(\d+\)\s+)?pl_studio_runtime::acp_host_call_evidence: host_mcp_call_result record_json=(.*)$',
    );
    final match = header.firstMatch(line);
    if (match == null) {
      if (line.contains('$_target: $_message')) {
        throw StateError('Unsupported directed Host log header');
      }
      return null;
    }
    dynamic data;
    try {
      data = jsonDecode(match.group(1)!);
    } on FormatException {
      throw StateError('Malformed complete Host evidence JSON');
    }
    return AgyHostRecord.parse(data, pid, file, number);
  }

  Future<AgyHostCalls> matchPhase(
    AgyHostTrace acp,
    String caller, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_callers.contains(caller)) throw StateError('Unbound Host caller');
    final expected = <String, int>{};
    for (final call in acp.calls) {
      final name = AgyHostTrace.canonicalName(call.fields.name);
      if (name != null) _add(expected, _key(name, acp.input(call)));
    }
    if (expected.isEmpty) throw StateError('Missing formal ACP Host calls');
    final expires = DateTime.now().add(timeout);
    while (true) {
      await read();
      final available = _records
          .where((r) => r.caller == caller && !_claimed.contains(r.hostCallId))
          .toList();
      final actual = <String, int>{};
      for (final call in available) {
        _add(actual, _key(call.toolId, call.arguments));
      }
      if (actual.entries.any((e) => e.value > (expected[e.key] ?? 0))) {
        throw StateError('Extra Host call/arguments in phase multiset');
      }
      if (!pendingTail && _same(expected, actual)) {
        _claimed.addAll(available.map((r) => r.hostCallId));
        return AgyHostCalls(
          available,
          collectionEvidence: {
            'origin': 'host-domain-trace',
            'pid': guiPid,
            'callerAgentId': caller,
            'acpToolCallIds': [
              for (final call in acp.calls)
                if (AgyHostTrace.canonicalName(call.fields.name) != null)
                  call.toolCallId.value,
            ],
            'hostCallIds': available.map((r) => r.hostCallId).toList(),
            'callCount': available.length,
            'argumentsMultisetSha256': sha256
                .convert(utf8.encode(jsonEncode(_canonical(expected))))
                .toString(),
            'pairing': 'multiset equality only; no ID-to-ID mapping',
          },
        );
      }
      if (!DateTime.now().isBefore(expires)) {
        throw StateError('Missing Host phase records or incomplete tail');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<AgyHostCalls> claimChild(
    String caller,
    int expectedCount, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_callers.contains(caller) || expectedCount < 2) {
      throw StateError('Unbound/invalid child Host scope');
    }
    final expires = DateTime.now().add(timeout);
    while (true) {
      await read();
      final records = _records
          .where((r) => r.caller == caller && !_claimed.contains(r.hostCallId))
          .toList();
      if (records.length > expectedCount) {
        throw StateError('Extra child Host records');
      }
      if (!pendingTail && records.length == expectedCount) {
        _claimed.addAll(records.map((r) => r.hostCallId));
        return AgyHostCalls(records);
      }
      if (!DateTime.now().isBefore(expires)) {
        throw StateError('Missing child Host records');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, Object?>> verifyDrained({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final expires = DateTime.now().add(timeout);
    String? last;
    while (true) {
      await read();
      if (_records.any(
        (r) => !_callers.contains(r.caller) || !_claimed.contains(r.hostCallId),
      )) {
        throw StateError(
          'Unclaimed/foreign Host evidence after phase or close',
        );
      }
      if (!pendingTail && last == fingerprint) {
        return {
          'origin': 'host-domain-trace',
          'completeRecords': _records.length,
          'claimedRecords': _claimed.length,
          'pendingTail': false,
          'stableSnapshots': 2,
          'fingerprint': fingerprint,
          'semantics':
              'domain return generation; not transport/consumption ACK',
        };
      }
      last = pendingTail ? null : fingerprint;
      if (!DateTime.now().isBefore(expires)) {
        throw StateError('Host log did not drain completely');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

final class _RotationPending implements Exception {
  const _RotationPending(this.message);
  final String message;
}

int _index(String path) =>
    p.basename(path) == 'studio.log' ? 0 : int.parse(path.split('.').last);
bool _prefix(List<int> value, List<int> prefix) {
  if (value.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (value[i] != prefix[i]) return false;
  }
  return true;
}

dynamic _freeze(dynamic value) => switch (value) {
  Map<String, dynamic> map => Map<String, dynamic>.unmodifiable(
    map.map((k, v) => MapEntry(k, _freeze(v))),
  ),
  List list => List<dynamic>.unmodifiable(list.map(_freeze)),
  _ => value,
};
dynamic _canonical(dynamic value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _key(String tool, Map<String, dynamic> args) =>
    jsonEncode([tool, _canonical(args)]);
String _identity(AgyHostRecord r) => jsonEncode([
  r.pid,
  r.caller,
  r.hostCallId,
  r.toolId,
  _canonical(r.arguments),
  _canonical(r.value),
  r.isError,
]);
void _add(Map<String, int> map, String key) => map[key] = (map[key] ?? 0) + 1;
bool _same(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
