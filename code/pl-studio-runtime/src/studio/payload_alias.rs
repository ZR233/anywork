//! 产品自有不透明载荷的旧字段改名边界。
//!
//! 只处理产品自己写入、且字段语义明确的载荷。转换严格限制在给定对象的已知键上：不递归
//! 改写厂商原始 JSON、opaque 内容或用户文本，也不为旧键保留运行期别名解析。

use anyhow::{Result, bail};
use serde_json::Value;

/// 把 `legacy` 键改名为 `current`；两键同时存在且值不同是持久化冲突。
///
/// 返回是否发生了改名，便于调用方决定是否需要重新序列化。
pub(crate) fn rename_key(
    object: &mut serde_json::Map<String, Value>,
    legacy: &str,
    current: &str,
) -> Result<bool> {
    let Some(value) = object.remove(legacy) else {
        return Ok(false);
    };
    match object.get(current) {
        Some(existing) if existing != &value => {
            bail!("conflicting persisted keys `{legacy}` and `{current}`")
        }
        Some(_) => Ok(true),
        None => {
            object.insert(current.to_string(), value);
            Ok(true)
        }
    }
}
