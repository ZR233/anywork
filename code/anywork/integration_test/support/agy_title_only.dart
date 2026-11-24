import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_composer_connector.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'production_studio_harness.dart';

// Kept below the directory's 80-character provisional-title limit, so the
// expected initial summary is explicit, not calculated by a copy of production.
const _prompt =
    'Write a slogan for a fictional moon library. Use no tools. One sentence.';

// One New/draft and one UI submit. The title must arrive without listing
// sessions, and the same sidebar row must display it.
Future<void> runAgyTitleOnly({
  required ProductionStudioScene scene,
  required AcpConversationSession owner,
  required StudioProject project,
  required Map<String, Object?> evidence,
  required Future<void> Function(String) record,
  required Future<void> Function() closeHarness,
}) async {
  final tester = scene.tester;
  final client = scene.graph.client;
  final target = owner.state.target!;
  final remoteId = owner.state.remoteSessionId!;
  final metadata = client.threadDirectory.observeThread(target.threadId);
  final sidebarRow = find.byKey(StudioDriverKeys.threadRow(target.threadId));
  String? firstDirectoryTitle;
  String? lastDirectoryTitle;
  String? latestRawTitle;
  var firstDirectoryMatchesRaw = false;
  var rawUpdateCount = 0;
  var rawTitleField = 'absent';
  var summaryPublished = false;
  var summaryVisible = false;
  var permissionObserved = false;
  Object? observationFailure;
  var passed = false;

  evidence['target'] = {
    'sessionId': target.sessionId,
    'agentId': target.agentId,
    'threadId': target.threadId,
    'instance': target.instance.toString(),
    'acpSessionId': remoteId.value,
    'cwd': project.path,
    'workspaceId': project.id,
  };
  evidence['stopReason'] = null;

  void inspectOwner(AcpConversationState state) {
    // This is the existing owner, which already consumes qualified typed frames.
    // Never subscribe to a second raw transport or retain message/metadata JSON.
    if (state.target != target || state.remoteSessionId != remoteId) {
      observationFailure ??= StateError('Title observation changed ACP target');
      return;
    }
    permissionObserved |= state.pendingPermissions.isNotEmpty;
    final updates = state.content
        .whereType<AcpConversationUpdateItem>()
        .map((item) => item.update)
        .whereType<AcpSessionInfoUpdateView>()
        .toList(growable: false);
    for (final update in updates.skip(rawUpdateCount)) {
      switch (update.title) {
        case AcpFieldAbsent<String>():
          break;
        case AcpFieldNull<String>():
          rawTitleField = 'null';
          latestRawTitle = null;
        case AcpFieldValue<String>(:final value):
          final title = value.trim();
          rawTitleField = title.isEmpty ? 'empty' : 'value';
          latestRawTitle = title.isEmpty ? null : title;
      }
    }
    rawUpdateCount = updates.length;
    firstDirectoryMatchesRaw |=
        latestRawTitle != null && firstDirectoryTitle == latestRawTitle;
    if (state.error != null ||
        state.observationGap != null ||
        state.observationEnded ||
        state.disconnected) {
      observationFailure ??= StateError('Title owner observation failed');
    }
  }

  void inspectDirectory() {
    final state = metadata.state.value;
    if (state.error != null || state.closed) {
      observationFailure ??= StateError('Title directory observation failed');
      return;
    }
    final row = state.frame?.row;
    if (row == null) return;
    final backend = row.backend;
    if (row.sessionId != target.sessionId ||
        row.agentId != target.agentId ||
        row.threadId != target.threadId ||
        row.workspaceId != project.id ||
        row.workspaceMode != ThreadWorkspaceMode.local ||
        !p.equals(row.workspacePath, project.path) ||
        backend is! AcpAgentBackendView ||
        backend.reference.acpSessionId != remoteId.value ||
        !p.equals(backend.reference.cwd, project.path)) {
      observationFailure ??= StateError('Title directory target/cwd mismatch');
      return;
    }
    firstDirectoryTitle ??= row.title;
    lastDirectoryTitle = row.title;
    firstDirectoryMatchesRaw |=
        latestRawTitle != null && firstDirectoryTitle == latestRawTitle;
    summaryPublished |= row.title == _prompt;
  }

  void check() {
    inspectOwner(owner.state);
    inspectDirectory();
    if (observationFailure case final error?) throw error;
    if (permissionObserved) {
      throw StateError('Title-only prompt unexpectedly requested permission');
    }
    expect(client.drafts.composer(target.threadId).state.error, isNull);
    expect(owner.state.content.whereType<AcpConversationToolItem>(), isEmpty);
    summaryVisible |= find
        .descendant(of: sidebarRow, matching: find.text(_prompt))
        .evaluate()
        .isNotEmpty;
  }

  void snapshotTitles() {
    evidence['rawSessionInfo'] = {
      'updates': rawUpdateCount,
      'lastTitleField': rawTitleField,
      'title': latestRawTitle,
    };
    evidence['initialPublication'] = {
      'firstDirectoryTitle': firstDirectoryTitle,
      'summaryPublished': summaryPublished,
      'summaryVisible': summaryVisible,
      'firstDirectoryMatchesRaw': firstDirectoryMatchesRaw,
    };
    evidence['directoryTitle'] = lastDirectoryTitle;
  }

  final ownerWatch = owner.source.watch(inspectOwner);
  final directoryWatch = metadata.state.watch((_) => inspectDirectory());
  try {
    check();
    expect(owner.state.lastCompleted, isNull);
    expect(owner.state.activeRun, isNull);
    expect(owner.state.sendPending, isFalse);
    await record('title-draft-ready');
    await tester.enterText(
      find.descendant(
        of: find.byType(AcpStartComposerView),
        matching: find.byType(TextField),
      ),
      _prompt,
    );
    await tester.pumpAndSettle();
    evidence['promptCount'] = 1;
    await tester.tap(
      find.byKey(ValueKey(AcpViewKeyValues.startSubmit(project.id))),
    );
    await scene.until(
      () {
        check();
        final failure = client.drafts.attachments.state
            .newThread(project.id)
            .failure;
        if (failure != null) throw StateError('Title first-submit failed');
        return find.byType(AcpComposerConnector).evaluate().length == 1 &&
            metadata.state.value.frame?.row != null &&
            sidebarRow.evaluate().length == 1;
      },
      'title first-submit publishes this project sidebar row',
      timeout: const Duration(seconds: 90),
    );
    expect(
      tester
          .widget<AcpComposerConnector>(find.byType(AcpComposerConnector))
          .threadId,
      target.threadId,
    );
    expect(
      client.acpSessions.conversationForThread(target.threadId),
      same(owner),
    );
    await record('title-first-submit-published');

    await scene.until(
      () {
        check();
        return owner.state.lastCompleted != null &&
            owner.state.activeRun == null &&
            !owner.state.sendPending;
      },
      'one real title-only ACP prompt completes',
      timeout: const Duration(seconds: 120),
    );
    final completed = owner.state.lastCompleted!;
    expect(completed.completionSequence, BigInt.one);
    final result = completed.result;
    expect(result, isA<AcpSuccessView<AcpPromptResponseView>>());
    final stop =
        (result as AcpSuccessView<AcpPromptResponseView>).value.stopReason;
    evidence['stopReason'] = stop.name;
    expect(stop, AcpStopReasonView.endTurn);
    expect(
      owner.state.content.whereType<AcpConversationMessageItem>().where(
        (item) => item.kind == AcpConversationMessageKind.user,
      ),
      hasLength(1),
    );
    expect(
      owner.state.content.whereType<AcpConversationMessageItem>().where(
        (item) => item.kind == AcpConversationMessageKind.assistant,
      ),
      isNotEmpty,
    );

    // The title notification can precede or follow the prompt response.
    const titleWindow = Duration(seconds: 20);
    evidence['titleObservation'] = {
      'source': 'existingOwner.typedSessionInfoUpdate',
      'postResponseLimitMs': titleWindow.inMilliseconds,
    };
    await scene.until(
      () {
        check();
        final title = latestRawTitle;
        return title != null &&
            title != _prompt &&
            lastDirectoryTitle == title &&
            find
                .descendant(of: sidebarRow, matching: find.text(title))
                .evaluate()
                .isNotEmpty;
      },
      'the ACP title notification updates the directory and the same sidebar row',
      timeout: titleWindow,
    );
    final peerPreemptedSummary = !summaryPublished && firstDirectoryMatchesRaw;
    snapshotTitles();
    evidence['titleSource'] = 'sessionInfoUpdate';
    evidence['peerTitlePreemptedSummary'] = peerPreemptedSummary;
    expect(
      summaryPublished || peerPreemptedSummary,
      isTrue,
      reason: 'Neither the fixed initial summary nor an observed peer title was published',
    );
    evidence['sidebarTitleMatches'] = true;
    evidence['unexpectedPermissions'] = permissionObserved;
    expect(owner.state.lastCompleted!.completionSequence, BigInt.one);
    expect(client.drafts.composer(target.threadId).state.draft, isEmpty);
    await record('title-observation-complete');
    passed = true;
  } catch (error) {
    evidence['failureType'] = error.runtimeType.toString();
    rethrow;
  } finally {
    // Preserve filtered title evidence even if directory convergence failed.
    snapshotTitles();
    ownerWatch.cancel();
    directoryWatch.cancel();
    evidence['unexpectedPermissions'] = permissionObserved;
    evidence['verdict'] = 'failed';
    var sceneReleased = false;
    try {
      await metadata.release();
      await scene.dispose();
      sceneReleased = true;
    } finally {
      try {
        evidence['shutdown'] = 'failed';
        await closeHarness();
        evidence['shutdown'] = 'clean';
        evidence['verdict'] = passed && sceneReleased ? 'passed' : 'failed';
      } finally {
        await record('title-only-shutdown');
      }
    }
  }
}
