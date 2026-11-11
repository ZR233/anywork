import 'dart:async';

import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart'
    show StudioFailure, StudioFailureCode;
import 'package:flutter_test/flutter_test.dart';

import 'accounts_view_models_test.dart';

const _key = AccountEditorKey(
  editorId: 'generic-editor',
  target: AccountDisplayKey(kind: AccountKind.acp, id: 'generic'),
  creating: true,
  template: AccountTemplateKey(kind: AccountKind.acp, id: 'command'),
);

void main() {
  test('refresh rejected as busy retains cancellation for the earlier unknown probe', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    h.acp.detect = (_) => Future.error(StateError('start reply lost'));
    final owner = await h.editor(_key);
    await Future<void>(() {});
    final original = h.acp.detectionStarts.single;
    h.acp.detect = (_) => Future.error(
      const StudioFailure(
        code: StudioFailureCode.busy,
        message: 'Previous probe is still active',
        retryable: false,
        correlationId: 'probe',
      ),
    );
    await owner.refreshLocalDetection();
    expect(h.acp.detectionStarts, hasLength(2));
    expect(h.acp.detectionStarts.last, isNot(original));
    owner.finish();
    await Future<void>(() {});
    expect(h.acp.detectionCancels, [original]);
  });

  test('source switches retain one program/argv/env draft and only managed requires preparation', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await h.editor(_key);
    owner.changeName('My ACP');
    owner.changeAcpSource(AcpAccountSource.command);
    owner.changeAcpCommand('/tools/agent');
    owner.changeAcpArgs(['--label', 'two words', '']);
    owner.changeAcpEnvironment([
      const AcpEnvironmentEntry(key: 'WORK', value: 'tree one'),
    ]);
    owner.changeAcpSource(AcpAccountSource.managed);
    expect(h.editorState(_key).canSave, isFalse);
    expect(h.acp.starts, isEmpty);
    owner.changeAcpSource(AcpAccountSource.local);
    final local = h.editorState(_key);
    expect(local.canSave, isTrue);
    expect(local.acp!.name.raw, 'My ACP');
    expect(local.acp!.command, '/tools/agent');
    expect(local.acp!.args, ['--label', 'two words', '']);
    expect(local.acp!.environment.single.value, 'tree one');
    owner.changeAcpSource(AcpAccountSource.command);
    expect(h.editorState(_key).canSave, isTrue);
    expect(h.editorState(_key).acp!.args, ['--label', 'two words', '']);
    owner.finish();
  });

  test('entry starts once, explicit refresh has a new identity, late detection cannot fill a changed draft', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final owner = await h.editor(_key);
    await Future<void>(() {});
    expect(h.acp.detectionStarts, hasLength(1));
    owner.presentation();
    owner.presentation();
    expect(h.acp.detectionStarts, hasLength(1));
    final first = h.acp.detectionStarts.single;
    owner.changeAcpSource(AcpAccountSource.command);
    owner.changeAcpCommand('custom-agent');
    h.acp.localDetection.publish(
      AccountResource(
        stamp: vmStamp,
        value: AcpLocalDetectionSnapshotView(
          revision: 2,
          operationId: first.value,
          state: AcpLocalDetectionPhaseView.available,
          program: '/old/agy',
          version: '1.2',
        ),
      ),
    );
    expect(h.editorState(_key).acp!.command, 'custom-agent');
    expect(h.editorState(_key).acp!.detectedProgram, isNull);
    owner.changeAcpSource(AcpAccountSource.local);
    await owner.refreshLocalDetection();
    final second = h.acp.detectionStarts.last;
    expect(second, isNot(first));
    h.acp.localDetection.publish(
      AccountResource(
        stamp: vmStamp,
        value: AcpLocalDetectionSnapshotView(
          revision: 3,
          operationId: first.value,
          state: AcpLocalDetectionPhaseView.available,
          program: '/late/agy',
          version: '1.2',
        ),
      ),
    );
    expect(h.editorState(_key).acp!.detectedProgram, isNull);
    owner.finish();
    await Future<void>(() {});
    expect(h.acp.detectionCancels, [second]);
  });

  test('leaving during start waits for that request then cancels its exact operation', () async {
    final h = AccountsVmHarness();
    addTearDown(h.dispose);
    final start = Completer<AcpLocalDetectionCommandReply>();
    h.acp.detect = (_) => start.future;
    final owner = await h.editor(_key);
    await Future<void>(() {});
    final operation = h.acp.detectionStarts.single;
    owner.finish();
    expect(h.acp.detectionCancels, isEmpty);
    start.complete(
      h.acp.detectionReply(operation, AcpLocalDetectionPhaseView.checking),
    );
    await Future<void>(() {});
    expect(h.acp.detectionCancels, [operation]);
    expect(h.acp.detectionStarts, [operation]);
  });
}
