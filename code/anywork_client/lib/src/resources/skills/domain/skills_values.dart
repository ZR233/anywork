import 'package:freezed_annotation/freezed_annotation.dart';

part 'skills_values.freezed.dart';

enum SkillSource { project, user, system, external }

@freezed
abstract class SkillInvocationPolicy with _$SkillInvocationPolicy {
  const factory SkillInvocationPolicy({
    required bool modelInvocable,
    required bool userInvocable,
  }) = _SkillInvocationPolicy;
}

@Freezed(toStringOverride: false)
sealed class SkillResourceBase with _$SkillResourceBase {
  const factory SkillResourceBase.directory({required String path}) =
      DirectorySkillResourceBase;
  const factory SkillResourceBase.url({required String url}) =
      UrlSkillResourceBase;
  const factory SkillResourceBase.opaque({required String description}) =
      OpaqueSkillResourceBase;
}

@Freezed(toStringOverride: false)
final class SkillSummary with _$SkillSummary {
  SkillSummary({
    required this.name,
    required this.description,
    required this.category,
    required List<String> platforms,
    required this.source,
    required this.providerId,
    required this.invocation,
    required this.resourceBase,
  }) : platforms = List.unmodifiable(platforms);
  final String name;
  final String description;
  final String? category;
  final List<String> platforms;
  final SkillSource source;
  final String providerId;
  final SkillInvocationPolicy invocation;
  final SkillResourceBase resourceBase;
}

@Freezed(toStringOverride: false)
final class SkillCatalogValue with _$SkillCatalogValue {
  SkillCatalogValue({
    required this.projectDir,
    required List<SkillSummary> skills,
    required List<String> warnings,
    required this.complete,
  }) : skills = List.unmodifiable(skills), warnings = List.unmodifiable(warnings);
  final String projectDir;
  final List<SkillSummary> skills;
  final List<String> warnings;
  final bool complete;
}

@Freezed(toStringOverride: false)
abstract class SkillsValue with _$SkillsValue {
  const factory SkillsValue({
    required String projectId,
    required String configFingerprint,
    required int catalogRevision,
    required SkillCatalogValue catalog,
  }) = _SkillsValue;
}

@Freezed(toStringOverride: false)
final class SkillSearchResult with _$SkillSearchResult {
  SkillSearchResult({
    required this.projectId,
    required this.catalogRevision,
    required List<SkillSummary> matches,
    required this.truncated,
  }) : matches = List.unmodifiable(matches);
  final String projectId;
  final int catalogRevision;
  final List<SkillSummary> matches;
  final bool truncated;
}
