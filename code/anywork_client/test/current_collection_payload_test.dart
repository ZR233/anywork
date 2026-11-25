import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart'
    show
        StudioModelRecoveryNotice,
        StudioModelRecoveryPhase,
        StudioProviderRecovery;
import 'package:test/test.dart';

void main() {
  test('Current atom collection payload keeps typed body references', () {
    final payload = InlineCurrentPayload(
      bytes: utf8.encode(
        jsonEncode({
          'id': 'atom-1',
          'source': {'kind': 'foregroundTurn', 'turnId': 'turn-1'},
          'sourceOrder': 3,
          'kind': 'text',
          'delivery': 'foreground',
          'lifecycle': {
            'kind': 'active',
            'started': {'effectSeq': 4, 'suborder': 1},
            'status': 'running',
          },
          'turnId': 'turn-1',
          'attemptId': 'attempt-1',
          'textChannel': 'final',
          'contentPresent': true,
          'contents': [
            {
              'role': 'body',
              'reference': {
                'ownerId': 'owner-1',
                'domain': 'entity',
                'entityId': 'atom-1',
                'contentKey': 'body',
                'generation': '9',
              },
            },
          ],
        }),
      ),
    );

    final atom = decodeCurrentAtomPayload(payload);
    expect(atom.id, 'atom-1');
    expect(atom.source, const ForegroundTurnChatSource(turnId: 'turn-1'));
    expect(atom.lifecycle, isA<ActiveChatAtom>());
    expect(atom.modelRecovery, isNull);
    expect(atom.contents.single.role, ChatContentRole.body);
    expect(atom.contents.single.reference.ownerId, 'owner-1');
    expect(atom.contents.single.reference.generation, '9');
  });

  test('paged Current keeps structured recovery and scheduled wait', () {
    final atom = decodeCurrentAtomPayload(
      InlineCurrentPayload(
        bytes: utf8.encode(
          jsonEncode({
            'id': 'recovery-notice',
            'source': {'kind': 'foregroundTurn', 'turnId': 'turn-1'},
            'kind': 'text',
            'delivery': 'foreground',
            'lifecycle': {'kind': 'active', 'status': 'waiting'},
            'textChannel': 'commentary',
            'modelRecovery': {
              'failureKind': 'rateLimit',
              'reason': 'none',
              'retryCount': 1,
              'maxRetries': 2,
              'effectiveWaitMillis': '45000',
              'phase': 'waiting',
            },
            'contents': const <Object?>[],
          }),
        ),
      ),
    );

    expect(
      atom.modelRecovery,
      StudioModelRecoveryNotice(
        phase: StudioModelRecoveryPhase.waiting,
        retryCount: 1,
        maxRetries: 2,
        failureKind: 'rateLimit',
        reason: StudioProviderRecovery.none,
        effectiveWaitMillis: BigInt.from(45000),
      ),
    );
  });

  test('deferred Current collection payload requires an owned body read', () {
    const reference = CurrentContentRef(
      ownerId: 'owner-1',
      domain: 'collection:atoms',
      entityId: 'atom-1',
      contentKey: 'entry',
      generation: '9',
    );
    expect(
      () => decodeCurrentAtomPayload(
        const DeferredCurrentPayload(reference: reference, byteLength: 4096),
      ),
      throwsFormatException,
    );
  });

  test('Current product JSON preserves unknown waits without reading legacy numbers', () {
    const active = {'phase': 'waiting', 'retryCount': 1, 'maxRetries': 2};
    expect(
      StudioModelRecoveryNotice.fromJson(active)?.effectiveWaitMillis,
      isNull,
    );
    expect(
      StudioModelRecoveryNotice.fromJson({
        ...active,
        'effectiveWaitMillis': 45000,
      })?.effectiveWaitMillis,
      isNull,
    );
  });
}
