import 'acp_values.dart';

enum AcpContentRoleView { assistant, user }

final class AcpAnnotationsView {
  AcpAnnotationsView({
    Iterable<AcpContentRoleView>? audience,
    this.lastModified,
    this.priority,
    this.meta,
  }) : audience = audience == null ? null : List.unmodifiable(audience);
  final List<AcpContentRoleView>? audience;
  final String? lastModified;
  final double? priority;
  final AcpJsonObject? meta;
}

sealed class AcpContentBlockView {
  const AcpContentBlockView({this.annotations, this.meta});
  final AcpAnnotationsView? annotations;
  final AcpJsonObject? meta;
}

final class AcpTextContentView extends AcpContentBlockView {
  const AcpTextContentView({required this.text, super.annotations, super.meta});
  final String text;
}

final class AcpImageContentView extends AcpContentBlockView {
  const AcpImageContentView({
    required this.data,
    required this.mimeType,
    this.uri,
    super.annotations,
    super.meta,
  });
  final String data;
  final String mimeType;
  final String? uri;
}

final class AcpAudioContentView extends AcpContentBlockView {
  const AcpAudioContentView({
    required this.data,
    required this.mimeType,
    super.annotations,
    super.meta,
  });
  final String data;
  final String mimeType;
}

final class AcpResourceLinkView extends AcpContentBlockView {
  const AcpResourceLinkView({
    required this.name,
    required this.uri,
    this.description,
    this.mimeType,
    this.size,
    this.title,
    super.annotations,
    super.meta,
  });
  final String name;
  final String uri;
  final String? description;
  final String? mimeType;
  final BigInt? size;
  final String? title;
}

final class AcpEmbeddedResourceView extends AcpContentBlockView {
  const AcpEmbeddedResourceView({
    required this.resource,
    super.annotations,
    super.meta,
  });
  final AcpResourceContentsView resource;
}

sealed class AcpResourceContentsView {
  const AcpResourceContentsView({required this.uri, this.mimeType, this.meta});
  final String uri;
  final String? mimeType;
  final AcpJsonObject? meta;
}

final class AcpTextResourceContentsView extends AcpResourceContentsView {
  const AcpTextResourceContentsView({
    required this.text,
    required super.uri,
    super.mimeType,
    super.meta,
  });
  final String text;
}

final class AcpBlobResourceContentsView extends AcpResourceContentsView {
  const AcpBlobResourceContentsView({
    required this.blob,
    required super.uri,
    super.mimeType,
    super.meta,
  });
  final String blob;
}

enum AcpToolKindView {
  read,
  edit,
  delete,
  move,
  search,
  execute,
  think,
  fetch,
  switchMode,
  other,
}

enum AcpToolCallStatusView { pending, inProgress, completed, failed }

sealed class AcpToolCallContentView {
  const AcpToolCallContentView({this.meta});
  final AcpJsonObject? meta;
}

final class AcpToolContentView extends AcpToolCallContentView {
  const AcpToolContentView({required this.content, super.meta});
  final AcpContentBlockView content;
}

final class AcpToolDiffView extends AcpToolCallContentView {
  const AcpToolDiffView({
    required this.path,
    required this.newText,
    this.oldText,
    super.meta,
  });
  final String path;
  final String? oldText;
  final String newText;
}

final class AcpToolTerminalView extends AcpToolCallContentView {
  const AcpToolTerminalView({required this.terminalId, super.meta});
  final AcpTerminalId terminalId;
}

final class AcpToolCallLocationView {
  const AcpToolCallLocationView({required this.path, this.line, this.meta});
  final String path;
  final int? line;
  final AcpJsonObject? meta;
}

final class AcpToolCallView {
  AcpToolCallView({
    required this.toolCallId,
    required this.title,
    required this.kind,
    required this.status,
    this.name,
    Iterable<AcpToolCallContentView> content = const [],
    Iterable<AcpToolCallLocationView> locations = const [],
    this.rawInput,
    this.rawOutput,
    this.meta,
  }) : content = List.unmodifiable(content),
       locations = List.unmodifiable(locations);
  final AcpToolCallId toolCallId;
  final String title;
  final String? name;
  final AcpToolKindView kind;
  final AcpToolCallStatusView status;
  final List<AcpToolCallContentView> content;
  final List<AcpToolCallLocationView> locations;
  final AcpJsonValue? rawInput;
  final AcpJsonValue? rawOutput;
  final AcpJsonObject? meta;
}

final class AcpToolCallUpdateFieldsView {
  AcpToolCallUpdateFieldsView({
    this.kind,
    this.status,
    this.title,
    this.name,
    Iterable<AcpToolCallContentView>? content,
    Iterable<AcpToolCallLocationView>? locations,
    this.rawInput,
    this.rawOutput,
  }) : content = content == null ? null : List.unmodifiable(content),
       locations = locations == null ? null : List.unmodifiable(locations);
  final AcpToolKindView? kind;
  final AcpToolCallStatusView? status;
  final String? title;
  final String? name;
  final List<AcpToolCallContentView>? content;
  final List<AcpToolCallLocationView>? locations;
  final AcpJsonValue? rawInput;
  final AcpJsonValue? rawOutput;
}

final class AcpToolCallUpdateView {
  const AcpToolCallUpdateView({
    required this.toolCallId,
    required this.fields,
    this.meta,
  });
  final AcpToolCallId toolCallId;
  final AcpToolCallUpdateFieldsView fields;
  final AcpJsonObject? meta;
}
