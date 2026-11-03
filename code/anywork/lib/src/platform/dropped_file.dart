/// Application-neutral file transfer from a drop or picker.
///
/// Views never import desktop_drop. A local path is used when the OS already
/// materialized the file; otherwise [openRead] keeps the transfer alive until
/// Rust copies it into a draft.
final class DroppedFileTransfer {
  const DroppedFileTransfer({
    required this.name,
    this.localPath,
    this.openRead,
  });

  final String name;
  final String? localPath;
  final Stream<List<int>> Function()? openRead;
}
