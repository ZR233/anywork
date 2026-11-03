/// Non-release observation RPC names shared with pure Dart host tools.
///
/// The layout endpoint is read-only. UI actions use the official Flutter Driver
/// extension, never a custom control message or a second presentation model.
const String kCaptureExtensionName = 'ext.anywork.capture';
const String kRequestExitExtensionName = 'ext.anywork.requestExit';
const String kTimelineLayoutExtensionName = 'ext.anywork.timelineLayout';
