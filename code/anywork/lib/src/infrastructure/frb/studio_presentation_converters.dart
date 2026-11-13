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
      startedAt: _exactSignedTimelineInt(value.startedAt),
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

LiveDisplayWindow _liveDisplayWindowFromFrb(
  frb_presentation.BridgeLiveDisplayWindow value,
) => LiveDisplayWindow(
  revision: _exactTimelineInt(value.revision, 'live display revision'),
  historyThrough: _exactTimelineInt(
    value.historyThrough,
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

TimelineBatch _timelineBatchFromFrb(
  frb_presentation.BridgeTimelineBatch value,
) {
  if (value.presentationVersion != presentationVersion) {
    throw ProtocolVersionMismatch(
      received: value.presentationVersion,
      supported: presentationVersion,
      field: 'presentationVersion',
    );
  }
  return TimelineBatch(
    presentationVersion: value.presentationVersion,
    placement: switch (value.placement) {
      frb_chat_types.BridgeChatPlacement.set_ => ChatPlacement.set,
      frb_chat_types.BridgeChatPlacement.prepend => ChatPlacement.prepend,
      frb_chat_types.BridgeChatPlacement.append => ChatPlacement.append,
    },
    blocks: [
      for (final block in value.blocks)
        DisplayBlock(
          id: block.id,
          historyPos: _exactTimelineInt(block.historyPos, 'display position'),
          body: _displayBodyFromFrb(block.body),
        ),
    ],
    before: value.before,
    fromPos: _exactNullableTimelineInt(value.fromPos, 'display prefix'),
    throughPos: _exactTimelineInt(value.throughPos, 'display prefix'),
    live: value.live == null ? null : _liveDisplayWindowFromFrb(value.live!),
  );
}

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
