import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shutdown_view.dart';
import 'shutdown_view_model.dart';

/// Must replace the whole Router child in MaterialApp.builder, not cover it.
/// Covered Settings/Conversation pages then really unmount even if TickerMode
/// paused their observations; controller owners wait on the actual unmounts.
class ApplicationShutdownBoundary extends ConsumerWidget {
  const ApplicationShutdownBoundary({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(shutdownViewModelProvider).asData?.value;
    return value?.exiting == true ? ApplicationShutdownView(state: value!) : child;
  }
}
