import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../presentation/view_models/timeline_session_owner.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_feed_projection.dart';
import '../state/timeline_image_resources.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/timeline_content_range_view.dart';
import 'timeline_media_connector.dart';

/// The expanded row lends its producer-defined range to the original feed.
class CompletionRunConnector extends StatefulWidget {
  const CompletionRunConnector({
    super.key,
    required this.unit,
    required this.content,
    required this.images,
    this.readAttachment,
    this.bodyBuilder,
    this.monotonicMicros,
    this.onContentLayout,
  });

  final TimelineDisplayUnit unit;
  final TimelineDisplayLease content;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String)? readAttachment;
  final Widget Function(String, String)? bodyBuilder;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;

  @override
  State<CompletionRunConnector> createState() => _MembersState();
}

class _MembersState extends State<CompletionRunConnector>
    implements TimelineGroupDisplay {
  VoidCallback? _unregister;
  Future<List<WorkGroupMember>>? _load;
  AsyncSnapshot<List<WorkGroupMember>> _snapshot =
      const AsyncSnapshot.nothing();

  @override
  TimelineWorkGroup? get group => widget.unit.body.feedGroup;

  @override
  void initState() {
    super.initState();
    _unregister = widget.content.registerGroupDisplay(this);
    _request();
  }

  @override
  void didUpdateWidget(CompletionRunConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.content, widget.content)) {
      _unregister?.call();
      _unregister = widget.content.registerGroupDisplay(this);
    }
    final previous = oldWidget.unit.body.feedGroup;
    if (previous != group || !identical(oldWidget.content, widget.content)) {
      _request();
    }
  }

  void _request() {
    final group = this.group;
    _snapshot = const AsyncSnapshot.nothing();
    _load = group == null ? null : widget.content.loadWorkGroupMembers(group);
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  @override
  String get unitId => widget.unit.id;
  @override
  bool get isCurrent =>
      mounted && widget.content.canRead && widget.unit.expansion.bodyActive;
  @override
  bool get loading => _snapshot.connectionState == ConnectionState.waiting;
  @override
  Object? get error => _snapshot.error;
  @override
  Iterable<WorkGroupMember> get members =>
      isCurrent ? _snapshot.data ?? const [] : const [];

  @override
  Widget build(BuildContext context) => FutureBuilder<List<WorkGroupMember>>(
    future: _load,
    builder: (context, snapshot) {
      _snapshot = snapshot;
      if (!isCurrent) return const SizedBox.shrink();
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const LinearProgressIndicator(minHeight: 1);
      }
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(_request),
          child: Text(snapshot.error.toString()),
        );
      }
      return TimelineBodyReadIntent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final member in snapshot.data ?? const <WorkGroupMember>[])
              _member(member),
          ],
        ),
      );
    },
  );

  Widget _member(WorkGroupMember member) {
    final item = timelineFeedMember(member);
    final read = widget.readAttachment;
    return ChatItemView(
      key: ValueKey(member.id),
      item: item,
      bodyBuilder: widget.bodyBuilder,
      isDisplayActive: () => isCurrent,
      monotonicMicros: widget.monotonicMicros,
      onContentLayout: widget.onContentLayout,
      attachmentBuilder: read == null
          ? null
          : (item) => TimelineAttachmentsConnector(
              item: item,
              resources: widget.images,
              readAttachment: read,
              isActive: () => isCurrent,
            ),
    );
  }
}
