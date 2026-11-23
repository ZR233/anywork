import 'dart:convert';

import 'package:anywork_client/models.dart';

import '../tool_item_adapter.dart';
import 'tool_detail_values.dart';

/// Per-item controller that tracks server/tool acceptance projections across
/// inline output, validated full-prefix declared output windows, and
/// callback epoch retirements.
class AcceptanceToolController extends TimelineToolItemController {
  AcceptanceToolController(super.item, {required this.decoder});

  final ToolAcceptanceProjection Function(String text) decoder;

  ToolAcceptanceProjection? _windowAcceptance;

  @override
  ToolAcceptanceProjection? get acceptance {
    final inline = decoder(item.output);
    return inline.state != ToolAcceptance.pending
        ? inline
        : _windowAcceptance ?? inline;
  }

  @override
  void onAcceptedOutputWindow(ContentWindow window) {
    final ToolAcceptanceProjection projection;
    try {
      projection = decoder(utf8.decode(window.bytes));
    } on FormatException {
      return;
    }
    final previous = _windowAcceptance;
    if (previous?.state == projection.state &&
        previous?.code == projection.code &&
        previous?.reason == projection.reason) {
      return;
    }
    _windowAcceptance = projection;
    notifyListeners();
  }

  @override
  void onRetireTransientState() {
    super.onRetireTransientState();
    _windowAcceptance = null;
  }
}
