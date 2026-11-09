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

WorkSummary _workSummaryFromFrb(frb_presentation.BridgeWorkSummary value) =>
    WorkSummary(
      total: _exactTimelineInt(value.total, 'work total'),
      terminal: _exactTimelineInt(value.terminal, 'work terminal'),
      running: _exactTimelineInt(value.running, 'work running'),
      waiting: _exactTimelineInt(value.waiting, 'work waiting'),
      failed: _exactTimelineInt(value.failed, 'work failed'),
      cancelled: _exactTimelineInt(value.cancelled, 'work cancelled'),
      transferred: _exactTimelineInt(value.transferred, 'work transferred'),
      startedAt: value.startedAt == null
          ? null
          : _exactSignedTimelineInt(value.startedAt!),
      finishedAt: value.finishedAt == null
          ? null
          : _exactSignedTimelineInt(value.finishedAt!),
      durationMs: _exactNullableTimelineInt(value.durationMs, 'work duration'),
      thinkingSummary: value.thinkingSummary,
      thinkingContent: value.thinkingContent == null
          ? null
          : _contentRefFromFrb(value.thinkingContent!),
    );

DisplayBlockBody _displayBodyFromFrb(
  frb_presentation.BridgeDisplayBlockBody value,
) => switch (value) {
  frb_presentation.BridgeDisplayBlockBody_Work(
    :final summary,
    :final members,
  ) =>
    WorkDisplayBlock(
      summary: _workSummaryFromFrb(summary),
      members: _displayBlockRefFromFrb(members),
    ),
  frb_presentation.BridgeDisplayBlockBody_Single(
    :final atom,
    :final completionId,
  ) =>
    SingleDisplayBlock(
      atom: _chatAtomFromFrb(atom),
      completionId: completionId,
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
  blocks: [
    for (final block in value.blocks)
      LiveDisplayBlock(
        id: block.id,
        blockOrder: _exactTimelineInt(block.blockOrder, 'live block order'),
        body: _displayBodyFromFrb(block.body),
        closing: block.closing,
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
        atom: _chatAtomFromFrb(member.atom),
        completionId: member.completionId,
      ),
  ],
  before: _exactNullableTimelineInt(value.before, 'display member boundary'),
);
