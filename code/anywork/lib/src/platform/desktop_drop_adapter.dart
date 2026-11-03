import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import 'dropped_file.dart';

/// Converts a plugin drop event into application-neutral file transfers.
List<DroppedFileTransfer> droppedFilesFromDetails(DropDetails details) {
  return [
    for (final item in details.items.whereType<DropFileItem>())
      DroppedFileTransfer(
        name: item.name,
        localPath: item.localPath,
        openRead: item.localPath == null || item.localPath!.isEmpty
            ? () => item.file.openRead()
            : null,
      ),
  ];
}

/// Production drop surface. Views consume [DroppedFileTransfer] instead.
class DesktopFileDropTarget extends StatelessWidget {
  const DesktopFileDropTarget({
    required this.enabled,
    required this.onEnter,
    required this.onLeave,
    required this.onDrop,
    required this.child,
    super.key,
  });

  final bool enabled;
  final VoidCallback onEnter;
  final VoidCallback onLeave;
  final ValueChanged<List<DroppedFileTransfer>> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enabled: enabled,
      acceptedKinds: const {DropItemKind.file},
      onEnter: (_) => onEnter(),
      onLeave: onLeave,
      onDrop: (details) => onDrop(droppedFilesFromDetails(details)),
      child: child,
    );
  }
}
