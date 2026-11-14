import 'dart:convert';

import 'package:anywork_client/acp_sessions.dart';
import 'package:crypto/crypto.dart';

// Borrow the real Client's synchronous publication, never infer a submission
// from a later protocol echo. This observer owns no session or business state.
final class AgySubmissionEvidence {
  AgySubmissionEvidence({
    required this.expectedPrompt,
    required AcpConversationState before,
  }) : startIndex = before.content.length {
    if (before.sendPending || before.activeRun != null) {
      throw StateError('Submission observer must be armed before an idle send');
    }
  }

  final String expectedPrompt;
  final int startIndex;
  bool _wasPending = false;
  int _submissions = 0;
  AcpConversationMessageItem? _submitted;
  List<AcpConversationMessageItem> _formalUsers = const [];

  void observe(AcpConversationState state) {
    final startsSend = state.sendPending && !_wasPending;
    _wasPending = state.sendPending;
    if (startsSend) {
      _submissions++;
      if (_submissions != 1) {
        throw StateError('Multiple Client submissions in one phase');
      }
      if (state.content.length != startIndex + 1 ||
          state.content.last is! AcpConversationMessageItem ||
          (state.content.last as AcpConversationMessageItem).kind !=
              AcpConversationMessageKind.user) {
        throw StateError('Missing first new provisional Client user item');
      }
      _submitted = state.content.last as AcpConversationMessageItem;
      verify();
    }
    if (_submissions == 1 && _submitted != null) {
      _formalUsers = List.unmodifiable(
        state.content
            .skip(startIndex)
            .whereType<AcpConversationMessageItem>()
            .where(
              (item) =>
                  item.kind == AcpConversationMessageKind.user &&
                  !identical(item, _submitted),
            ),
      );
    }
  }

  void verify() {
    final submitted = _submitted;
    if (_submissions != 1 || submitted == null) {
      throw StateError('Expected exactly one observed Client submission');
    }
    if (submitted.chunks.any((chunk) => chunk.content is! AcpTextContentView) ||
        _text(submitted) != expectedPrompt) {
      throw StateError('Client submitted prompt differs; body not logged');
    }
  }

  Map<String, Object?> diagnostics() {
    final submitted = _submitted;
    final formalUsers = _formalUsers;
    return {
      'startIndex': startIndex,
      'submissionCount': _submissions,
      'observedSubmission': _submitted != null,
      if (submitted != null) 'submitted': _message(submitted, expectedPrompt),
      'formalUserMessages': [
        for (final item in formalUsers) _message(item, expectedPrompt),
      ],
    };
  }
}

String _text(AcpConversationMessageItem item) => item.chunks
    .map((chunk) => chunk.content)
    .whereType<AcpTextContentView>()
    .map((block) => block.text)
    .join();

Map<String, Object?> _message(
  AcpConversationMessageItem item,
  String expected,
) {
  final text = _text(item);
  var difference = 0;
  while (difference < text.length &&
      difference < expected.length &&
      text.codeUnitAt(difference) == expected.codeUnitAt(difference)) {
    difference++;
  }
  return {
    'text': _summary(text),
    'equalsExpectedText': text == expected,
    'firstDifferenceUtf16': text == expected ? null : difference,
    'chunks': [
      for (final chunk in item.chunks)
        {
          'type': chunk.content.runtimeType.toString(),
          'payload': _summary(switch (chunk.content) {
            AcpTextContentView(:final text) => text,
            AcpImageContentView(:final data) => data,
            AcpAudioContentView(:final data) => data,
            AcpResourceLinkView(:final uri) => uri,
            AcpEmbeddedResourceView(:final resource) => switch (resource) {
              AcpTextResourceContentsView(:final text) => text,
              AcpBlobResourceContentsView(:final blob) => blob,
            },
          }),
        },
    ],
  };
}

Map<String, Object?> _summary(String text) => {
  'utf16Length': text.length,
  'utf8Bytes': utf8.encode(text).length,
  'sha256': sha256.convert(utf8.encode(text)).toString(),
};
