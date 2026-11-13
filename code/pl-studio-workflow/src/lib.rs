//! 工作模式注册、状态图与计划的领域逻辑。
//!
//! 状态转换由显式输入驱动；不读取配置、创建线程或持有数据库与工具运行时。
pub mod mode;
pub mod plan;

#[cfg(test)]
mod test_support;
