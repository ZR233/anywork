import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/studio_routes.dart';
import 'app_graph.dart';

/// Adapts the committed GoRouter destination to the single GUI content owner.
/// It holds no page stack, content, subscription or independent selection.
final class ConversationRouteBinding {
  ConversationRouteBinding(this.router, this.graph) {
    router.routerDelegate.addListener(_routeChanged);
    _routeChanged();
  }

  final GoRouter router;
  final AppGraph graph;
  final activation = ValueNotifier<AsyncValue<String?>>(const AsyncData(null));
  Object? _destination;
  int _generation = 0;
  bool _closed = false;

  void _routeChanged() {
    if (_closed || router.routerDelegate.currentConfiguration.isEmpty) return;
    final state = router.routerDelegate.state;
    final destination = (state.pageKey, state.name, state.uri.toString());
    if (_destination == destination) return;
    _destination = destination;
    // The SDK's navigation generation revokes queued selection intents without
    // mutating selection or cancelling any accepted business operation.
    graph.client.selection.beginNavigation();
    final generation = ++_generation;
    // A Router callback can occur while Flutter is reconciling pages. Each
    // committed departure still revokes demand, even if a return is coalesced.
    scheduleMicrotask(() {
      if (_closed) return;
      graph.setConversationPageVisible(false);
      if (generation != _generation) return;
      unawaited(_activate(state, generation));
    });
  }

  bool _owns(int generation) => !_closed && generation == _generation;

  Future<void> _activate(GoRouterState state, int generation) async {
    activation.value = const AsyncData(null);
    if (!_owns(generation)) return;
    if (state.name == StudioRoutes.studio) {
      graph.setConversationPageVisible(true);
      return;
    }
    if (state.name != StudioRoutes.botConversation) return;
    final threadId = state.pathParameters['threadId']!;
    activation.value = const AsyncLoading();
    if (!_owns(generation)) return;
    try {
      await graph.client.bootstrap();
      if (!_owns(generation)) return;
      await graph.client.directoryCommands.selectThread(threadId);
      if (!_owns(generation)) return;
      final selection = graph.client.selection.state;
      if (selection.selectedThreadId != threadId || selection.needsOpen) {
        throw const StudioFailure(
          code: StudioFailureCode.notFound,
          message: 'The conversation destination is unavailable.',
          retryable: false,
          correlationId: 'conversation-route-target',
        );
      }
      graph.setConversationPageVisible(true, expectedThreadId: threadId);
      if (_owns(generation)) activation.value = AsyncData(threadId);
    } catch (error, stack) {
      if (_owns(generation)) activation.value = AsyncError(error, stack);
    }
  }

  void retry() {
    if (_closed) return;
    _destination = null;
    _routeChanged();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    ++_generation;
    graph.client.selection.beginNavigation();
    router.routerDelegate.removeListener(_routeChanged);
    graph.setConversationPageVisible(false);
    activation.dispose();
  }
}
