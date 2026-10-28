import 'dart:convert';

import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_account_editor_state.dart';
import 'package:anywork/src/features/settings/accounts/state/acp_account_target.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/views/acp_account_editor_view.dart';
import 'package:anywork/src/features/settings/accounts/widgets/acp_install_preparation_panel.dart';
import 'package:anywork/src/features/settings/state/settings_action.dart';
import 'package:anywork/src/features/settings/widgets/settings_form_field.dart';
import 'package:anywork/src/features/settings/widgets/settings_feedback.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/acp_port_fixture.dart';
import 'support/acp_settings_environment.dart';
import 'support/driver_environment.dart';
import 'support/pump_client_future.dart';

const _create = AcpAccountCreateTarget(
  accountId: 'antigravity',
  template: acpSettingsTemplate,
);
const _refusal = StudioFailure(
  code: StudioFailureCode.permissionDenied,
  message: 'The scripted native boundary refused this operation',
  retryable: false,
  correlationId: 'acp-install-original-action',
);

AcpAccountEditorViewState _state(
  AcpSettingsEnvironment env, [
  AcpAccountEditorTarget target = _create,
]) =>
    env.container.read(acpAccountEditorViewModelProvider(target)).requireValue;
AcpAccountEditorViewModel _vm(
  AcpSettingsEnvironment env, [
  AcpAccountEditorTarget target = _create,
]) => env.container.read(acpAccountEditorViewModelProvider(target).notifier);

Future<void> _publish(
  WidgetTester tester,
  AcpSettingsEnvironment env,
  ScriptedAcpInstallFeed feed,
  AcpInstallState state, {
  required int revision,
  required int base,
  AcpAccountEditorTarget target = _create,
}) async {
  await pumpClientFuture(
    tester,
    feed.publishChanged(
      acpInstallSnapshot(revision: revision, state: state),
      baseRevision: base,
    ),
    'original install change ACK $base->$revision',
  );
  await pumpClientUntil(
    tester,
    () => _state(env, target).install == state,
    'real editor observes install revision $revision',
  );
  await tester.pump();
  expect(
    tester
        .widget<AcpInstallPreparationPanel>(
          find.byKey(StudioDriverKeys.acpInstallPanel),
        )
        .state,
    state,
  );
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final control = find.byKey(key);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump();
}

void _expectRefusalRendered(WidgetTester tester) {
  final error = tester
      .widget<AcpAccountEditorView>(find.byType(AcpAccountEditorView))
      .error!;
  expect(error.split('\n').toSet(), {
    'The request was not accepted. Permission denied',
  });
  expect(
    find.descendant(
      of: find.byType(SettingsInlineError),
      matching: find.text(error),
    ),
    findsOneWidget,
  );
  expect(
    find.text(_refusal.message),
    findsNothing,
    reason: '命令原始message不是产品摘要',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实Driver保安装revision0与未知总量/速度/摘要，采集不新增需求或原生动作', (tester) async {
    final env = DriverTestEnvironment();
    addTearDown(
      () => pumpClientFuture(
        tester,
        env.close(),
        'Driver original application owners join',
      ),
    );
    await pumpClientFuture(
      tester,
      env.establish(threads: const []),
      'Driver real application graph',
    );
    final repository = env.application.graph.acpInstall;
    expect(env.capture().acpInstall, isNull);
    final synchronizing = repository.synchronize();
    final feed = await pumpClientFuture(
      tester,
      env.application.acpPort.installFeedOpened(0),
      'Driver original install feed',
    );
    await pumpClientFuture(
      tester,
      feed.publishBaseline(
        acpInstallSnapshot(
          revision: 0,
          state: AcpInstallState.downloading(
            operationId: 'op-9',
            release: acpRelease(),
            progress: const AcpInstallProgress(
              completedBytes: 2048,
              totalBytes: null,
              bytesPerSecond: null,
            ),
            retryCount: 1,
          ),
        ),
      ),
      'zero revision native baseline ACK',
    );
    await pumpClientFuture(
      tester,
      synchronizing,
      'install zero baseline materialized',
    );
    final observers = repository.state.observerCount;
    final budget = List.of(env.application.domains.budget.usage);
    final json = env.snapshotJson();
    final install =
        ((jsonDecode(json) as Map)['settings'] as Map)['acpInstall'] as Map;
    expect(install['loaded'], isTrue);
    expect(install['revision'], 0);
    final entry = (install['installations'] as List).single as Map;
    expect(
      (
        entry['phase'],
        entry['operationId'],
        entry['stage'],
        entry['retryCount'],
      ),
      ('downloading', 'op-9', 'download', 1),
    );
    expect(entry['progress'], {
      'completedBytes': 2048,
      'totalBytes': null,
      'bytesPerSecond': null,
    });
    expect(entry['release'], {
      'version': '1.4.1',
      'target': 'linux-x86_64',
      'archiveUrl': 'https://dl.google.com/agy-extensions/releases/linux/agy-acp-server-1.4.1-linux-x86_64.zip',
      'sha256': null,
    });
    expect(env.snapshotJson(), json);
    expect(repository.state.observerCount, observers);
    expect(env.application.domains.budget.usage, budget);
    expect(env.application.acpPort.installFeeds, hasLength(1));
    expect(env.application.acpPort.authFeeds, isEmpty);
    expect(env.application.acpPort.authReads, isEmpty);
    expect(env.application.acpPort.installReads, isEmpty);
    expect(env.application.acpPort.catalogReads, isEmpty);
    expect(env.application.acpPort.installStarts, isEmpty);
    expect(env.application.acpPort.installCancels, isEmpty);
  });

  testWidgets('真实创建/编辑表单保模板版本与准备资格，编辑只改名且不绑定共享安装', (tester) async {
    final account = acpSettingsAccount('edit-account', revision: 4);
    final env = await AcpSettingsEnvironment.open(tester, accounts: [account]);
    await env.mountEditor(tester, _create);
    await env.installBaseline(tester, const AcpInstallState.idle());
    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.acpInstallVersion)).data,
      'Version · 1.4.1',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(StudioDriverKeys.acpInstallPrepare))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(StudioDriverKeys.accountSave), findsNothing);
    expect(
      find.byType(SettingsFormField),
      findsOneWidget,
      reason: '不引入program/argv/API key配置控件',
    );
    await tester.enterText(
      find.byKey(StudioDriverKeys.acpAccountName),
      '  Work  ',
    );
    expect(
      _vm(env).toUpdate(),
      const AcpAccountUpdate(
        accountId: 'antigravity',
        name: 'Work',
        provider: AcpProvider.antigravity,
      ),
    );
    await tester.enterText(find.byKey(StudioDriverKeys.acpAccountName), '   ');
    expect(_vm(env).toUpdate().name, 'Antigravity');
    final unsupported = AcpAccountCreateTarget(
      accountId: 'unsupported',
      template: acpSettingsTemplate.copyWith(
        automaticInstall: const AcpInstallAvailability.unsupportedPlatform(),
      ),
    );
    await env.mountEditor(tester, unsupported);
    expect(_state(env, unsupported).canPrepareAutomatically, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.byKey(StudioDriverKeys.acpInstallPrepare))
          .onPressed,
      isNull,
    );
    await pumpClientFuture(
      tester,
      _vm(env, unsupported).prepare(),
      'unsupported preparation refused locally',
    );
    final edit = AcpAccountEditTarget(
      account: account,
      template: acpSettingsTemplate,
    );
    await env.mountEditor(tester, edit);
    expect(_state(env, edit).create, isFalse);
    expect(_state(env, edit).intent.operationId, isNull);
    expect(
      (edit.account.connectionRevision, _state(env, edit).accountId),
      (4, 'edit-account'),
    );
    expect(find.byKey(StudioDriverKeys.acpInstallPrepare), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(StudioDriverKeys.accountSave))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(
      find.byKey(StudioDriverKeys.acpAccountName),
      'Renamed',
    );
    expect(
      _vm(env, edit).toUpdate(),
      const AcpAccountUpdate(
        accountId: 'edit-account',
        name: 'Renamed',
        provider: AcpProvider.antigravity,
      ),
    );
    expect(edit.account.connectionRevision, 4);
    expect(env.acp.port.installStarts, isEmpty);
    expect(env.acp.port.authStarts, isEmpty);
    expect(env.settings.configurationPort.acpSaves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('start在途禁重复和显式claim；合法回执只认领自己，另一Ready仍须用户显式认领', (tester) async {
    final env = await AcpSettingsEnvironment.open(tester);
    await env.mountEditor(tester, _create);
    final feed = await env.installBaseline(
      tester,
      const AcpInstallState.idle(),
    );
    final preparing = _vm(env).prepare();
    final start = await pumpClientFuture(
      tester,
      env.acp.port.installStarted(0),
      'original start dispatched',
    );
    expect(_state(env).preparing, isTrue);
    await pumpClientFuture(
      tester,
      _vm(env).prepare(),
      'duplicate prepare refused by current VM',
    );
    expect(env.acp.port.installStarts, hasLength(1));
    final elsewhere = AcpInstallState.ready(
      operationId: 'other-ready',
      server: acpSettingsServer(),
    );
    await _publish(tester, env, feed, elsewhere, revision: 2, base: 1);
    expect(_state(env).availableElsewhere, acpSettingsServer());
    expect(_state(env).prepared, isNull);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(StudioDriverKeys.acpInstallUsePrepared),
          )
          .onPressed,
      isNull,
    );
    _vm(env).usePrepared();
    expect(_state(env).intent.operationId, isNull);
    final ownReady = AcpInstallState.ready(
      operationId: start.request.operationId.value,
      server: acpSettingsServer(),
    );
    await _publish(tester, env, feed, ownReady, revision: 3, base: 2);
    start.accept(
      AcpInstallCommandReply(
        receipt: acpInstallReceipt(start.request.operationId, revision: 3),
        snapshot: acpInstallSnapshot(revision: 3, state: ownReady),
      ),
    );
    await pumpClientFuture(
      tester,
      preparing,
      'original start settles and claims',
    );
    await tester.pump();
    expect(_state(env).preparing, isFalse);
    expect(_state(env).intent.operationId, start.request.operationId.value);
    expect(_state(env).prepared, acpSettingsServer());
    expect(
      tester
          .widget<FilledButton>(find.byKey(StudioDriverKeys.accountSave))
          .onPressed,
      isNotNull,
    );
    await _publish(tester, env, feed, elsewhere, revision: 4, base: 3);
    expect(_state(env).prepared, isNull);
    expect(_state(env).availableElsewhere, acpSettingsServer());
    expect(find.byKey(StudioDriverKeys.accountSave), findsNothing);
    await _tap(tester, StudioDriverKeys.acpInstallUsePrepared);
    expect(_state(env).intent.operationId, 'other-ready');
    expect(_state(env).prepared, acpSettingsServer());
    expect(env.acp.port.installStarts, hasLength(1));
    expect(env.settings.configurationPort.acpSaves, isEmpty);
    expect(env.acp.port.authStarts, isEmpty);
  });

  testWidgets('Unknown start不认领也不重发；canonical Ready不是本表单受理证据', (tester) async {
    final env = await AcpSettingsEnvironment.open(tester);
    await env.mountEditor(tester, _create);
    final feed = await env.installBaseline(
      tester,
      const AcpInstallState.idle(),
    );
    final preparing = _vm(env).prepare();
    final start = await pumpClientFuture(
      tester,
      env.acp.port.installStarted(0),
      'Unknown start dispatched',
    );
    env.expectedUnresolvedInstallOperations.add(start.request.operationId);
    start.fail(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Original native reply was lost',
        retryable: true,
        correlationId: 'acp-unknown-start',
      ),
    );
    await pumpClientFuture(tester, preparing, 'original Unknown outcome');
    expect(
      _state(env).prepareAction!.outcome,
      SettingsActionOutcome.unknownOutcome,
    );
    expect(_state(env).prepareAction!.operation!.receipt, isNull);
    expect(_state(env).intent.operationId, isNull);
    await _publish(
      tester,
      env,
      feed,
      AcpInstallState.ready(
        operationId: start.request.operationId.value,
        server: acpSettingsServer(),
      ),
      revision: 2,
      base: 1,
    );
    await _tap(tester, StudioDriverKeys.acpInstallUsePrepared);
    await pumpClientFuture(
      tester,
      _vm(env).prepare(),
      'Unknown original start is protected',
    );
    expect(_state(env).intent.operationId, isNull);
    expect(_state(env).prepared, isNull);
    expect(find.byKey(StudioDriverKeys.accountSave), findsNothing);
    expect(env.acp.port.installStarts, hasLength(1));
  });

  for (final lateSuccess in [false, true]) {
    testWidgets(
      '同表单A取消未回时B可取消；晚A${lateSuccess ? '成功' : '拒绝'}不结算B，只有实际Cancelled帧才是终态',
      (tester) async {
        final env = await AcpSettingsEnvironment.open(tester);
        await env.mountEditor(tester, _create);
        final initial = const AcpInstallState.resolving(
          operationId: 'install-A',
        );
        final feed = await env.installBaseline(tester, initial);
        final vm = _vm(env);
        final oldCancel = vm.cancelPrepare();
        final a = await pumpClientFuture(
          tester,
          env.acp.port.installCancelled(0),
          'cancel A native request',
        );
        expect(a.request.provider, AcpProvider.antigravity);
        expect(a.request.targetOperationId, const OperationId('install-A'));
        expect(a.request.operationId, isNot(a.request.targetOperationId));
        await pumpClientFuture(
          tester,
          vm.cancelPrepare(),
          'duplicate A cancel',
        );
        expect(env.acp.port.installCancels, hasLength(1));
        await _publish(
          tester,
          env,
          feed,
          const AcpInstallState.resolving(operationId: 'install-B'),
          revision: 2,
          base: 1,
        );
        expect(a.reply.isCompleted, isFalse, reason: 'B资格必须在A仍hold时证明');
        expect(_state(env).cancelPending, isFalse);
        expect(_state(env).currentCancelAction, isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(StudioDriverKeys.acpInstallCancel),
              )
              .onPressed,
          isNotNull,
        );
        await tester.enterText(
          find.byKey(StudioDriverKeys.acpAccountName),
          'B draft kept',
        );
        final newCancel = vm.cancelPrepare();
        final b = await pumpClientFuture(
          tester,
          env.acp.port.installCancelled(1),
          'cancel B native request while A held',
        );
        expect(b.request.provider, AcpProvider.antigravity);
        expect(
          env.acp.port.installCancels.map(
            (call) => call.request.targetOperationId.value,
          ),
          ['install-A', 'install-B'],
        );
        expect(b.request.operationId, isNot(b.request.targetOperationId));
        expect(b.request.operationId, isNot(a.request.operationId));
        final bIntent = _state(env).cancelAction!.intent;
        final preparationIntent = _state(env).intent;
        expect(_state(env).cancelTargetOperationId, 'install-B');
        expect(_state(env).cancelAction!.operation!.id, b.request.operationId);
        await pumpClientFuture(
          tester,
          vm.cancelPrepare(),
          'duplicate B cancel',
        );
        expect(env.acp.port.installCancels, hasLength(2));
        if (lateSuccess) {
          a.accept(
            AcpInstallCommandReply(
              receipt: acpInstallReceipt(a.request.operationId, revision: 1),
              snapshot: acpInstallSnapshot(revision: 1, state: initial),
            ),
          );
        } else {
          a.reject(const CommandDispatchFailure.rejected(failure: _refusal));
        }
        await pumpClientFuture(
          tester,
          oldCancel,
          'old A owner settles independently',
        );
        await tester.pump();
        expect(_state(env).cancelAction!.intent, bIntent);
        expect(_state(env).cancelPending, isTrue);
        expect(_state(env).currentCancelAction!.error, isNull);
        expect(_state(env).name, 'B draft kept');
        expect(_state(env).intent, preparationIntent);
        expect(
          _state(env).install,
          const AcpInstallState.resolving(operationId: 'install-B'),
        );
        expect(env.acp.install.state.value.canonical!.revision, 2);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(StudioDriverKeys.acpInstallCancel),
              )
              .onPressed,
          isNull,
        );
        expect(find.text(_refusal.message), findsNothing);
        expect(find.byType(SettingsInlineError), findsNothing);
        b.accept(
          AcpInstallCommandReply(
            receipt: acpInstallReceipt(b.request.operationId, revision: 2),
            snapshot: acpInstallSnapshot(
              revision: 2,
              state: const AcpInstallState.resolving(operationId: 'install-B'),
            ),
          ),
        );
        await pumpClientFuture(
          tester,
          newCancel,
          'B reply settles only B action',
        );
        await tester.pump();
        expect(_state(env).cancelAction!.intent, bIntent);
        expect(
          _state(env).cancelAction!.outcome,
          SettingsActionOutcome.succeeded,
        );
        expect(_state(env).cancelPending, isFalse);
        expect(_state(env).install, isNot(isA<AcpInstallCancelled>()));
        expect(
          find.descendant(
            of: find.byKey(StudioDriverKeys.acpInstallPanel),
            matching: find.text('Cancelled.'),
          ),
          findsNothing,
        );
        await _publish(
          tester,
          env,
          feed,
          const AcpInstallState.cancelled(operationId: 'install-B'),
          revision: 3,
          base: 2,
        );
        expect(
          find.descendant(
            of: find.byKey(StudioDriverKeys.acpInstallPanel),
            matching: find.text('Cancelled.'),
          ),
          findsOneWidget,
        );
        expect(_state(env).name, 'B draft kept');
        expect(env.acp.port.installCancels, hasLength(2));
        await env.close(tester);
      },
    );
  }

  testWidgets('prepare与cancel按各自action结算：后发取消不丢原合法start认领或中途名称', (
    tester,
  ) async {
    final env = await AcpSettingsEnvironment.open(tester);
    await env.mountEditor(tester, _create);
    final feed = await env.installBaseline(
      tester,
      const AcpInstallState.idle(),
    );
    final vm = _vm(env);
    final preparing = vm.prepare();
    final start = await pumpClientFuture(
      tester,
      env.acp.port.installStarted(0),
      'prepare A native request held',
    );
    expect(start.request.provider, AcpProvider.antigravity);
    final generation = _state(env).intent.generation;
    final prepareIntent = _state(env).prepareAction!.intent;
    final resolving = AcpInstallState.resolving(
      operationId: start.request.operationId.value,
    );
    await _publish(tester, env, feed, resolving, revision: 2, base: 1);
    final cancelling = vm.cancelPrepare();
    final cancel = await pumpClientFuture(
      tester,
      env.acp.port.installCancelled(0),
      'cancel A overlaps original prepare',
    );
    expect(start.reply.isCompleted, isFalse);
    expect(cancel.request.targetOperationId, start.request.operationId);
    expect(cancel.request.operationId, isNot(start.request.operationId));
    final cancelIntent = _state(env).cancelAction!.intent;
    await tester.enterText(
      find.byKey(StudioDriverKeys.acpAccountName),
      'Name edited during both calls',
    );
    start.accept(
      AcpInstallCommandReply(
        receipt: acpInstallReceipt(start.request.operationId, revision: 2),
        snapshot: acpInstallSnapshot(revision: 2, state: resolving),
      ),
    );
    await pumpClientFuture(
      tester,
      preparing,
      'original legal start reply survives later cancel',
    );
    await tester.pump();
    expect(_state(env).prepareAction!.intent, prepareIntent);
    expect(_state(env).prepareAction!.pending, isFalse);
    expect(_state(env).prepareAction!.outcome, SettingsActionOutcome.succeeded);
    expect(_state(env).intent.generation, generation);
    expect(_state(env).intent.operationId, start.request.operationId.value);
    expect(_state(env).cancelAction!.intent, cancelIntent);
    expect(_state(env).cancelPending, isTrue);
    expect(cancel.reply.isCompleted, isFalse);
    expect(_state(env).name, 'Name edited during both calls');
    expect(
      tester
          .widget<SettingsFormField>(
            find.byKey(StudioDriverKeys.acpAccountName),
          )
          .value,
      'Name edited during both calls',
    );
    expect(_state(env).prepared, isNull);
    cancel.accept(
      AcpInstallCommandReply(
        receipt: acpInstallReceipt(cancel.request.operationId, revision: 2),
        snapshot: acpInstallSnapshot(revision: 2, state: resolving),
      ),
    );
    await pumpClientFuture(tester, cancelling, 'original cancel action reply');
    expect(_state(env).install, resolving);
    await _publish(
      tester,
      env,
      feed,
      AcpInstallState.cancelled(operationId: start.request.operationId.value),
      revision: 3,
      base: 2,
    );
    expect(env.acp.port.installStarts, hasLength(1));
    expect(env.acp.port.installCancels, hasLength(1));
  });

  for (final success in [false, true]) {
    testWidgets('同账号重开表单后旧start${success ? '成功' : '失败'}不认领、不写新错误；当前尝试仍能结算', (
      tester,
    ) async {
      final env = await AcpSettingsEnvironment.open(tester);
      await env.mountEditor(tester, _create);
      final feed = await env.installBaseline(
        tester,
        const AcpInstallState.idle(),
      );
      final oldVm = _vm(env);
      final oldPrepare = oldVm.prepare();
      final old = await pumpClientFuture(
        tester,
        env.acp.port.installStarted(0),
        'old form start reached native',
      );
      await env.unmount(tester);
      expect(
        env.container.exists(acpAccountEditorViewModelProvider(_create)),
        isFalse,
      );
      await env.mountEditor(tester, _create);
      final freshGeneration = _state(env).intent.generation;
      expect(_vm(env), isNot(same(oldVm)), reason: '真实dispose后的新表单有独立VM存活代次');
      await tester.enterText(
        find.byKey(StudioDriverKeys.acpAccountName),
        'Fresh form name',
      );
      if (success) {
        final oldReady = AcpInstallState.ready(
          operationId: old.request.operationId.value,
          server: acpSettingsServer(),
        );
        await _publish(tester, env, feed, oldReady, revision: 2, base: 1);
        old.accept(
          AcpInstallCommandReply(
            receipt: acpInstallReceipt(old.request.operationId, revision: 2),
            snapshot: acpInstallSnapshot(revision: 2, state: oldReady),
          ),
        );
      } else {
        old.reject(const CommandDispatchFailure.rejected(failure: _refusal));
      }
      await pumpClientFuture(
        tester,
        oldPrepare,
        'disposed original start continuation finishes',
      );
      await tester.pump();
      expect(_state(env).intent.generation, freshGeneration);
      expect(_state(env).intent.operationId, isNull);
      expect(_state(env).prepareAction, isNull);
      expect(_state(env).name, 'Fresh form name');
      expect(find.text(_refusal.message), findsNothing);
      expect(find.byType(SettingsInlineError), findsNothing);
      if (success) {
        expect(_state(env).prepared, isNull);
        expect(_state(env).availableElsewhere, acpSettingsServer());
        await _tap(tester, StudioDriverKeys.acpInstallUsePrepared);
        expect(_state(env).prepared, acpSettingsServer());
      } else {
        final current = _vm(env).prepare();
        final next = await pumpClientFuture(
          tester,
          env.acp.port.installStarted(1),
          'fresh form own start',
        );
        expect(_state(env).preparing, isTrue);
        next.reject(const CommandDispatchFailure.rejected(failure: _refusal));
        await pumpClientFuture(tester, current, 'current failure is presented');
        await tester.pump();
        expect(_state(env).prepareAction!.error, _refusal);
        _expectRefusalRendered(tester);
        expect(_state(env).name, 'Fresh form name');
      }
    });
  }

  testWidgets('旧表单取消A仍在途时新表单可取消B，旧失败不清新pending或名称', (tester) async {
    final env = await AcpSettingsEnvironment.open(tester);
    await env.mountEditor(tester, _create);
    final feed = await env.installBaseline(
      tester,
      const AcpInstallState.resolving(operationId: 'form-A'),
    );
    final oldVm = _vm(env);
    final oldCancel = oldVm.cancelPrepare();
    final a = await pumpClientFuture(
      tester,
      env.acp.port.installCancelled(0),
      'old form cancel A held',
    );
    await env.unmount(tester);
    expect(
      env.container.exists(acpAccountEditorViewModelProvider(_create)),
      isFalse,
    );
    await env.mountEditor(tester, _create);
    expect(_vm(env), isNot(same(oldVm)));
    await _publish(
      tester,
      env,
      feed,
      const AcpInstallState.resolving(operationId: 'form-B'),
      revision: 2,
      base: 1,
    );
    await tester.enterText(
      find.byKey(StudioDriverKeys.acpAccountName),
      'New form B',
    );
    final currentCancel = _vm(env).cancelPrepare();
    final b = await pumpClientFuture(
      tester,
      env.acp.port.installCancelled(1),
      'new form cancel B before A replies',
    );
    a.reject(const CommandDispatchFailure.rejected(failure: _refusal));
    await pumpClientFuture(
      tester,
      oldCancel,
      'old form late failure observed only by old continuation',
    );
    await tester.pump();
    expect(_state(env).cancelPending, isTrue);
    expect(_state(env).cancelAction!.operation!.id, b.request.operationId);
    expect(_state(env).currentCancelAction!.error, isNull);
    expect(_state(env).name, 'New form B');
    expect(find.text(_refusal.message), findsNothing);
    expect(find.byType(SettingsInlineError), findsNothing);
    b.reject(const CommandDispatchFailure.rejected(failure: _refusal));
    await pumpClientFuture(
      tester,
      currentCancel,
      'current B failure remains visible',
    );
    await tester.pump();
    expect(_state(env).cancelPending, isFalse);
    expect(_state(env).currentCancelAction!.error, _refusal);
    _expectRefusalRendered(tester);
    expect(_state(env).name, 'New form B');
    expect(
      env.acp.port.installCancels.map(
        (call) => call.request.targetOperationId.value,
      ),
      ['form-A', 'form-B'],
    );
  });

  testWidgets('取消预算耗尽不残留B准入，A真实结算释放容量后同一B可再次到native', (tester) async {
    final budget = ResourceBudget(
      capacities: const {
        ResourceKind.chatHandle: 2,
        ResourceKind.pendingOperation: 1,
        ResourceKind.draft: 64,
        ResourceKind.attachment: 256,
        ResourceKind.observer: 1024,
        ResourceKind.readModel: 256,
      },
    );
    final env = await AcpSettingsEnvironment.open(tester, acpBudget: budget);
    await env.mountEditor(tester, _create);
    final feed = await env.installBaseline(
      tester,
      const AcpInstallState.resolving(operationId: 'budget-A'),
    );
    final first = _vm(env).cancelPrepare();
    final a = await pumpClientFuture(
      tester,
      env.acp.port.installCancelled(0),
      'budget A holds real mutation permit',
    );
    await _publish(
      tester,
      env,
      feed,
      const AcpInstallState.resolving(operationId: 'budget-B'),
      revision: 2,
      base: 1,
    );
    await pumpClientFuture(
      tester,
      _vm(env).cancelPrepare(),
      'budget rejects B before native',
    );
    expect(
      _state(env).currentCancelAction!.error!.code,
      StudioFailureCode.overloaded,
    );
    expect(
      _state(env).currentCancelAction!.error!.details,
      const StudioFailureDetails.resourceLimit(
        resource: 'pendingOperation',
        capacity: 1,
      ),
    );
    expect(_state(env).cancelPending, isFalse);
    expect(env.acp.port.installCancels, hasLength(1));
    a.reject(const CommandDispatchFailure.rejected(failure: _refusal));
    await pumpClientFuture(tester, first, 'A real action releases its permit');
    final retried = _vm(env).cancelPrepare();
    final b = await pumpClientFuture(
      tester,
      env.acp.port.installCancelled(1),
      'same B retry actually reaches native',
    );
    expect(b.request.targetOperationId, const OperationId('budget-B'));
    b.accept(
      AcpInstallCommandReply(
        receipt: acpInstallReceipt(b.request.operationId, revision: 2),
        snapshot: acpInstallSnapshot(
          revision: 2,
          state: const AcpInstallState.resolving(operationId: 'budget-B'),
        ),
      ),
    );
    await pumpClientFuture(tester, retried, 'B retry settles');
    expect(
      _state(env).currentCancelAction!.outcome,
      SettingsActionOutcome.succeeded,
    );
    expect(env.acp.port.installCancels, hasLength(2));
  });

  test('关闭逐项join两个不同目标的原取消，先结算B也不能丢仍hold的A', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.install;
    addTearDown(() async {
      for (final call in fixture.port.installCancels) {
        if (!call.reply.isCompleted) {
          call.reject(const CommandDispatchFailure.rejected(failure: _refusal));
        }
      }
      expect((await repository.close()).complete, isTrue);
      expect((await fixture.auth.close()).complete, isTrue);
      expect(fixture.budget.usage, isEmpty);
      fixture.operations.seal();
    });
    final feed = await establishAcpInstall(
      fixture,
      state: const AcpInstallState.resolving(operationId: 'join-A'),
    );
    final a = repository.cancel(
      AcpProvider.antigravity,
      targetOperationId: 'join-A',
    );
    final aCall = await fixture.port.installCancelled(0);
    await feed.publishChanged(
      acpInstallSnapshot(
        revision: 2,
        state: const AcpInstallState.resolving(operationId: 'join-B'),
      ),
      baseRevision: 1,
    );
    final b = repository.cancel(
      AcpProvider.antigravity,
      targetOperationId: 'join-B',
    );
    final bCall = await fixture.port.installCancelled(1);
    expect((aCall.reply.isCompleted, bCall.reply.isCompleted), (false, false));
    // 这是公开close的有界观察契约，不用零延迟猜命令是否已到达：上面已等两个真实native请求。
    final pending = await repository.close(deadline: DateTime.now());
    await feed.feed.closeStarted.future;
    expect(pending.complete, isFalse);
    expect(
      pending.unresolved
          .where((owner) => owner.owner.startsWith('acp:action:'))
          .map((owner) => owner.owner)
          .toSet(),
      {'acp:action:${a.id.value}', 'acp:action:${b.id.value}'},
    );
    bCall.reject(const CommandDispatchFailure.rejected(failure: _refusal));
    expect(await b.result, isA<RejectedCommandResult<AcpInstallSnapshot>>());
    final stillA = await repository.retryCleanup(deadline: DateTime.now());
    expect(stillA.complete, isFalse);
    expect(
      stillA.unresolved
          .where((owner) => owner.owner.startsWith('acp:action:'))
          .map((owner) => owner.owner)
          .toSet(),
      {'acp:action:${a.id.value}'},
    );
    aCall.reject(const CommandDispatchFailure.rejected(failure: _refusal));
    expect(await a.result, isA<RejectedCommandResult<AcpInstallSnapshot>>());
    expect(
      (await repository.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 1)),
      )).complete,
      isTrue,
    );
    expect((await fixture.auth.close()).complete, isTrue);
    expect(fixture.port.installCancels, hasLength(2));
    expect(fixture.budget.usage, isEmpty);
    fixture.operations.seal();
  });
}
