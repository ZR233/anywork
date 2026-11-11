import 'dart:convert';

import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/composer_target_diagnostic.dart';

void main() {
  for (final (target, expected) in [
    (
      const ComposerTarget.thread(threadId: 'thread-a'),
      {'kind': 'thread', 'threadId': 'thread-a'},
    ),
    (
      const ComposerTarget.start(workspaceId: 'workspace-b'),
      {'kind': 'start', 'workspaceId': 'workspace-b'},
    ),
  ]) {
    test('snapshot JSON preserves the identity of $target', () {
      final snapshot = {
        'composers': [
          {'target': composerTargetDiagnostic(target)},
        ],
      };
      final encoded = jsonEncode(snapshot);
      expect(jsonDecode(encoded), {
        'composers': [
          {'target': expected},
        ],
      });
    });
  }

  test('unknown diagnostic targets do not impersonate a valid target', () {
    expect(composerTargetDiagnostic(Object()), isNull);
    expect(
      jsonEncode({'target': composerTargetDiagnostic(null)}),
      '{"target":null}',
    );
  });
}
