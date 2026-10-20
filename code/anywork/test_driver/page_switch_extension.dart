import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'page_switch.dart';
import 'raw_tap_extension.dart';

/// Reuses normal tap hit testing and event routing. No backend delay or fake loading.
class PageSwitchCommandExtension extends CommandExtension {
  PageSwitchCommandExtension({required this.client, required this.owner});
  final AnyworkClient Function() client;
  final TimelineSessionOwner Function() owner;

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
    final display = owner();
    final lease = display.lease(request.threadId);
    if (lease == null ||
        lease.generation != request.generation ||
        !lease.hasOlder) {
      throw StateError(
        'PageSwitch requires the current display and an older page',
      );
    }
    final scope = lease.queries;
    if (scope == null) throw StateError('PageSwitch has no active query scope');
    Future<void>? page;
    Observation? observation;
    var pageCompleted = false;
    var loadingAtTap = false;
    var switchedWhilePending = false;
    var pendingAtTap = 0;
    var pendingAtSwitch = 0;
    String? destination;
    StudioThreadSession? opening;
    int? openingAttempt;
    var openingAtReturn = false;
    var openingReleased = false;
    try {
      final tap = RawTapCommandExtension(
        followingTap: request.bounceBack
            ? ByValueKey('thread-row-${request.threadId}')
            : null,
        onBeforeFollowingTap: () {
          opening = client().activeSession;
          final timeline = opening?.timeline;
          openingAttempt = timeline?.currentAttemptId?.value;
          openingAtReturn =
              opening?.threadId == request.destinationThreadId &&
              timeline?.state.value is ChatOpening<StudioTimelineFrame> &&
              openingAttempt != null &&
              timeline!.ownedAttemptCount > 0;
          if (!openingAtReturn) {
            throw StateError('Rapid return did not overlap the real open');
          }
        },
        onBeforeTap: () {
          if (client().selection.state.selectedThreadId != request.threadId ||
              display.lease(request.threadId)?.generation !=
                  request.generation) {
            throw StateError('PageSwitch target changed before input');
          }
          page = display
              .loadOlder(request.threadId, generation: request.generation)
              .whenComplete(() => pageCompleted = true);
          loadingAtTap = display.source.value?.isLoadingOlder == true;
          pendingAtTap = scope.pendingQueries;
          if (!loadingAtTap || pendingAtTap == 0) {
            throw StateError('PageSwitch page was not accepted');
          }
          observation = client().selection.source.watch((selection) {
            if (selection.selectedThreadId == request.threadId) {
              return;
            }
            destination = selection.selectedThreadId;
            switchedWhilePending = !pageCompleted;
            pendingAtSwitch = scope.pendingQueries;
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
      await lease.released;
      if (request.bounceBack) {
        if (client().selection.state.selectedThreadId != request.threadId) {
          throw StateError('Rapid return did not select the original thread');
        }
        final retired = await opening!.timeline.joinRetired();
        openingReleased =
            retired.complete && opening!.timeline.ownedAttemptCount == 0;
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
        'oldDisplayReleased': lease.isReleased,
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
