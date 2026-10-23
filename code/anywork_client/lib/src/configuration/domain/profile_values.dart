import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile_values.freezed.dart';

enum AgentWorkspaceMode { unrestricted, directory, worktree, review }

@freezed
abstract class AgentProfileSummary with _$AgentProfileSummary {
  const factory AgentProfileSummary({
    required String profileId,
    required String displayName,
    required String description,
    required String whenToUse,
    required String accountId,
    required String modelId,
    required String? effort,
    required String source,
    required String revision,
    required String contentHash,
    required bool system,
    required bool enabled,
    required AgentWorkspaceMode workspaceMode,
  }) = _AgentProfileSummary;
}

@Freezed(toStringOverride: false)
final class ProfilesValue with _$ProfilesValue {
  ProfilesValue({required List<AgentProfileSnapshot> profiles, required List<ProfileDiagnostic> diagnostics}) : profiles = List.unmodifiable(profiles), diagnostics = List.unmodifiable(diagnostics);
  final List<AgentProfileSnapshot> profiles;
  final List<ProfileDiagnostic> diagnostics;
}

@Freezed(toStringOverride: false)
abstract class AgentProfileSnapshot with _$AgentProfileSnapshot {
  const factory AgentProfileSnapshot({
    required String profileId,
    required String displayName,
    required String description,
    required String whenToUse,
    required String systemInstructions,
    required String accountId,
    required String modelId,
    required String? effort,
    required String source,
    required String revision,
    required String contentHash,
    required bool system,
    required bool enabled,
    required AgentWorkspaceMode workspaceMode,
  }) = _AgentProfileSnapshot;
}

@freezed
abstract class ProfileDiagnostic with _$ProfileDiagnostic {
  const factory ProfileDiagnostic({required String path, required String message}) = _ProfileDiagnostic;
}

@Freezed(toStringOverride: false)
abstract class AgentProfileEdit with _$AgentProfileEdit {
  const factory AgentProfileEdit({
    required String profileId,
    required String displayName,
    required String description,
    required String whenToUse,
    required String systemInstructions,
    required String accountId,
    required String modelId,
    required String? effort,
    required bool enabled,
    required AgentWorkspaceMode workspaceMode,
  }) = _AgentProfileEdit;
}
