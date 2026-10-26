import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import 'interaction_snapshot.dart';
import 'thread_runtime_snapshot.dart';
import 'thread_settings_snapshot.dart';

part 'thread_command_reply.freezed.dart';

/// Evidence returned by one route write, not a replacement canonical mirror.
@Freezed(toStringOverride: false)
final class ThreadModelRouteCommandReply with _$ThreadModelRouteCommandReply {
  const ThreadModelRouteCommandReply({
    required this.runtime,
    required this.settings,
    required this.modeDefaultSaved,
    required this.warning,
    required this.receipt,
  });
  final ThreadRuntimeSnapshot runtime;
  final ThreadSettingsSnapshot settings;
  final bool modeDefaultSaved;
  final String? warning;
  final CommitReceipt receipt;
}

/// A complete native interaction result; it does not fabricate a read scope.
@Freezed(toStringOverride: false)
final class InteractionCommandReply with _$InteractionCommandReply {
  const InteractionCommandReply({
    required this.interaction,
    required this.receipt,
  });
  final InteractionSnapshot interaction;
  final CommitReceipt receipt;
}
