import 'package:flutter_test/flutter_test.dart';

import '../../../../xtask/dart/client_boundary_check.dart';

const _client = 'code/anywork_client/lib/src/fixture.dart';
const _feature = 'code/anywork/lib/src/features/chat/chat_view.dart';
const _account = 'code/anywork/lib/src/presentation/providers/fixture.dart';
const _accountsFeature = 'code/anywork/lib/src/features/settings/accounts/';

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
      name: 'Account View cannot import a domain Repository',
      path: '${_accountsFeature}views/fixture.dart',
      source: "import 'package:anywork_client/accounts.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Pure entry cannot hide a Connector in a conditional export',
      path: '${_accountsFeature}accounts_views.dart',
      source:
          "export 'state/fixture.dart' if (dart.library.io) "
          "'connectors/fixture.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Preview cannot hide a Provider in a conditional import',
      path: '${_accountsFeature}previews/fixture.dart',
      source:
          "import 'fixture.dart' if (dart.library.io) "
          "'package:flutter_riverpod/flutter_riverpod.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Account Widget cannot import AppGraph through a relative path',
      path: '${_accountsFeature}widgets/fixture.dart',
      source: "import '../../../../app/app_graph.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Pure View cannot import a VM through a package path',
      path: '${_accountsFeature}views/fixture.dart',
      source:
          "import 'package:anywork/src/features/settings/accounts/"
          "view_models/fixture.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Pure View cannot use the aggregate app model export',
      path: '${_accountsFeature}views/fixture.dart',
      source: "import '../../../../domain/models/studio_models.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Account state cannot depend on Flutter controllers',
      path: '${_accountsFeature}state/fixture.dart',
      source: "import 'package:flutter/widgets.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Account state cannot carry an async resource',
      path: '${_accountsFeature}state/fixture.dart',
      source:
          'class ViewState { final Future<void> pending; '
          'ViewState(this.pending); }',
      rule: 'UI-02',
    ),
    (
      name: 'Account VM cannot import Widgets',
      path: '${_accountsFeature}view_models/fixture.dart',
      source: "import 'package:flutter/material.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Account VM cannot import the pure Widget barrel',
      path: '${_accountsFeature}view_models/fixture.dart',
      source: "import '../accounts_views.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Account VM cannot import domain transport ports',
      path: '${_accountsFeature}view_models/fixture.dart',
      source: "import 'package:anywork_client/accounts_ports.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Account VM cannot import a concrete adapter',
      path: '${_accountsFeature}view_models/fixture.dart',
      source: "import '../../../../infrastructure/frb/studio_api.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Account modules cannot hide dependencies in handwritten parts',
      path: '${_accountsFeature}view_models/fixture.dart',
      source: "part 'hidden.dart';",
      rule: 'UI-02',
    ),
    (
      name: 'Account View cannot become part of a Connector library',
      path: '${_accountsFeature}views/fixture.dart',
      source: "part of '../connectors/fixture.dart';",
      rule: 'UI-02',
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
Object? existing(dynamic client, String id) => client.conversations.existingSession(id);
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
    'pure account presentation and injected VM dependencies are allowed',
    () {
      for (final fixture in <({String path, String source})>[
        (
          path: '${_accountsFeature}views/fixture.dart',
          source: '''
import 'package:flutter/material.dart';
import '../state/fixture.dart';
import '../../../../shared/account_brand.dart';
''',
        ),
        (
          path: '${_accountsFeature}previews/fixture.dart',
          source: '''
import 'package:flutter/widget_previews.dart';
import '../accounts_views.dart';
import '../../../../app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
// import 'package:anywork_client/accounts.dart';
const example = "import 'package:flutter_riverpod/flutter_riverpod.dart';";
''',
        ),
        (
          path: '${_accountsFeature}state/fixture.dart',
          source: '''
import 'package:freezed_annotation/freezed_annotation.dart';
part 'fixture.freezed.dart';
class ViewState {
  final String raw;
  ViewState(this.raw);
}
''',
        ),
        (
          path: '${_accountsFeature}view_models/fixture.dart',
          source: '''
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:anywork_client/accounts.dart';
import '../../../../presentation/providers/account_domains.dart';
import '../state/fixture.dart';
part 'fixture.g.dart';
''',
        ),
      ]) {
        expect(
          checkClientSource(path: fixture.path, source: fixture.source),
          isEmpty,
          reason: fixture.path,
        );
      }
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
