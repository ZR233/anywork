part of 'studio_api.dart';

DisplayBlockRef _displayBlockRefFromFrb(
  frb_presentation.BridgeDisplayBlockRef value,
) => DisplayBlockRef(databaseId: value.databaseId, blockId: value.blockId);

frb_presentation.BridgeDisplayBlockRef _displayBlockRefToFrb(
  DisplayBlockRef value,
) => frb_presentation.BridgeDisplayBlockRef(
  databaseId: value.databaseId,
  blockId: value.blockId,
);

frb_presentation.BridgeDisplayMemberWindow _displayMemberWindowToFrb(
  DisplayMemberWindow value,
) => switch (value) {
  LatestDisplayMembers() =>
    const frb_presentation.BridgeDisplayMemberWindow.latest(),
  BeforeDisplayMembers(:final memberOrder) =>
    frb_presentation.BridgeDisplayMemberWindow.before(
      memberOrder: BigInt.from(memberOrder),
    ),
};

WorkTiming _workTimingFromFrb(frb_presentation.BridgeWorkTiming value) =>
    WorkTiming(
      startedAt: value.startedAt == null
          ? null
          : _exactSignedTimelineInt(value.startedAt!),
      finishedAt: value.finishedAt == null
          ? null
          : _exactSignedTimelineInt(value.finishedAt!),
    );

DisplayRecord _displayRecordFromFrb(
  frb_presentation.BridgeDisplayRecord value,
) => DisplayRecord(
  atom: _chatAtomFromFrb(value.atom),
  startFact: value.startFact == null
      ? null
      : _chatPositionFromFrb(value.startFact!),
  endFact: value.endFact == null ? null : _chatPositionFromFrb(value.endFact!),
  contentSource: switch (value.contentSource) {
    frb_presentation.BridgeDisplayContentSource_CurrentAtom() =>
      const CurrentAtom(),
    frb_presentation.BridgeDisplayContentSource_FrozenObservation(
      :final capturedAt,
      :final available,
    ) =>
      FrozenObservation(
        capturedAt: capturedAt == null
            ? null
            : _exactSignedTimelineInt(capturedAt),
        available: available,
      ),
    frb_presentation.BridgeDisplayContentSource_CompletedOriginal(
      :final completionId,
    ) =>
      CompletedOriginal(completionId: completionId),
  },
);

DisplayBlockBody _displayBodyFromFrb(
  frb_presentation.BridgeDisplayBlockBody value,
) => switch (value) {
  frb_presentation.BridgeDisplayBlockBody_Work(:final timing, :final members) =>
    WorkDisplayBlock(
      timing: _workTimingFromFrb(timing),
      members: _displayBlockRefFromFrb(members),
    ),
  frb_presentation.BridgeDisplayBlockBody_Single(
    :final record,
    :final visibility,
  ) =>
    SingleDisplayBlock(
      record: _displayRecordFromFrb(record),
      visibility: switch (visibility) {
        frb_presentation.BridgeSingleVisibility.content =>
          SingleVisibility.content,
        frb_presentation.BridgeSingleVisibility.finalEmptyAfterContent =>
          SingleVisibility.finalEmptyAfterContent,
      },
    ),
};

TailSnapshot _tailSnapshotFromFrb(
  frb_presentation.BridgeTailSnapshot value,
) => TailSnapshot(
  revision: _exactTimelineInt(value.revision, 'view revision'),
  layoutRevision: _exactTimelineInt(value.layoutRevision, 'layout revision'),
  readyFrontier: _exactTimelineInt(
    value.readyFrontier,
    'display history prefix',
  ),
  executionPresent: value.executionPresent,
  currentWorkId: value.currentWorkId,
  blocks: [
    for (final block in value.blocks)
      LiveDisplayBlock(
        id: block.id,
        blockOrder: _exactTimelineInt(block.blockOrder, 'live block order'),
        source: block.source == null ? null : _chatSourceFromFrb(block.source!),
        body: _displayBodyFromFrb(block.body),
        hasUnfinishedMembers: block.hasUnfinishedMembers,
        thinkingSummary: block.thinkingSummary,
        state: switch (block.state) {
          frb_presentation.BridgeDisplayBlockState.open =>
            DisplayBlockState.open,
          frb_presentation.BridgeDisplayBlockState.sealed =>
            DisplayBlockState.sealed,
        },
      ),
  ],
  older: value.older,
);

OpenTimeline _openTimelineFromFrb(frb_presentation.BridgeOpenTimeline value) =>
    OpenTimeline(
      readerId: value.readerId,
      presentationVersion: value.presentationVersion,
      readerProtocolVersion: value.readerProtocolVersion,
      initialCursor: ViewCursor(value.initialCursor),
    );
List<DisplayBlock> _displayBlocksFromFrb(
  List<frb_presentation.BridgeDisplayBlock> values,
) => [
  for (final value in values)
    DisplayBlock(
      id: value.id,
      blockOrder: _exactTimelineInt(value.blockOrder, 'block order'),
      body: _displayBodyFromFrb(value.body),
    ),
];
TimelinePage _timelinePageFromFrb(frb_presentation.BridgeTimelinePage value) =>
    TimelinePage(
      presentationVersion: value.presentationVersion,
      databaseId: value.databaseId,
      ceiling: _exactTimelineInt(value.ceiling, 'history ceiling'),
      blocks: _displayBlocksFromFrb(value.blocks),
      before: value.before,
    );
ViewUpdate _viewUpdateFromFrb(
  frb_presentation.BridgeViewUpdate value,
) => ViewUpdate(
  presentationVersion: value.presentationVersion,
  readerProtocolVersion: value.readerProtocolVersion,
  after: ViewCursor(value.after),
  next: ViewCursor(value.next),
  history: HistoryDelta(
    placement: switch (value.history.placement) {
      frb_presentation.BridgeHistoryPlacement.set_ => HistoryPlacement.set,
      frb_presentation.BridgeHistoryPlacement.append => HistoryPlacement.append,
    },
    fromOrder: _exactNullableTimelineInt(
      value.history.fromOrder,
      'history start',
    ),
    throughOrder: _exactTimelineInt(value.history.throughOrder, 'history end'),
    blocks: _displayBlocksFromFrb(value.history.blocks),
    before: value.history.before,
  ),
  tail: switch (value.tail) {
    frb_presentation.BridgeTailUpdate_Keep() => const KeepTail(),
    frb_presentation.BridgeTailUpdate_Replace(:final snapshot) => ReplaceTail(
      snapshot: _tailSnapshotFromFrb(snapshot),
    ),
    frb_presentation.BridgeTailUpdate_Status(
      :final baseLayoutRevision,
      :final revision,
      :final currentWorkId,
      :final thinkingSummary,
    ) =>
      TailStatus(
        baseLayoutRevision: _exactTimelineInt(
          baseLayoutRevision,
          'base layout revision',
        ),
        revision: _exactTimelineInt(revision, 'view revision'),
        currentWorkId: currentWorkId,
        thinkingSummary: thinkingSummary,
      ),
  },
);

DisplayMemberPage _displayMemberPageFromFrb(
  frb_presentation.BridgeDisplayMemberPage value,
) => DisplayMemberPage(
  block: _displayBlockRefFromFrb(value.block),
  revision: _exactTimelineInt(value.revision, 'display member revision'),
  sealed: value.sealed,
  entries: [
    for (final member in value.entries)
      DisplayMemberHead(
        memberKey: member.memberKey,
        memberOrder: _exactTimelineInt(
          member.memberOrder,
          'display member order',
        ),
        record: _displayRecordFromFrb(member.record),
      ),
  ],
  before: _exactNullableTimelineInt(value.before, 'display member boundary'),
);
