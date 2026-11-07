# pl-agent-tool

独立的可执行工具声明与消费接口。基础消费方只需此 crate，不依赖 Anywork 的
core/model/protocol/Studio、RMCP、Tokio 或网络运行时。MCP 服务端继续使用其原有 SDK；
Anywork 的 MCP client adapter 与原生工具通过相同宿主端点被调用。

| 特性 | 内容 |
| --- | --- |
| 无默认特性 | `ToolDefinition`、`InputFormat`、`DefinitionError`、`JsonValue`、`Tool`、`ToolHandle` |
| `typed` | `typed::TypedTool`、schema 准备、原文 JSON 解码及静态作者适配 |
| `macros` | 包含 `typed`，增加 `#[tool_args]`、`#[tool]` 薄宏 |

独立下游 fixture 不加入工作区，以避免特性合并掩盖依赖边界。从仓库根运行：

```powershell
cargo test --locked --manifest-path code/pl-agent-tool/fixtures/downstream/Cargo.toml --target-dir target/tool-downstream
```

构建缓存显式留在根 `target/`，不写入 fixture 源码目录；此入口同时验证重命名依赖、
无直接 Serde/Schemars 依赖、泛型关闭转发与不支持形状的编译诊断。

## 消费方

应用在组合入口固定输入、上下文、输出与错误类型。业务值不会被通用接口擦除为 JSON
或错误字符串；只在 `ToolHandle::new` 中擦除工具实现并装箱返回的 future。

```rust
use std::error::Error;
use pl_agent_tool::ToolHandle;

pub async fn invoke<I, C, O, E>(
    tool: &ToolHandle<I, C, O, E>,
    input: I,
    context: C,
) -> Result<O, E>
where
    I: Send + 'static,
    C: Send + 'static,
    O: Send + 'static,
    E: Error + Send + Sync + 'static,
{
    tool.execute(input, context).await
}
```

`Tool` 使用拥有型参数和 RPITIT + Send，不要求工具、上下文或输出实现 Debug。
Handle 不可 Clone，也不实现 Tool；调用方不要再次擦除它。owner 停止准入并等待全部在途调用后
显式 close，失败保留原实例安全重试。库不维护 registry、任务、取消或退休状态，不在 Drop
启动异步关闭。

## typed 作者

普通作者只编写参数、业务状态、输出/错误与业务方法。启用 `macros` 后：

```rust
#[pl_agent_tool::tool_args]
#[serde(deny_unknown_fields)]
pub struct AddArgs {
    pub left: i64,
    pub right: i64,
}

pub struct Sum {
    pub value: i64,
}

#[derive(Debug, thiserror::Error)]
#[error("integer addition overflow")]
pub struct AddError;

pub struct Add {
    offset: i64,
}

#[pl_agent_tool::tool(name = "add")]
impl Add {
    /// 将两个整数与工具固定的偏移相加。
    async fn execute(&self, args: AddArgs, _context: ()) -> Result<Sum, AddError> {
        let value = args.left.checked_add(args.right)
            .and_then(|sum| sum.checked_add(self.offset))
            .ok_or(AddError)?;
        Ok(Sum { value })
    }
}

pub fn add_tool(offset: i64) -> Result<
    pl_agent_tool::ToolHandle<
        String, (), Sum, pl_agent_tool::typed::InvocationError<AddError>
    >,
    pl_agent_tool::DefinitionError,
> {
    let prepared = pl_agent_tool::typed::prepare_json::<Add>()?;
    Ok(pl_agent_tool::ToolHandle::new(
        prepared.attach(Add { offset })
    ))
}
```

准备阶段在接管实例前生成并校验声明，attach 只移动实例，不失败。输入默认是原始 String；
宿主可通过 `attach_input` 提供一次性的文本提取函数。手写 `TypedTool` 与宏共用同一适配器。
宏仅支持命名参数结构体和规定的 inherent async execute/可选 close；支持泛型、where、
重命名依赖与显式 crate override，不生成装箱、spawn、授权或业务解析代码。

参数 schema 按 draft 2020-12 的反序列化语义生成，保留 `$schema`、title、联合与引用；
默认不生成输出 schema，需要时在 attach 前显式选择。schema 生成不执行全部约束，
range、长度和跨字段业务条件仍由作者检查。默认不注入未知字段拒绝。

普通 struct/map flatten 直接遵循 Serde/Schemars。严格未知字段拒绝不能与 Serde flatten
组合时，用私有非 flatten wire 与 `#[serde(from = "Wire")]`/From 保留共享业务结构。
decoder 保留实际路径与 JSON source，拒绝尾随输入；flatten/自定义 Deserialize
可能只提供容器级路径，不承诺叶子定位。需要保留领域错误/source 或已观测副作用的校验
应留在业务 handler。

## 动态与原始工具

动态发现的工具或 Text/Grammar 输入直接实现 `Tool`，持有已准备的不可变 `ToolDefinition`。
声明根 schema 只要求是 JSON 文档对象；库不限制其语义必须为 `type=object`，
也不解析或改写 `$defs`、`$ref`、oneOf/anyOf。名称与 Grammar 字段拒绝全空白，
保留合法字符串原字节。`definition()` 不执行 I/O，不在每次调用重建 schema。

MCP adapter 使用冻结远端 descriptor，而非临时从 Rust Value 派生声明；
共享服务的工具 close 只释放自身 lease。provider 名称、strict 和 object-only 限制
由宿主的模型投影处理，不回写作者声明。

## Anywork 作者升级

原 `pl_core::tool::opaque::Tool` 已迁至本库；raw/dynamic 作者直接实现 `pl_agent_tool::Tool`，
普通 JSON 作者使用上述 typed 层。Anywork 的固定端点为 `pl_core::tool::opaque::RuntimeTool`。

- 原生 ToolOutput/ToolError 使用 `pl_tool::binding::prepare_native_tool`，成功输出与已有错误
  原样通过，包括 observed_output、媒体、专用格式及控制提议。
- 普通 Serialize 输出使用 `prepare_json_tool`，显式选择同步 context/error 映射。
  成功后编码一次，同一 JSON 文本进入完整 payload 与模型 Text context；
  编码失败明确报告阶段与 source，可能已有副作用，不自动重执行。
- 使用 `binding::prepare_registration` 先做唯一模型投影、原 opaque 声明编码和内部 ID
  校验，再附着新 handle。内部 ID 与模型名称独立；控制授权仍在 Registration 显式配置。
- 旧作者 ToolSpec 构造器、重复 schema 与 properties 扫描已移除；动态 Rust 参数同样使用
  `typed::input_schema_for`。MCP、exec 特殊校验、raw patch 与角色化 finish 保留专用适配。

这次升级不改变模型线协议、工具结果信封、checkpoint、数据库或 FRB；
重开消费原保存字节与投影，不要求当前作者的 Args/Output 可反序列化。
完整宿主契约见 [工具运行时](../../design/09-tool-runtime.md) 与
[crate 边界](../../design/02-crates.md)。
