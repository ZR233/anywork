import '../../../resources.dart';
import '../domain/profile_values.dart';
import 'configuration_port.dart';
import 'configuration_read_fields.dart';
import 'profile_reads.dart';

final class ProfilesReader {
  const ProfilesReader(this.scope);
  final AgentProfilesReadConnection scope;

  Future<String> text(ReadText value) =>
      readConfigurationText(value, scope.text);
  Future<String?> optional(ReadText? value) async =>
      value == null ? null : await text(value);

  /// The list never resolves systemInstructions, even if that field is Inline.
  Future<AgentProfileSummary> summary(AgentProfileRead value) async =>
      AgentProfileSummary(
        profileId: await text(value.profileId),
        displayName: await text(value.displayName),
        description: await text(value.description),
        whenToUse: await text(value.whenToUse),
        accountId: await text(value.accountId),
        modelId: await text(value.modelId),
        effort: await optional(value.effort),
        source: await text(value.source),
        revision: await text(value.revision),
        contentHash: await text(value.contentHash),
        system: value.system,
        enabled: value.enabled,
        workspaceMode: value.workspaceMode,
      );

  Future<AgentProfileSnapshot> detail(AgentProfileRead value) async {
    final row = await summary(value);
    return AgentProfileSnapshot(
      profileId: row.profileId,
      displayName: row.displayName,
      description: row.description,
      whenToUse: row.whenToUse,
      systemInstructions: await text(value.systemInstructions),
      accountId: row.accountId,
      modelId: row.modelId,
      effort: row.effort,
      source: row.source,
      revision: row.revision,
      contentHash: row.contentHash,
      system: row.system,
      enabled: row.enabled,
      workspaceMode: row.workspaceMode,
    );
  }

  Future<List<ProfileDiagnostic>> diagnostics(TypedListRef reference) async {
    final items = await readConfigurationList<ProfileDiagnosticRead>(
      reference,
      (offset) async {
        final page = await scope.diagnostics(
          reference.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    return List.unmodifiable([
      for (final item in items)
        ProfileDiagnostic(
          path: await text(item.path),
          message: await text(item.message),
        ),
    ]);
  }
}
