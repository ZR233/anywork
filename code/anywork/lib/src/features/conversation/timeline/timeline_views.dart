/// Pure timeline presentation boundary.
///
/// This library intentionally exports no Connector, repository, client,
/// Provider, AppGraph or native bridge.
library;

export 'live_status/live_status_header_spec.dart';
export 'live_status/live_status_machine.dart';
export 'live_status/live_status_state.dart';
export 'live_status/live_status_surface_view.dart';
export 'state/chat_item_presentation.dart';
export 'state/chat_payload_reading.dart'
    show
        DecodedToolCard,
        ToolCardReading,
        ToolCardUnavailableKind,
        UnavailableToolCard;
export 'state/timeline_ui_controllers.dart';
export 'state/timeline_view_state.dart';
export 'state/tool_presentation.dart';
export 'views/plan_detail_view.dart';
export 'views/timeline_view.dart';
export 'widgets/chat_item_view.dart';
export 'widgets/completion_run_view.dart';
export 'widgets/conversation_activity_bar.dart';
export 'widgets/conversation_current_views.dart';
export 'widgets/timeline_activity_row.dart';
export 'widgets/timeline_reasoning_view.dart';
export 'widgets/timeline_work_group_shell.dart';
export 'widgets/timeline_attachments_view.dart';
export 'widgets/timeline_children_view.dart';
export 'widgets/timeline_compacting_zip_icon.dart';
export 'widgets/timeline_content_range_view.dart';
export 'widgets/timeline_image_view.dart';
export 'widgets/timeline_markdown.dart';
export 'widgets/timeline_plain_text.dart';
export 'tools/support/tool_detail_panel.dart';
export 'tools/support/tool_detail_values.dart';
export 'tools/tool_item_adapter.dart';
export 'tools/tool_item_registry.dart';
export 'tools/tool_item_view.dart';
export 'widgets/timeline_wait_blocks.dart';
