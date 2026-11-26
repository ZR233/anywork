import 'dart:typed_data';

import 'collection_equality.dart';

enum SessionDetailKind {
  plan,
  interactions,
  todo,
  workflow,
  activeSkills,
  activeMcpServers,
  activeLspServers,
}

/// An immutable byte window read from the owning conversation feed.
final class SessionDetailWindow {
  SessionDetailWindow({
    required this.ownerEpoch,
    required this.revision,
    required this.offset,
    required this.totalBytes,
    required List<int> bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final String ownerEpoch;
  final int revision;
  final int offset;
  final int totalBytes;
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionDetailWindow &&
          ownerEpoch == other.ownerEpoch &&
          revision == other.revision &&
          offset == other.offset &&
          totalBytes == other.totalBytes &&
          listEquals(bytes, other.bytes);

  @override
  int get hashCode => Object.hash(
    ownerEpoch,
    revision,
    offset,
    totalBytes,
    Object.hashAll(bytes),
  );
}
