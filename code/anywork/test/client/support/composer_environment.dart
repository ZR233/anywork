import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/connectors/composer_connector.dart';
import 'package:anywork/src/features/conversation/state/conversation_view_state.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart' show OperationId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_client_future.dart';
import 'selector_conversation_port.dart';
import 'selector_environment.dart';

const composerThreadId = 'thread-main';
const composerExecution = AgentExecution(
  id: 'exec-1',
  phase: AgentExecutionPhase.running,
  turnId: 'turn-1',
);
const composerContinuation = ContinuationView(
  id: 'continuation-1',
  sourceTurnId: 'turn-1',
  reason: ContinuationReason.userStop,
  createdAt: 1767225600,
  claimed: false,
);

CommitReceipt composerReceipt(
  OperationId operationId, {
  bool effective = false,
  bool durable = false,
}) => CommitReceipt(
  operationId: operationId,
  disposition: CommitDisposition.applied,
  targets: const [],
  effect: EffectPoint.immediate,
  effective: effective,
  durable: durable,
  requiresIdentityObservation: true,
);

ContinuationOperationView composerContinuationView(
  SelectorContinueCall call, {
  ContinuationOperationState state = const ContinuationOperationState.pending(),
  bool durable = true,
}) => ContinuationOperationView(
  threadId: call.threadId,
  operationId: call.operationId,
  inputId: call.operationId.value,
  continuationId: call.continuationId,
  acceptedSequence: 7,
  state: state,
  durable: durable,
  receipt: composerReceipt(call.operationId, durable: durable),
);

/// Real VM/Session/Workspace/Drafts assembly. Only native frames, replies and
/// read gates are supplied; no primary-action or operation reducer lives here.
final class ComposerEnvironment {
  ComposerEnvironment(this.env);
  final SelectorEnvironment env;
  ConversationSession get session =>
      env.conversations.existingSession(composerThreadId)!;
  ConversationViewModel get vm => env.container.read(
    conversationViewModelProvider(composerThreadId).notifier,
  );
  ConversationViewState get state => env.container
      .read(conversationViewModelProvider(composerThreadId))
      .requireValue;
  final page = ConversationStopPage(isCurrent: () => true);
  late final ProviderSubscription<AsyncValue<ConversationViewState>>
  subscription;

  static Future<ComposerEnvironment> open(
    WidgetTester tester, {
    ThreadExecutionBaseline? initial,
  }) async {
    final env = SelectorEnvironment();
    env.conversationPort.initialExecution = initial;
    final fixture = ComposerEnvironment(env);
    addTearDown(() async {
      fixture.page.retire();
      fixture.subscription.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(tester, env.close(), 'composer owner cleanup');
    });
    await pumpClientFuture(tester, env.establish(), 'composer product sources');
    await pumpClientFuture(
      tester,
      env.selectThread(composerThreadId),
      'composer Session',
    );
    fixture.subscription = env.container.listen(
      conversationViewModelProvider(composerThreadId),
      (_, _) {},
    );
    await pumpClientFuture(
      tester,
      env.container.read(
        conversationViewModelProvider(composerThreadId).future,
      ),
      'composer VM',
    );
    fixture.vm.deferStopPage(fixture.page);
    await pumpClientFuture(
      tester,
      fixture.waitFor(
        (state) =>
            state.executionCurrent &&
            state.metadataCurrent &&
            state.configuration?.value?.modelRoute != null,
      ),
      'composer canonical execution and route',
    );
    return fixture;
  }

  Future<ConversationViewState> waitFor(
    bool Function(ConversationViewState) matches,
  ) {
    final done = Completer<ConversationViewState>();
    final watcher = env.container.listen(
      conversationViewModelProvider(composerThreadId),
      (_, next) {
        final value = next.asData?.value;
        if (!done.isCompleted && value != null && matches(value)) {
          done.complete(value);
        }
      },
      fireImmediately: true,
    );
    return done.future.whenComplete(watcher.close);
  }

  Future<void> publish(
    WidgetTester tester,
    ThreadExecutionBaseline value,
  ) async {
    await pumpClientFuture(
      tester,
      env.conversationPort.publishExecution(value),
      'explicit native execution ACK',
    );
    await tester.pump();
  }

  Future<void> pump(
    WidgetTester tester, {
    String threadId = composerThreadId,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: env.container,
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('en'),
          localizationsDelegates: _localizations,
          supportedLocales: _locales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: _ComposerMount(threadId: threadId, page: page),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

// Import localization at this test assembly boundary, never in a domain fake.
final _localizations = AppLocalizations.localizationsDelegates;
final _locales = AppLocalizations.supportedLocales;

class _ComposerMount extends ConsumerWidget {
  const _ComposerMount({required this.threadId, required this.page});
  final String threadId;
  final ConversationStopPage page;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(conversationViewModelProvider(threadId));
    final vm = ref.read(conversationViewModelProvider(threadId).notifier);
    final stop = vm.captureStop(page);
    return ComposerConnector(
      target: ComposerKey.thread(threadId: threadId),
      onStop: stop == null ? null : () => unawaited(stop()),
      stopState: vm.stopStateFor(page),
    );
  }
}
