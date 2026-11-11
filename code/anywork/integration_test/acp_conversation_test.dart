import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_conversation_view_model.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../anywork_client/test/support/acp_business_port.dart';
import '../test/ui/acp_components_support.dart';
import 'support/presentation_capture.dart';

// Native Flutter + production Client acceptance, not Rust/FRB/provider protocol
// acceptance. The shared controlled port supplies only official external frames.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'native ACP configuration, draft, permissions and background owner lifecycle',
    (tester) async {
      AcpSessionConfigOptionView select({
        required bool grouped,
        bool changed = false,
      }) {
        final values = [
          AcpSelectOptionView(
            value: AcpConfigValueId(grouped ? 'group/raw:1' : 'flat/raw:1'),
            name: grouped ? '标准深度' : '标准质量',
          ),
          AcpSelectOptionView(
            value: AcpConfigValueId(grouped ? 'group/raw:2' : 'flat/raw:2'),
            name: grouped ? '深入分析' : '请求高质量',
          ),
        ];
        return AcpSessionConfigOptionView(
          id: AcpConfigId(grouped ? 'vendor/grouped' : 'vendor/select'),
          name: grouped ? '分析深度' : '回答质量',
          kind: AcpSelectConfigView(
            currentValue: values[changed ? 1 : 0].value,
            options: grouped
                ? AcpGroupedOptionsView([
                    AcpSelectGroupView(
                      group: const AcpConfigGroupId('server/group'),
                      name: '服务端分组',
                      options: values,
                    ),
                  ])
                : AcpUngroupedOptionsView(values),
          ),
        );
      }

      List<AcpSessionConfigOptionView> options({bool groupedChanged = false}) =>
          [
            select(grouped: false),
            select(grouped: true, changed: groupedChanged),
            acpBooleanFixture,
          ];

      final harness = await AcpComponentHarness.create(options: options());
      final run = AcpRunIdView(
        instance: BigInt.from(19),
        sequence: BigInt.from(7),
      );
      harness.port.run = run;
      final gates = <Completer<void>>[];
      ControlledAcpObservation? otherSource;
      addTearDown(() async {
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }
        final admission = harness.port.promptResult;
        if (admission != null && !admission.isCompleted) {
          admission.complete(run);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.close(tester);
        expect(harness.source.closeSignals, greaterThanOrEqualTo(1));
        expect(harness.source.closes, 1);
        if (otherSource case final source?) {
          expect(source.closeSignals, greaterThanOrEqualTo(1));
          expect(source.closes, 1);
        }
        expect(tester.takeException(), isNull);
        // This is the real Client close report, not a synthetic port close ACK.
        debugPrint(
          'ACP native cleanup: Client complete; observations closed; '
          'Flutter production widgets unmounted',
        );
      });

      // The fixture owns only layout. Both visible sections, their providers,
      // subscriptions, commands and draft are the production implementations.
      Future<void> showPage(String threadId) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: presentationCaptureKey,
            child: harness.scope(
              Column(
                key: ValueKey(threadId),
                children: [
                  Expanded(child: AcpConversationContent(threadId: threadId)),
                  AcpConversationComposer(threadId: threadId, compact: true),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await showPage('thread');
      final geometry = await configurePresentationWindow(
        tester,
        logicalWidth: 1280,
        logicalHeight: 900,
        requireNativeResize: true,
      );
      debugPrint('ACP native viewport: ${jsonEncode(geometry)}');
      tester.testTextInput.register();
      await tester.enterText(find.byType(TextField), '原生 ACP 消息');
      await tester.pumpAndSettle();
      final draft = harness.client.drafts.composer('thread');
      expect(draft.state.draft, '原生 ACP 消息');

      Finder dropdown(bool grouped) =>
          find.byType(DropdownButton<AcpConfigValueId>).at(grouped ? 1 : 0);
      FilledButton sendButton() =>
          tester.widget<FilledButton>(find.byType(FilledButton));

      Future<void> configure({
        bool? grouped,
        required List<AcpSessionConfigOptionView> canonical,
      }) async {
        final gate = Completer<void>();
        gates.add(gate);
        harness.port.configureResult = gate;
        if (grouped == null) {
          await tester.tap(find.byType(Switch));
        } else {
          await tester.tap(dropdown(grouped));
          await tester.pumpAndSettle();
          if (grouped) expect(find.text('服务端分组'), findsWidgets);
          await tester.tap(find.text(grouped ? '深入分析' : '请求高质量').last);
        }
        await tester.pump();
        expect(harness.owner.state.configPending, isTrue);
        expect(sendButton().onPressed, isNull);
        // Tapping a disabled production button must not reach the port.
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(
          harness.port.calls.where((call) => call.$1 == 'prompt'),
          isEmpty,
        );
        final request = harness.port.calls.last.$2 as AcpConfigureRequestView;
        expect(request.target, same(harness.owner.state.target));
        expect(
          request.configId,
          grouped == null
              ? acpBooleanFixture.id
              : AcpConfigId(grouped ? 'vendor/grouped' : 'vendor/select'),
        );
        if (grouped == null) {
          expect((request.value as AcpBooleanConfigValueView).value, isTrue);
        } else {
          expect(
            (request.value as AcpSelectConfigValueView).value,
            AcpConfigValueId(grouped ? 'group/raw:2' : 'flat/raw:2'),
          );
        }
        // An ACK alone cannot invent a current value. The formal event below
        // can normalize the selection back to its original server value.
        gate.complete();
        await tester.pump();
        expect(harness.owner.state.configPending, isTrue);
        expect(sendButton().onPressed, isNull);
        harness.emit(
          AcpConfiguredEventView(
            AcpConfiguredResponseView(configOptions: canonical),
          ),
        );
        await tester.pumpAndSettle();
        expect(harness.owner.state.configPending, isFalse);
        expect(sendButton().onPressed, isNotNull);
        expect(draft.state.draft, '原生 ACP 消息');
      }

      await configure(grouped: false, canonical: options());
      expect(
        tester.widget<DropdownButton<AcpConfigValueId>>(dropdown(false)).value,
        const AcpConfigValueId('flat/raw:1'),
      );
      await configure(grouped: true, canonical: options(groupedChanged: true));
      expect(
        tester.widget<DropdownButton<AcpConfigValueId>>(dropdown(true)).value,
        const AcpConfigValueId('group/raw:2'),
      );
      await configure(canonical: options(groupedChanged: true));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        harness.port.calls.where((call) => call.$1 == 'configure'),
        hasLength(3),
      );
      await capturePresentation(tester, 'acp-native-configured.png');

      // Keep admission in flight across a second actual tap.
      final admission = Completer<AcpRunIdView>();
      harness.port.promptResult = admission;
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(sendButton().onPressed, isNull);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      final prompts = harness.port.calls.where((call) => call.$1 == 'prompt');
      expect(prompts, hasLength(1));
      final prompt = prompts.single.$2 as AcpPromptRequestView;
      expect(prompt.target, same(harness.owner.state.target));
      expect((prompt.content.single as AcpTextContentView).text, '原生 ACP 消息');
      admission.complete(run);
      await tester.pumpAndSettle();
      expect(draft.state.draft, isEmpty);
      expect(draft.state.submissionRevision, greaterThan(0));
      expect(harness.owner.state.activeRun, run);

      // Generation and configuration are independent controls. Exercise the
      // production widget while the admitted run remains active, using a fresh
      // command gate rather than the already-completed pre-send fixture gate.
      final runningConfiguration = Completer<void>();
      gates.add(runningConfiguration);
      harness.port.configureResult = runningConfiguration;
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(harness.owner.state.activeRun, run);
      expect(harness.owner.state.sendPending, isFalse);
      expect(harness.owner.state.configPending, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        tester
            .widget<DropdownButton<AcpConfigValueId>>(dropdown(false))
            .onChanged,
        isNull,
      );
      final runningRequest =
          harness.port.calls.last.$2 as AcpConfigureRequestView;
      expect(runningRequest.target, same(harness.owner.state.target));
      expect(runningRequest.configId, acpBooleanFixture.id);
      expect((runningRequest.value as AcpBooleanConfigValueView).value, isTrue);
      harness.emit(
        AcpConfiguredEventView(
          AcpConfiguredResponseView(
            configOptions: [
              ...options(groupedChanged: true).take(2),
              AcpSessionConfigOptionView(
                id: acpBooleanFixture.id,
                name: acpBooleanFixture.name,
                description: acpBooleanFixture.description,
                category: acpBooleanFixture.category,
                kind: const AcpBooleanConfigView(currentValue: true),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(harness.owner.state.activeRun, run);
      expect(harness.owner.state.configPending, isTrue);
      runningConfiguration.complete();
      await tester.pumpAndSettle();
      expect(harness.owner.state.activeRun, run);
      expect(harness.owner.state.configPending, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      expect(
        tester
            .widget<DropdownButton<AcpConfigValueId>>(dropdown(false))
            .onChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<DropdownButton<AcpConfigValueId>>(dropdown(true))
            .onChanged,
        isNotNull,
      );
      expect(prompts, hasLength(1));
      expect(
        harness.port.calls.where((call) => call.$1 == 'configure'),
        hasLength(4),
      );
      debugPrint(
        'ACP native running configuration applied; original run active',
      );

      const permissions = [
        AcpPermissionOptionView(
          optionId: AcpPermissionOptionId('allow/server-once'),
          name: '仅此次允许',
          kind: AcpPermissionOptionKindView.allowOnce,
        ),
        AcpPermissionOptionView(
          optionId: AcpPermissionOptionId('allow/server-always'),
          name: '总是允许',
          kind: AcpPermissionOptionKindView.allowAlways,
        ),
        AcpPermissionOptionView(
          optionId: AcpPermissionOptionId('deny/server-once'),
          name: '仅此次拒绝',
          kind: AcpPermissionOptionKindView.rejectOnce,
        ),
        AcpPermissionOptionView(
          optionId: AcpPermissionOptionId('deny/server-always'),
          name: '总是拒绝',
          kind: AcpPermissionOptionKindView.rejectAlways,
        ),
      ];
      for (var index = 0; index < permissions.length; index++) {
        final id = AcpPermissionIdView(
          instance: run.instance,
          sequence: BigInt.from(index + 30),
        );
        harness.emit(
          AcpPermissionEventView(
            id: id,
            request: AcpPermissionRequestView(
              sessionId: acpRemoteFixture,
              toolCall: AcpToolCallUpdateView(
                toolCallId: const AcpToolCallId('native/read'),
                fields: AcpToolCallUpdateFieldsView(title: '读取项目文件'),
              ),
              options: permissions,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final option in permissions) {
          expect(find.text(option.name), findsOneWidget);
        }
        if (index == 0) {
          await capturePresentation(tester, 'acp-native-permission.png');
        }
        final option = permissions[index];
        final button = find.byKey(ValueKey((id, option.optionId)));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final answer =
            harness.port.calls.last.$2 as AcpPermissionAnswerRequestView;
        expect(answer.permissionId, same(id));
        expect(answer.optionId, option.optionId);
        expect(answer.target, same(harness.owner.state.target));
        expect(harness.owner.state.pendingPermissions, isEmpty);
      }
      expect(
        harness.port.calls.where((call) => call.$1 == 'answerPermission'),
        hasLength(4),
      );

      harness.update(
        const AcpAgentMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '原生流式回复')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '下一条草稿');
      await tester.pumpAndSettle();
      expect(find.text('原生流式回复'), findsOneWidget);

      // A -> B -> A replaces the real component subtree, allowing autoDispose
      // display watches to release; the Client owner must keep consuming A.
      final sourceB = ControlledAcpObservation([
        AcpAcceptedFrameView(
          target: AcpSessionTargetView(
            sessionId: 'session',
            agentId: 'agent-b',
            threadId: 'thread-b',
            instance: BigInt.from(20),
          ),
          hasObservation: true,
        ),
        AcpEventFrameView(
          AcpReadyEventView(
            AcpNewSessionResponseView(
              sessionId: const AcpRemoteSessionId('remote-b'),
            ),
          ),
        ),
        const AcpSettledFrameView(AcpSuccessView<void>(null)),
      ]);
      otherSource = sourceB;
      harness.port.sources.add(sourceB);
      final ownerB = await harness.client.acpSessions.openConversation(
        OpenAcpSessionRequestView(
          accountId: 'account',
          expectedConnectionRevision: BigInt.one,
          workspaceId: 'workspace',
          threadId: 'thread-b',
          intent: const AcpLoadIntentView(AcpRemoteSessionId('remote-b')),
        ),
      );
      await showPage('thread-b');
      expect(find.text('原生流式回复'), findsNothing);
      harness.update(
        const AcpAgentMessageChunkView(
          AcpContentChunkView(content: AcpTextContentView(text: '，后台继续')),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.source.closeSignals, 0);
      expect(ownerB.state.activeRun, isNull);
      await showPage('thread');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AcpConversationContent)),
      );
      expect(
        await container.read(acpConversationOwnerProvider('thread').future),
        same(harness.owner),
      );
      expect(find.text('原生流式回复，后台继续'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '下一条草稿',
      );
      expect(harness.client.drafts.composer('thread'), same(draft));
      expect(
        harness.port.calls.where((call) => call.$1 == 'open'),
        hasLength(2),
      );
      expect(prompts, hasLength(1));

      await capturePresentation(tester, 'acp-native-background-return.png');
      await tester.tap(find.text('中断'));
      await tester.pumpAndSettle();
      final interrupt = harness.port.calls.last.$2 as AcpInterruptRequestView;
      expect(interrupt.target, same(harness.owner.state.target));
      expect(interrupt.run, run);
      // Control completion is not prompt completion; only the formal event ends it.
      expect(harness.owner.state.activeRun, run);
      harness.emit(
        AcpCompletedEventView(
          AcpCompletedRunView(
            run: run,
            completionSequence: BigInt.one,
            result: const AcpSuccessView(
              AcpPromptResponseView(stopReason: AcpStopReasonView.cancelled),
            ),
            summary: 'cancelled',
            truncated: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.owner.state.activeRun, isNull);
      expect(find.text('中断'), findsNothing);
      expect(sendButton().onPressed, isNotNull);
      expect(draft.state.draft, '下一条草稿');
      expect(prompts, hasLength(1));
      expect(
        harness.port.calls.where((call) => call.$1 == 'interrupt'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      debugPrint(
        'ACP native assertions complete on ${Platform.operatingSystem}',
      );
    },
  );
}
