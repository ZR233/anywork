import '../../models/studio_enums.dart';

/// 工作模式目录的只读投影：revision 与全量描述符列表。
class ThreadModeCatalogView {
  const ThreadModeCatalogView({this.revision = 0, this.modes = const []});

  final int revision;
  final List<ThreadModeDescriptorView> modes;
}

class ThreadModeDescriptorView {
  const ThreadModeDescriptorView({
    required this.id,
    required this.displayName,
    required this.description,
    required this.order,
    required this.hasWorkflow,
    this.readOnly = false,
  });

  final String id;
  final String displayName;
  final String description;
  final int order;
  final bool hasWorkflow;
  final bool readOnly;

  ThreadModeId get mode => ThreadModeId.fromId(id);
}
