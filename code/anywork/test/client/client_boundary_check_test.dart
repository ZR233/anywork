import 'package:flutter_test/flutter_test.dart';

import '../../../../xtask/dart/client_boundary_check.dart';

const _client = 'code/anywork_client/lib/src/fixture.dart';
const _feature = 'code/anywork/lib/src/features/conversation/views/chat_view.dart';
const _account = 'code/anywork/lib/src/presentation/providers/fixture.dart';
const _state = 'code/anywork/lib/src/features/conversation/state/fixture.dart';
const _vm = 'code/anywork/lib/src/features/settings/view_models/fixture.dart';
const _adapter = 'code/anywork/lib/src/infrastructure/frb/fixture.dart';

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
      name: 'Freezed allowance does not permit arbitrary pure Dart packages',
      path: _client,
      source: "import 'package:collection/collection.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Freezed allowance cannot hide a private conditional import',
      path: _client,
      source:
          "import 'package:freezed_annotation/freezed_annotation.dart' "
          "if (dart.library.io) 'package:freezed_annotation/src/models.dart';",
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
      name: 'Feature cannot import the conversation transport entrypoint',
      path: _feature,
      source: "import 'package:anywork_client/conversation_ports.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'New domain ports cannot bypass the feature boundary',
      path: _feature,
      source: "import 'package:anywork_client/configuration_ports.dart';",
      rule: 'OWN-01',
    ),
    (
      name: 'Dumb imports cannot hide Riverpod in a conditional branch',
      path: _feature,
      source:
          "import 'safe.dart' if (dart.library.io) "
          "'package:flutter_riverpod/flutter_riverpod.dart';",
      rule: 'UI-02',
    ),
    for (final owner in ['WidgetRef', 'ConfigurationRepository', 'ThreadSession',
      'TimelineConnection', 'AppGraph', 'GetIt'])
      (
        name: 'Dumb cannot receive $owner instead of immutable props',
        path: _feature,
        source: 'class ConversationView { ConversationView(this.owner); '
            'final $owner owner; }',
        rule: 'UI-02',
      ),
    (
      name: 'Dumb cannot use a service locator without a Ref',
      path: _feature,
      source: 'Object build() => getIt.get<ConfigurationRepository>();',
      rule: 'UI-02',
    ),
    for (final owner in ['Widget', 'WidgetRef', 'Future<void>',
      'StreamSubscription<int>', 'TimelineConnection', 'OperationTicket<int>',
      'TextEditingController', 'ReadonlyLatestValue<int>'])
      (
        name: 'Freezed state cannot value-object runtime owner $owner',
        path: _state,
        source: '@freezed abstract class EditorState with _\$EditorState { '
            'const factory EditorState({required $owner owner}) = _EditorState; }',
        rule: 'STATE-01',
      ),
    (
      name: 'Generated state cannot import Widgets to hide an owner type',
      path: _state,
      source: "import 'package:flutter/widgets.dart' as ui;",
      rule: 'STATE-01',
    ),
    (
      name: 'Plain legacy wrapper is not a generated AsyncNotifier VM',
      path: _vm,
      source: 'class AccountViewModel { int build() => 0; }',
      rule: 'VM-02',
    ),
    (
      name: 'Generated name alone does not turn a canonical getter into a VM',
      path: _vm,
      source: '@riverpod class AccountViewModel extends _\$AccountViewModel { '
          'EditorState build() => repository.state; }',
      rule: 'VM-03',
    ),
    (
      name: 'Synchronous generated Notifier cannot stand in for AsyncNotifier VM',
      path: _vm,
      source: '@riverpod class AccountViewModel extends _\$AccountViewModel { '
          'EditorState build() => EditorState(); '
          'void edit(String text) {} }',
      rule: 'VM-02',
    ),
    (
      name: 'VM cannot import Widget UI to perform dialogs itself',
      path: _vm,
      source: "import 'package:flutter/material.dart';",
      rule: 'VM-01',
    ),
    (
      name: 'Adapter cannot import a feature reducer or VM',
      path: _adapter,
      source: "import '../../features/settings/view_models/accounts.dart';",
      rule: 'ADAPTER-01',
    ),
    (
      name: 'Adapter cannot publish a parallel canonical mirror',
      path: _adapter,
      source: 'void convert(dynamic canonical) { canonical.publish(value); }',
      rule: 'ADAPTER-01',
    ),
    (
      name: 'Diagnostics cannot depend on feature-private owners',
      path: 'code/anywork/lib/src/diagnostics/fixture.dart',
      source: "import '../features/conversation/view_models/timeline.dart';",
      rule: 'DIAG-01',
    ),
    (
      name: 'A forwarding typedef cannot restore the old facade',
      path: _client,
      source: 'typedef StudioClient = AnyworkClient;',
      rule: 'OLD-01',
    ),
    (
      name: 'Old facade barrel cannot remain as a compatibility import',
      path: _vm,
      source: "import 'package:anywork_client/studio_client.dart';",
      rule: 'OLD-01',
    ),
    (
      name: 'A domain barrel cannot become the replacement giant bucket',
      path: 'code/anywork_client/lib/models.dart',
      source: "export 'src/configuration/domain/configuration_repository.dart';",
      rule: 'EXPORT-01',
    ),
    (
      name: 'Domain exports cannot leak their reducer or transport writer',
      path: 'code/anywork_client/lib/conversation.dart',
      source: "export 'src/conversation/data/thread_mirrors.dart';",
      rule: 'EXPORT-01',
    ),
    (
      name: 'Dot-segment exports cannot escape into another domain',
      path: 'code/anywork_client/lib/conversation.dart',
      source: "export 'src/conversation/domain/../../configuration/domain/configuration_state.dart';",
      rule: 'EXPORT-01',
    ),
    (
      name: 'Handwritten part cannot hide a forwarding library',
      path: _client,
      source: "part 'settings_commands.dart';",
      rule: 'OLD-02',
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
      name: 'The new Repository cannot become a module singleton either',
      path: _account,
      source: 'final repository = createWorkspaceRepository(port: port);',
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

  test('SDK and Freezed imports, instance owners and observation cancellation are allowed', () {
    expect(
      checkClientSource(
        path: _client,
        source: '''
import 'dart:async';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
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
import 'package:anywork_client/conversation.dart';
Object rowKey(String itemId) => new ValueKey(itemId);
''',
      ),
      isEmpty,
    );
  });

  test('typed callbacks, value state, generated VM and typed adapter are allowed', () {
    for (final fixture in <({String path, String source})>[
      (
        path: _feature,
        source: '''
import 'package:flutter/widgets.dart';
import '../../../app/theme/studio_tokens.dart';
class ConversationView {
  ConversationView({required this.title, required this.onSend});
  final String title;
  final void Function(String) onSend;
}
''',
      ),
      (
        path: _state,
        source: '''
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
part 'fixture.freezed.dart';
@freezed abstract class EditorState with _\$EditorState {
  const factory EditorState({required String text, StudioFailure? error}) = _EditorState;
}
''',
      ),
      (
        path: _vm,
        source: '''
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'fixture.g.dart';
@riverpod class AccountViewModel extends _\$AccountViewModel {
  FutureOr<EditorState> build() { return EditorState(text: ''); }
  void edit(String text) { state = AsyncData(EditorState(text: text)); }
}
''',
      ),
      (
        path: _adapter,
        source: '''
import 'package:anywork_client/configuration_ports.dart';
import '../../rust/api/studio/types/settings.dart';
ConfigurationValue convert(BridgeConfigurationValue value) => decode(value);
''',
      ),
      (
        path: 'code/anywork_client/lib/conversation.dart',
        source: "export 'src/conversation/domain/thread_identity.dart';",
      ),
      (
        path: 'code/anywork_client/lib/configuration_ports.dart',
        source: "export 'configuration.dart'; "
            "export 'src/configuration/data/configuration_frames.dart';",
      ),
      (
        path: 'code/anywork/lib/src/features/settings/modes/widgets/fixture.dart',
        source: '''
import 'package:vyuh_node_flow/vyuh_node_flow.dart' as graph;
class WorkflowCanvas {
  WorkflowCanvas(this.edge);
  final graph.Connection<Object?> edge;
}
''',
      ),
    ]) {
      expect(
        checkClientSource(path: fixture.path, source: fixture.source),
        isEmpty,
        reason: fixture.path,
      );
    }
  });

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
