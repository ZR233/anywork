import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/skills_values.dart';

part 'skills_reads.freezed.dart';

@Freezed(toStringOverride: false)
abstract class SkillCatalogRead with _$SkillCatalogRead {
  const factory SkillCatalogRead({required ReadText projectDir, required TypedListRef skills,
    required TypedListRef warnings, required bool complete}) = _SkillCatalogRead;
}

@Freezed(toStringOverride: false)
abstract class SkillsReadHeader with _$SkillsReadHeader {
  const factory SkillsReadHeader({required ReadText projectId, required ReadText configFingerprint,
    required int catalogRevision, required SkillCatalogRead catalog}) = _SkillsReadHeader;
}

@freezed
abstract class SkillInvocationPolicyRead with _$SkillInvocationPolicyRead {
  const factory SkillInvocationPolicyRead({required bool modelInvocable,
    required bool userInvocable}) = _SkillInvocationPolicyRead;
}

@Freezed(toStringOverride: false)
sealed class SkillResourceBaseRead with _$SkillResourceBaseRead {
  const factory SkillResourceBaseRead.directory({required ReadText path}) = DirectorySkillResourceBaseRead;
  const factory SkillResourceBaseRead.url({required ReadText url}) = UrlSkillResourceBaseRead;
  const factory SkillResourceBaseRead.opaque({required ReadText description}) = OpaqueSkillResourceBaseRead;
}

@Freezed(toStringOverride: false)
abstract class SkillSummaryRead with _$SkillSummaryRead {
  const factory SkillSummaryRead({required ReadText name, required ReadText description,
    required ReadText? category, required TypedListRef platforms, required SkillSource source,
    required ReadText providerId, required SkillInvocationPolicyRead invocation,
    required SkillResourceBaseRead resourceBase}) = _SkillSummaryRead;
}

@Freezed(toStringOverride: false)
abstract class SkillsEntityRead with _$SkillsEntityRead {
  const factory SkillsEntityRead({required ProductEntityRef reference,
    required SkillSummaryRead value}) = _SkillsEntityRead;
}

@freezed
final class SkillsEntryPage with _$SkillsEntryPage {
  SkillsEntryPage({required this.collection, required this.offset,
    required List<ProductEntityRef> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class SkillSummaryReadPage with _$SkillSummaryReadPage {
  SkillSummaryReadPage({required this.listId, required this.offset, required this.total,
    required List<SkillSummaryRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<SkillSummaryRead> items;
  final int? nextOffset;
}
