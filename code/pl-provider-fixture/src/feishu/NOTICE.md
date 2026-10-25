# Feishu fixture wire notice

This environment crate includes typed samples derived from the MIT-licensed
official Node SDK `larksuite/node-sdk` revision
`b188be60134d409b61259546bcf69c731d2b0b7c` (npm 1.76.0 gitHead
`1889911f0841e669de0be5bd02c737a3f1fd20fa`):

- `scene/registration/addons.ts` gzip + base64url pipeline
- `ws-client/enum.ts` FrameType / HeaderKey / MessageType / ErrorCode
- `ws-client/proto-buf/pbbp2.js` Header and Frame field numbers

The SDK is not vendored. Official HTTP paths follow Feishu Open Platform
China docs (`https://open.feishu.cn`).

Copyright (c) 2022 Lark Technologies Pte. Ltd. The complete MIT permission
and warranty notice for this fixed reference is retained in
[`pl-studio-runtime/THIRD_PARTY_NOTICES.md`](../../../pl-studio-runtime/THIRD_PARTY_NOTICES.md).

## Resource peer contract

The resource samples independently follow the official [file upload API](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/im-v1/file/create),
[send content](https://open.feishu.cn/document/server-docs/im-v1/message-content-description/create_json),
and [receive content](https://open.feishu.cn/document/server-docs/im-v1/message-content-description/receive_json)
contracts. `lark-cli` 1.0.98 `schema im.files.create` was also inspected statically:
its bot upload scope is `im:resource:upload`. The CLI's alternatives do not
independently dictate the registration template: this peer also retains the
existing `im:resource` receiving capability and main's `cardkit:card:write`.
No real platform, CLI account or credential is used by this peer.

- `FeishuControl::register_resource(media::SyntheticResource)` registers one
  nonempty byte sequence with an immutable key, message identity, kind, name and
  MIME header. It emits no event. `EventBody::{Image, File, Audio, Media, Post}`
  create official receive JSON independently. `Post(ReceivedPost)` has no
  send-side locale wrapper; `Raw` is explicit opaque wire, not a product support
  decision. A post's image/media keys can reference separately registered bytes.
- `GET /open-apis/im/v1/messages/{message_id}/resources/{file_key}?type=image|file`
  requires the exact binding; audio/media use `file`. It returns original bytes,
  Content-Type and UTF-8 Content-Disposition. Uploaded bytes gain a message
  binding only when that file message is accepted by the peer.
- `POST /open-apis/im/v1/files` uses Axum Multipart and validates exactly one
  `file_type`, `file_name`, `file`, plus optional nonnegative `duration`.
  The official `opus|mp4|pdf|doc|xls|ppt|stream` enum is accepted without codec
  inspection or transcoding. Empty, missing, duplicate, unknown and oversized
  fields are rejected. A successful upload stores bytes but sends no message.
- Message send preserves legacy nonempty `text`, a typed `zh_cn` post sample
  with `md`/`text` nodes (including a mixed paragraph), the supported opaque
  RichPost wire, `interactive` CardKit references, and `file` with only a
  peer-uploaded `file_key`. Both post representations first use the same
  documented node-field and paragraph validation; choosing the typed sample
  adds no layout restriction. Paragraphs may mix supported nodes; only `img`
  and `media` require independent paragraphs. Typed observations preserve node
  order/text, while broader validated RichPost observations retain original
  wire without interpretation. This is not a claim to implement every locale,
  arbitrary opaque posts without `md`, or the whole outbound rich-text grammar.
  The **entire encoded HTTP JSON body** is limited to 30,000 bytes.
  Send/history/read responses for ordinary messages use received content
  objects. Posts retain original paragraphs in `content_v2`; the legacy sample
  presents Markdown as plain text without rendering or claiming platform layout
  equivalence. Accepted sends are observable via history and
  `GET /open-apis/im/v1/messages/{message_id}`.
- `media::{UploadDisposition, ResourceDownloadDisposition}` scripts are separate
  from `SendDisposition`. A validated upload selects one step, then `Hang` waits
  before storage; explicit release succeeds and shutdown stores nothing.
  `AcceptThenDrop` stores bytes and breaks the response, without inventing message
  success. Download `Disconnect` breaks a body after a bounded planned prefix.
  Replacing future scripts does not release existing hangs; rearming a media hang
  with waiters is rejected. Early explicit releases are retained by the existing
  generation/watch predicate. Message-send lost responses keep the existing
  timeout/lost-response stimulus and do not implement permanent UUID deduplication.

Limits are independent fixture policy: 30,000,000 bytes per resource/file,
64 retained keys, 120,000,000 retained bytes, four concurrent media handlers,
512 media requests and 512 message requests per peer lifetime, 64 media fault
steps, 1,024-byte names/metadata fields, and a 15-second multipart receive
deadline. The whole multipart body is capped at 30,065,536 bytes, reserving
65,536 bytes for framing above the independently enforced file-component limit.
No eviction/overwrite hides a previously registered or uploaded key. Shutdown
closes admission and cancels receive/hang futures before joining the listener.

`FeishuReport` contains `uploads`, `resourceDownloads`, `messageSends`, sorted
`resources`, and `mediaStatus`. `callIndex` links typed observations to the
ordered call list; names/identity/length/SHA-256 are safe synthetic environment
facts, never file bodies or bearer tokens. `StoredResponseDropped` distinguishes
platform storage from a successful response. `ResponsePrepared` and
`preparedBytes` describe planned peer bytes, **not proof of client delivery**.
These facts never decide product admission, tools, chat-to-thread mapping,
Succeeded/Partial/Unknown, real tenant compatibility or client rendering.

## Fixed-main integration

The integrated namespace keeps main's CardKit create/element/settings routes,
per-card serialization, positive-int32 shared sequence, UUID replay/conflict,
one-time IM publication, expiry, faults and complete `entity_json` observations.
The same official element route may update any markdown element actually
registered in that card. No element name carries special host semantics. Element
ids follow JSON 2.0's ASCII letter-led, letter/digit/underscore, 20-byte rule;
content UUID identity includes the target element and sequence, and settings
identity includes its sequence. Equal text on another element or a changed
sequence cannot masquerade as a replay (including an out-of-int32 sequence).
The first markdown element remains the
`CardEntityReport.content` summary; `entity_json` preserves every element.

CardKit's independent platform entity limit remains 30 KiB and content limit
100,000 characters. Product policy (4,000 scalars, conservative 30,000-byte
requests, 200 ms pacing, truncation notices and independent host status) is not
implemented by this peer. Platform facts stay inspectable for D2 to judge.
No automatic transcript, chunking, filtering, history-save or delivery claim is
introduced here. Rejected/cancelled ordinary sends have no assigned platform
message identity and are not counted as successful per-chat QPS effects.

The default independent scope sample has eight scopes: the five granular IM
capabilities, `im:resource`, `im:resource:upload`, and `cardkit:card:write`; it
does not add broad `im:message` or `im:message.group_msg`.

`FeishuControl::set_file_message_key_mode(media::FileMessageKeyMode::MessageScoped)`
makes later accepted file messages expose a distinct message-scoped readback key.
`PreserveUploadKey` remains the default. Download verifies the exact message/key
binding and resolves the alias to the same retained original bytes; it does not
duplicate file storage or change the upload-key identity in safe summaries.
The aliases are bounded by the existing 512 message-request lifetime budget.
`MessageContentObservation::RichPost { content, md_text }` preserves main's
documented rich-post wire outside the small typed md/text sample without
expanding product DTOs or rendering Markdown.

ACK numeric narrowing uses checked int32 conversion: malformed/out-of-range
codes remain `None`, and `200 + 2^32` cannot become a successful `Some(200)`.
