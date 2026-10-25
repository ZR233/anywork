// `BridgeError` 是 FRB/FFI 边界的错误契约：其形状由生成的 Dart 镜像类型决定，
// 装箱会改变对外 FFI 表面，因此在该 crate 内放宽“错误变体过大”的告警。
// 协议侧共享错误 `StudioError` 已通过装箱 `details` 收敛体积。
#![allow(clippy::result_large_err)]
// 桥接 DTO 的 `Bridge*Event` 枚举是 FRB 逐字段镜像的 FFI 契约，装箱会改变生成的 Dart
// 类型形状；这些枚举的体积差异来自协议侧事件变体，因此在该 crate 内放宽同一告警。
#![allow(clippy::large_enum_variant)]

pub mod api;
mod desktop_instance;
mod diagnostics;
mod read_owner;

pub use pl_protocol::ThreadSubscriptionUpdate;

#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub mod frb_generated;
