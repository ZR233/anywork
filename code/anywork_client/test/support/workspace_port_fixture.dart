import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import 'scripted_feed.dart';

final class WorkspaceRestoreCall {
  WorkspaceRestoreCall(this.threadId);
  final String threadId;
  final reply = Completer<WorkspaceThreadRecord>();
}

/// No baseline is invented: these actual native opens stay pending until the
/// test supplies their handles, including after the original owner seals.
final class WorkspaceProjectOpen {
  WorkspaceProjectOpen(this.index);
  final int index;
  final reply = Completer<FeedConnection<ProjectDirectoryFrame>>();
  ScriptedFeed<ProjectDirectoryFrame>? native;
  ScriptedFeed<ProjectDirectoryFrame> accept() {
    final feed = ScriptedFeed<ProjectDirectoryFrame>(feedId: 'binding-projects-$index',
      sequenceOf: (frame) => frame is ProjectDirectoryData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! ProjectDirectoryData);
    native = feed;
    reply.complete(feed);
    return feed;
  }
}

final class WorkspaceThreadOpen {
  WorkspaceThreadOpen(this.scope, this.index);
  final ThreadDirectoryScope scope;
  final int index;
  final reply = Completer<ThreadDirectoryConnection>();
  WorkspaceNativeThreadFeed? native;
  WorkspaceNativeThreadFeed accept() {
    final feed = WorkspaceNativeThreadFeed(index);
    native = feed;
    reply.complete(feed);
    return feed;
  }
}

/// Thin native handle only; the production Workspace owns selection, query
/// membership, feed supervision and the backend frontier, none of which this
/// pending-open environment needs to implement.
final class WorkspaceNativeThreadFeed implements ThreadDirectoryConnection {
  WorkspaceNativeThreadFeed(int index) : feed = ScriptedFeed<ThreadDirectoryFrame>(feedId: 'binding-thread-$index',
    sequenceOf: (frame) => frame is ThreadDirectoryData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! ThreadDirectoryData);
  final ScriptedFeed<ThreadDirectoryFrame> feed;
  @override
  Stream<ThreadDirectoryFrame> get events => feed.events;
  @override
  Future<void> ackThrough(int sequence) => feed.ackThrough(sequence);
  @override
  void requestClose() => feed.requestClose();
  @override
  Future<FeedCloseReport> close() => feed.close();
  @override
  Future<FeedCloseReport> retryClose() => feed.retryClose();
  @override
  Future<ThreadDirectoryReadTarget> extendWindow(ProductCollectionRef expectedCollection, {int limit = 32}) =>
    throw UnsupportedError('No native frontier was published by this pending-open environment');
}

/// Scripted external WorkspacePort, not a Workspace Repository/selection fake.
/// Successful restore materials are supplied explicitly by each test. Only
/// actual port entries complete the barriers; waiting never starts a request.
final class ScriptedWorkspacePort implements WorkspacePort {
  final restores = <WorkspaceRestoreCall>[];
  final projects = <WorkspaceProjectOpen>[];
  final threads = <WorkspaceThreadOpen>[];
  final firstProjectOpen = Completer<WorkspaceProjectOpen>();
  final firstThreadOpen = Completer<WorkspaceThreadOpen>();
  final _restoreWaiters = <int, Completer<WorkspaceRestoreCall>>{};

  Future<WorkspaceRestoreCall> restoreOpened(int index) => index < restores.length ? Future.value(restores[index])
    : _restoreWaiters.putIfAbsent(index, Completer<WorkspaceRestoreCall>.new).future;

  @override
  Future<WorkspaceThreadRecord> restoreThread(String threadId) {
    final call = WorkspaceRestoreCall(threadId);
    final index = restores.length;
    restores.add(call);
    _restoreWaiters.remove(index)?.complete(call);
    return call.reply.future;
  }
  @override
  Future<FeedConnection<ProjectDirectoryFrame>> openProjectDirectory() {
    final call = WorkspaceProjectOpen(projects.length);
    projects.add(call);
    if (!firstProjectOpen.isCompleted) firstProjectOpen.complete(call);
    return call.reply.future;
  }
  @override
  Future<ThreadDirectoryConnection> openThreadDirectory(ThreadDirectoryScope scope) {
    final call = WorkspaceThreadOpen(scope, threads.length);
    threads.add(call);
    if (!firstThreadOpen.isCompleted) firstThreadOpen.complete(call);
    return call.reply.future;
  }

  void releasePending() {
    for (final call in restores) {
      if (!call.reply.isCompleted) call.reply.completeError(const CommandDispatchFailure.rejected(
        failure: StudioFailure(code: StudioFailureCode.cancelled, message: 'The scripted restore did not execute.',
          retryable: false, correlationId: 'binding-test-teardown')));
    }
    acceptPendingOpens();
    for (final call in projects) { _releaseClose(call.native!); }
    for (final call in threads) { _releaseClose(call.native!.feed); }
  }

  void acceptPendingOpens() {
    for (final call in projects) { if (call.native == null) call.accept(); }
    for (final call in threads) { if (call.native == null) call.accept(); }
  }
  void _releaseClose<T>(ScriptedFeed<T> feed) {
    final receipt = feed.closeReceipt;
    if (receipt != null && !receipt.isCompleted) receipt.complete(
      FeedCloseReport(feedId: feed.feedId, outcome: const FeedCloseOutcome.clean()));
  }
  @override
  Never noSuchMethod(Invocation invocation) =>
    throw UnsupportedError('Unscripted Workspace native capability: ${invocation.memberName}');
}
