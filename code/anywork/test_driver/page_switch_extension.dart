import 'package:anywork/src/features/conversation/presentation_api.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'page_switch.dart';
import 'raw_tap_extension.dart';

/// Reuses normal tap hit testing and event routing. No backend delay or fake loading.
class PageSwitchCommandExtension extends CommandExtension {
  PageSwitchCommandExtension({required this.workspace, required this.conversations,
    required this.owner});
  final WorkspaceRepository Function() workspace;
  final ConversationRepository Function() conversations;
  final TimelineCoordinator Function() owner;

  @override
  String get commandKind => 'PageSwitch';

  @override
  Command deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
    DeserializeCommandFactory commandFactory,
  ) => PageSwitch.deserialize(params, finderFactory);

  @override
  Future<Result> call(
    Command command,
    WidgetController prober,
    CreateFinderFactory finderFactory,
    CommandHandlerFactory handlerFactory,
  ) async {
    final request = command as PageSwitch;
    final deadline = DateTime.now().add(request.timeout ?? const Duration(seconds: 30));
    final display = owner();
    final original = display.display(request.threadId);
    final selection = workspace();
    final repository = conversations();
    if (original == null || original.generation != request.generation ||
        display.value?.hasOlder != true) {
      throw StateError(
        'PageSwitch requires the current display and an older page',
      );
    }
    Future<void>? page;
    Observation? observation;
    var pageCompleted = false;
    var loadingAtTap = false;
    var switchedWhilePending = false;
    var pendingAtTap = 0;
    var pendingAtSwitch = 0;
    String? destination;
    ConversationSession? opening;
    TimelineLifecycleRead? openingLifecycle;
    int? openingAttempt;
    var openingAtReturn = false;
    var openingReleased = false;
    try {
      final tap = RawTapCommandExtension(
        followingTap: request.bounceBack
            ? ByValueKey('thread-row-${request.threadId}')
            : null,
        onBeforeFollowingTap: () {
          // Freeze the actual B Session and read-only lifecycle before the
          // second real input. An opening phase is not a native Future probe.
          opening = repository.active.value;
          final timeline = opening?.timeline;
          final state = timeline?.state.value;
          openingLifecycle = timeline?.lifecycle;
          openingAttempt = state?.attemptId?.value;
          openingAtReturn =
              opening?.threadId == request.destinationThreadId &&
              state?.phase == TimelineConnectionPhase.opening &&
              openingAttempt != null &&
              openingLifecycle!.ownedAttemptCount > 0;
          if (!openingAtReturn) {
            throw StateError('Rapid return did not overlap the real open');
          }
        },
        onBeforeTap: () {
          if (selection.state.value.selection.threadId != request.threadId ||
              !identical(display.display(request.threadId), original) ||
              original.generation != request.generation) {
            throw StateError('PageSwitch target changed before input');
          }
          page = display
              .loadOlder(request.threadId, request.generation)
              .whenComplete(() => pageCompleted = true);
          // Observe immediately, but keep the original Future for its true
          // result/join below. A page failure must not escape through the Zone.
          page!.then<void>((_) {}, onError: (Object _, StackTrace __) {}).ignore();
          loadingAtTap = display.value?.olderLoading == true;
          pendingAtTap = original.pendingQueries;
          if (!loadingAtTap || pendingAtTap == 0) {
            throw StateError('PageSwitch page was not accepted');
          }
          observation = selection.state.watch((state) {
            if (state.selection.threadId == request.threadId || destination != null) {
              return;
            }
            destination = state.selection.threadId;
            switchedWhilePending = !pageCompleted;
            pendingAtSwitch = original.pendingQueries;
          });
        },
      );
      await tap.call(command, prober, finderFactory, handlerFactory);
      await page;
      if (!loadingAtTap ||
          !switchedWhilePending ||
          pendingAtSwitch == 0 ||
          destination != request.destinationThreadId) {
        throw StateError('Sidebar selection did not overlap the accepted page');
      }
      final displayReport = await original.observeRelease(deadline: deadline);
      if (!displayReport.complete || !original.isReleased) {
        throw StateError('The original display has unresolved release responsibility');
      }
      if (request.bounceBack) {
        if (selection.state.value.selection.threadId != request.threadId) {
          throw StateError('Rapid return did not select the original thread');
        }
        final retired = await openingLifecycle!.observeRetired(deadline: deadline);
        openingReleased =
            retired.complete && openingLifecycle!.ownedAttemptCount == 0;
        if (!openingReleased) {
          throw StateError('The abandoned opening attempt did not release');
        }
      }
      return _PageSwitchResult({
        'threadId': request.threadId,
        'generation': request.generation,
        'destination': destination,
        'loadingAtTap': loadingAtTap,
        'switchedWhilePending': switchedWhilePending,
        'pendingQueriesAtTap': pendingAtTap,
        'pendingQueriesAtSwitch': pendingAtSwitch,
        // This is only the original display, not all candidates/consumers.
        'oldDisplayReleased': original.isReleased,
        if (request.bounceBack) ...{
          'openingAtReturn': openingAtReturn,
          'openingAttemptId': openingAttempt,
          'openingReleased': openingReleased,
        },
        'pass': true,
      });
    } finally {
      observation?.cancel();
      await page;
    }
  }
}

class _PageSwitchResult extends Result {
  _PageSwitchResult(this.value);
  final Map<String, Object?> value;
  @override
  Map<String, dynamic> toJson() => value;
}
