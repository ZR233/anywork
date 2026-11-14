import 'dart:convert';

import 'package:anywork_client/acp_sessions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/acp_acceptance_fixture.dart' as f;
import '../integration_test/support/agy_host_evidence.dart';
import '../integration_test/support/agy_host_trace.dart';
import '../integration_test/support/agy_json_evidence.dart';

void main() {
  test('parameter fingerprints share exact canonical key ordering', () {
    final arguments = <String, dynamic>{
      'z': [
        {'b': 2, 'a': null},
        'text',
      ],
      'a': {'d': true, 'c': 1},
    };
    final reversed = <String, dynamic>{
      'a': {'c': 1, 'd': true},
      'z': [
        {'a': null, 'b': 2},
        'text',
      ],
    };
    final before = jsonEncode(arguments);
    final fingerprint = agyArgumentsFingerprint(arguments);
    expect(fingerprint, agyArgumentsFingerprint(reversed));
    final bytes = utf8.encode(jsonEncode(agyCanonicalJson(arguments)));
    expect(fingerprint['sha256'], sha256.convert(bytes).toString());
    expect(fingerprint['utf8Bytes'], bytes.length);
    expect(fingerprint['topLevelFieldCount'], 2);
    expect(
      (fingerprint['fields'] as List).first['keySha256'],
      sha256.convert(utf8.encode('a')).toString(),
    );
    expect(jsonEncode(arguments), before);
  });

  test(
    'parameter fingerprints retain field value and collection distinctions',
    () {
      final differences = <(Map<String, dynamic>, Map<String, dynamic>)>[
        ({'x': 1}, {'x': 2}),
        ({}, {'x': null}),
        ({'x': null}, {'x': false}),
        (
          {
            'x': [1, 2],
          },
          {
            'x': [2, 1],
          },
        ),
        (
          {
            'x': [1],
          },
          {
            'x': [1, 1],
          },
        ),
        ({'x': 1}, {'x': 1.0}),
        ({'cwd': '.'}, {'cwd': './'}),
      ];
      for (final (left, right) in differences) {
        expect(
          agyArgumentsFingerprint(left)['sha256'],
          isNot(agyArgumentsFingerprint(right)['sha256']),
        );
      }
      final integer = agyArgumentsFingerprint({'x': 1});
      final decimal = agyArgumentsFingerprint({'x': 1.0});
      expect((integer['fields'] as List).single['valueJsonType'], 'integer');
      expect((decimal['fields'] as List).single['valueJsonType'], 'decimal');
    },
  );

  test(
    'ACP and failed Host diagnostics hash unchanged arguments without secrets',
    () async {
      const secretKey = 'PRIVATE_FIELD_NAME_DO_NOT_EXPORT';
      const secretValue = 'PRIVATE_PARAMETER_VALUE_DO_NOT_EXPORT';
      const cwd = '/private/PRIVATE_CWD_DO_NOT_EXPORT';
      final arguments = <String, dynamic>{
        secretKey: {'nested': secretValue},
        'cwd': cwd,
        'command': secretValue,
      };
      final before = jsonEncode(arguments);
      final fixture = await f.Fixture.open();
      final trace = await fixture.calls([
        {'name': 'anywork_exec_command', 'input': arguments, 'output': null},
      ]);
      final record = AgyHostRecord.parse(
        {
          'kind': 'acp_host_call_result',
          'version': 1,
          'pid': 4242,
          'callerAgentId': 'fixture-agent',
          'hostCallId': 'original-host-call',
          'toolId': 'anywork_exec_command',
          'arguments': arguments,
          'value': {
            'diagnostic': {'cwd': cwd},
          },
          'isError': true,
        },
        4242,
        'studio.log',
        1,
      );
      final host = AgyHostCalls([record]);
      final acpDiagnostic = trace
          .diagnostics(safeCommands: {}, markers: {})
          .single;
      final hostDiagnostic = host.diagnostics({}, {}).single;
      expect(
        acpDiagnostic['rawInputFingerprint'],
        hostDiagnostic['argumentsFingerprint'],
      );
      for (final diagnostic in [acpDiagnostic, hostDiagnostic]) {
        final encoded = jsonEncode(diagnostic);
        for (final secret in [secretKey, secretValue, cwd]) {
          expect(encoded.contains(secret), isFalse);
        }
      }
      expect(trace.input(trace.calls.single), arguments);
      expect(record.arguments, arguments);
      expect(jsonEncode(arguments), before);
      expect(host.verifyGeneratedResults, throwsA(isA<TestFailure>()));
    },
  );

  test(
    'non-object or unrepresentable raw input remains diagnosable without hash',
    () async {
      final samples = <(AcpJsonValue?, String, String)>[
        (null, 'missing', 'null'),
        (const AcpJsonNull(), 'null', 'null'),
        (const AcpJsonString('private'), 'present', 'string'),
        (AcpJsonArray([]), 'present', 'array'),
        (AcpJsonInteger(BigInt.zero), 'present', 'number'),
        (AcpJsonInteger(BigInt.one << 80), 'unrepresentable', 'AcpJsonInteger'),
      ];
      for (final (raw, state, type) in samples) {
        final fixture = await f.Fixture.open();
        f.push(
          fixture.source,
          f.update(
            AcpToolCallSessionUpdateView(
              AcpToolCallView(
                toolCallId: const AcpToolCallId('input-shape'),
                title: 'Fixture',
                name: 'anywork_exec_command',
                kind: AcpToolKindView.execute,
                status: AcpToolCallStatusView.completed,
                rawInput: raw,
              ),
            ),
          ),
        );
        await fixture.owner.source.waitFor(
          (s) => s.content.whereType<AcpConversationToolItem>().isNotEmpty,
        );
        final trace = AgyHostTrace(fixture.owner.state.content);
        final diagnostic = trace
            .diagnostics(safeCommands: {}, markers: {})
            .single;
        expect(diagnostic['rawInputState'], state);
        expect(diagnostic['rawInputType'], type);
        expect(diagnostic.containsKey('rawInputFingerprint'), isFalse);
        expect(() => trace.input(trace.calls.single), throwsStateError);
      }
    },
  );
}
