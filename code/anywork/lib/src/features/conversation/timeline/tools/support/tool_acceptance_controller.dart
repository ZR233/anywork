import '../tool_item_adapter.dart';
import '../../state/tool_data_artifact.dart';
import 'tool_detail_values.dart';

/// Per-item controller that tracks server/tool acceptance projections across
/// inline output, validated full-prefix declared output windows, and
/// callback epoch retirements.
class AcceptanceToolController extends TimelineToolItemController {
  AcceptanceToolController(super.item, {required this.decoder});

  final ToolAcceptanceProjection Function(ToolDataArtifact data) decoder;

  @override
  ToolAcceptanceProjection? get acceptance {
    return decoder(toolData);
  }
}
