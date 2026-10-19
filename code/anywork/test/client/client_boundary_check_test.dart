import 'package:flutter_test/flutter_test.dart';

import '../../../../xtask/dart/client_boundary_check.dart';

const _client = 'code/anywork_client/lib/src/fixture.dart';
const _feature = 'code/anywork/lib/src/features/chat/chat_view.dart';
const _account = 'code/anywork/lib/src/presentation/providers/fixture.dart';

void main() {
  // These are parsed Dart programs, not examples of a rule's own regexp or
  // expected diagnostic text. The CLI and these tests use the same AST walk.
  for (final fixture in <({String name, String path, String source, String rule})>[
    (
      name: 'Client cannot import Flutter',
      path: _client,
      source: "import 'package:flutter/widgets.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Client cannot hide Riverpod in a conditional export',
      path: _client,
      source:
          "export 'safe.dart' if (dart.library.io) "
          "'package:riverpod/riverpod.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Client cannot accept a account Ref',
      path: _client,
      source: 'void observe(Ref ref) {}',
      rule: 'OWN-01',
    ),
    (
      name: 'Feature cannot use relative FRB adapter imports',
      path: _feature,
      source: "import '../../infrastructure/frb/studio_api.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Feature cannot import generated wire DTOs',
      path: _feature,
      source: "import 'package:anywork/src/rust/api/studio/types/chat.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Feature cannot import public transport ports directly',
      path: _feature,
      source: "import 'package:anywork_client/studio_ports.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'App cannot reach private Client code',
      path: _account,
      source: "import 'package:anywork_client/src/chat/channel.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Client map is not a module owner',
      path: _client,
      source: 'final entries = <String, Object>{};',
      rule: 'LIFE-01',
    ),
    (
      name: 'Static Thread cache is not an app owner',
      path: _account,
      source:
          'class Cache { static final threadSessions = <String, Object>{}; }',
      rule: 'LIFE-01',
    ),
    (
      name: 'AnyworkClient cannot be a module singleton',
      path: _account,
      source: 'final client = new AnyworkClient(transport: transport);',
      rule: 'LIFE-01',
    ),
    (
      name: 'Provider disposal cannot close a session',
      path: _account,
      source:
          'void bind(dynamic ref, dynamic session) { '
          'ref.onDispose(() { session.close(); }); }',
      rule: 'LIFE-02',
    ),
    (
      name: 'Provider cancellation cannot register a close tearoff',
      path: _account,
      source:
          'void bind(dynamic ref, dynamic session) { '
          'ref.onCancel(session.close); }',
      rule: 'LIFE-02',
    ),
    for (final owner in ['session', 'composer', 'skills', 'sessionCosts'])
      (
        name: 'Provider cannot admit a $owner owner',
        path: _account,
        source:
            'Object observe(dynamic client, String id) => client.$owner(id);',
        rule: 'LIFE-03',
      ),
    (
      name: 'Provider cannot admit through a cascade',
      path: _account,
      source: 'void observe(dynamic client) { client..session("thread"); }',
      rule: 'LIFE-03',
    ),
    (
      name: 'Commands cannot reread aggregate state',
      path: 'code/anywork_client/lib/src/commands/thread_commands.dart',
      source:
          'Future<void> rename(dynamic transport) async { '
          'await transport.rename(); await transport.readStudioState(); }',
      rule: 'CMD-02',
    ),
    (
      name: 'View cannot combine Thread props with its own business read',
      path: _feature,
      source:
          'class ChatView { '
          'ChatView({required this.threadId}); final String threadId; '
          'void build(dynamic ref) { '
          'ref.watch(threadSessionStoreProvider(threadId)); } }',
      rule: 'UI-01',
    ),
    (
      name: 'Timeline cannot key a row by mutable content',
      path: _feature,
      source: 'Object rowKey(dynamic row) => new ValueKey(row.text);',
      rule: 'UI-01',
    ),
    (
      name: 'Dropped failure needs an explanation',
      path: _account,
      source: 'void update() { try { work(); } catch (error) {} }',
      rule: 'ERR-01',
    ),
  ]) {
    test(fixture.name, () {
      final diagnostics = checkClientSource(
        path: fixture.path,
        source: fixture.source,
      );
      expect(
        diagnostics.where((d) => d.rule == 'SYNTAX'),
        isEmpty,
        reason: 'A forbidden program must be valid Dart syntax',
      );
      expect(diagnostics.map((d) => d.rule), contains(fixture.rule));
      expect(diagnostics.every((d) => d.line > 0 && d.column > 0), isTrue);
    });
  }

  test(
    'SDK imports, instance owners and observation cancellation are allowed',
    () {
      expect(
        checkClientSource(
          path: _client,
          source: '''
import 'dart:async';
import 'package:anywork_client/anywork_client.dart';
class Owner {
  final sessions = <String, Object>{};
  final events = StreamController<Object>();
}
''',
        ),
        isEmpty,
      );
      expect(
        checkClientSource(
          path: _account,
          source: '''
void observe(dynamic ref, dynamic source) {
  final observation = source.watchLatest((next) {});
  ref.onDispose(observation.cancel);
}
Object? existing(dynamic client, String id) => client.existingSession(id);
Object descriptor(String id) => new ThreadRuntimeTopic(id);
''',
        ),
        isEmpty,
      );
      expect(
        checkClientSource(
          path: _feature,
          source: '''
import 'package:anywork_client/studio_client.dart';
Object rowKey(String itemId) => new ValueKey(itemId);
''',
        ),
        isEmpty,
      );
    },
  );

  test(
    'comments and string contents do not create imports or lifecycle calls',
    () {
      expect(
        checkClientSource(
          path: _account,
          source: '''
// ref.onDispose(() { session.close(); });
const example = "import 'package:anywork_client/src/private.dart';";
const command = 'readStudioState(); session.close();';
void ignore() {
  try { work(); } catch (error) {
    // Optional observation is already cancelled; no resource remains owned here.
  }
}
''',
        ),
        isEmpty,
      );
    },
  );

  test('invalid source fails closed with a positioned syntax diagnostic', () {
    final diagnostics = checkClientSource(path: _client, source: 'final = ;');
    expect(diagnostics.map((d) => d.rule), contains('SYNTAX'));
    expect(diagnostics.first.toString(), contains('$_client:1:'));
  });
}
