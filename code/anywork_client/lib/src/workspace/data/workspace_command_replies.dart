import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:anywork_client/operations.dart';

import '../domain/directory_values.dart';
import '../domain/selection.dart';

part 'workspace_command_replies.freezed.dart';

@Freezed(toStringOverride: false)
abstract class RenameThreadCommandReply with _$RenameThreadCommandReply {
  const factory RenameThreadCommandReply({required WorkspaceThreadRecord thread,
    required CommitReceipt receipt}) = _RenameThreadCommandReply;
}

@Freezed(toStringOverride: false)
abstract class ArchiveThreadCommandReply with _$ArchiveThreadCommandReply {
  const factory ArchiveThreadCommandReply({required ArchiveThreadResult result,
    required CommitReceipt receipt}) = _ArchiveThreadCommandReply;
}
