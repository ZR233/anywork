import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';

Map<String, String>? composerTargetDiagnostic(Object? target) =>
    switch (target) {
      ThreadComposerTarget(:final threadId) => {
        'kind': 'thread',
        'threadId': threadId,
      },
      StartComposerTarget(:final workspaceId) => {
        'kind': 'start',
        'workspaceId': workspaceId,
      },
      _ => null,
    };
