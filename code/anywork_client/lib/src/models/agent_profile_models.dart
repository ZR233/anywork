import 'thread_directory_models.dart';

enum AgentWorkspaceMode { unrestricted, directory, worktree, review }

/// Definition identity and descriptive metadata shared by all Profile backends.
class AgentDefinitionView {
  const AgentDefinitionView({
    required this.definitionId,
    required this.displayName,
    required this.description,
    required this.whenToUse,
    required this.source,
    required this.revision,
    required this.contentHash,
  });

  final String definitionId;
  final String displayName;
  final String description;
  final String whenToUse;
  final String source;
  final String revision;
  final String contentHash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDefinitionView &&
          definitionId == other.definitionId &&
          displayName == other.displayName &&
          description == other.description &&
          whenToUse == other.whenToUse &&
          source == other.source &&
          revision == other.revision &&
          contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(
    definitionId,
    displayName,
    description,
    whenToUse,
    source,
    revision,
    contentHash,
  );
}

/// Typed current Profile snapshot. Backend-specific fields remain in [binding].
class AgentProfileView {
  const AgentProfileView({
    required this.definition,
    required this.binding,
    required this.system,
    required this.enabled,
    required this.workspaceMode,
  });

  final AgentDefinitionView definition;
  final AgentBindingView binding;
  final bool system;
  final bool enabled;
  final AgentWorkspaceMode workspaceMode;

  String get id => definition.definitionId;
  String get displayName => definition.displayName;
  String get description => definition.description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentProfileView &&
          definition == other.definition &&
          binding == other.binding &&
          system == other.system &&
          enabled == other.enabled &&
          workspaceMode == other.workspaceMode;

  @override
  int get hashCode =>
      Object.hash(definition, binding, system, enabled, workspaceMode);
}

/// Editable user intent retains metadata and one closed backend binding.
class AgentProfileDraft {
  const AgentProfileDraft({
    required this.definition,
    required this.binding,
    this.enabled = true,
    this.workspaceMode = AgentWorkspaceMode.directory,
  });

  factory AgentProfileDraft.fromView(AgentProfileView profile) =>
      AgentProfileDraft(
        definition: profile.definition,
        binding: profile.binding,
        enabled: profile.enabled,
        workspaceMode: profile.workspaceMode,
      );

  final AgentDefinitionView definition;
  final AgentBindingView binding;
  final bool enabled;
  final AgentWorkspaceMode workspaceMode;

  String get id => definition.definitionId;
}
