import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/profile_values.dart';

part 'profile_reads.freezed.dart';

@freezed
abstract class AgentProfilesReadHeader with _$AgentProfilesReadHeader {
  const factory AgentProfilesReadHeader({required TypedListRef profiles, required TypedListRef diagnostics}) = _AgentProfilesReadHeader;
}

@Freezed(toStringOverride: false)
abstract class AgentProfileRead with _$AgentProfileRead {
  const factory AgentProfileRead({required ReadText profileId, required ReadText displayName, required ReadText description, required ReadText whenToUse, required ReadText systemInstructions, required ReadText accountId, required ReadText modelId, required ReadText? effort, required ReadText source, required ReadText revision, required ReadText contentHash, required bool system, required bool enabled, required AgentWorkspaceMode workspaceMode}) = _AgentProfileRead;
}

@Freezed(toStringOverride: false)
abstract class ProfileDiagnosticRead with _$ProfileDiagnosticRead {
  const factory ProfileDiagnosticRead({required ReadText path, required ReadText message}) = _ProfileDiagnosticRead;
}
