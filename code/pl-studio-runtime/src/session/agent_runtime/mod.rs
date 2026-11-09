//! 具体执行后端运行时。ACP 在分配前拒绝，这里只有 Native 组合。
mod native;
mod resources;

pub(crate) use native::NativeThreadRuntime;
pub(crate) use resources::NativeResources;
