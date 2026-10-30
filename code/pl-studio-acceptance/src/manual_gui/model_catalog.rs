//! Optional discovery instances for directed native GUI observation.
use anyhow::{Context, Result, bail, ensure};
use pl_model::config::{
    AccountCatalogRegistry, AccountId, AccountModelCatalogConfig, builtin_account_catalog,
};
use pl_model::protocol::ConnectionMode;
use pl_provider_fixture::{
    MIMO_MEDIA_MODEL_IDS, MODEL_CATALOG_CONTROL_FILE_NAME, ModelCatalogControl,
};
use pl_studio_runtime::config::StudioConfig;
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

/// Loopback discovery instances written into the isolated `config.toml`.
pub(super) const INSTANCES: [(&str, &str, &str); 4] = [
    ("catalog-openai", "openai", "openai"),
    ("catalog-openai-second", "openai", "openai-second"),
    ("catalog-deepseek", "deepseek", "deepseek"),
    ("catalog-mimo", "mimo-api", "mimo"),
];

/// Bootstrap route model_id for a synthesized `models` inventory. Inventory A keeps a
/// withdrawable model_id so the restart journey can prove a vanished model stays
/// selected but unavailable.
const BOOTSTRAP_ROUTE_MODEL_ID: &str = "fixture-model-old";

/// Preferred bootstrap route model_id for payload instances: the captured list has no
/// `fixture-model-old`, so prefer a bundled model_id real responses usually contain.
/// It is only used when the selected capture really lists it; see
/// [`bootstrap_route_model_id`].
const PAYLOAD_BOOTSTRAP_ROUTE_MODEL_ID: &str = "gpt-6-astra";

/// Picks the `catalog-openai` startup route model_id.
///
/// A `models` inventory always keeps [`BOOTSTRAP_ROUTE_MODEL_ID`] because the restart
/// journey needs a withdrawable model_id. A payload instance must instead resolve
/// against ids the capture actually contains: prefer
/// [`PAYLOAD_BOOTSTRAP_ROUTE_MODEL_ID`], otherwise the first id the product catalog
/// would publish, and only when the capture has no model at all fall
/// back to [`BOOTSTRAP_ROUTE_MODEL_ID`] with a visible note.
fn bootstrap_route_model_id(control: Option<&ModelCatalogControl>) -> Result<String> {
    let Some(control) = control else {
        return Ok(BOOTSTRAP_ROUTE_MODEL_ID.into());
    };
    let Some(captured) = control.openai.captured_model_ids()? else {
        return Ok(BOOTSTRAP_ROUTE_MODEL_ID.into());
    };
    if captured
        .iter()
        .any(|id| id == PAYLOAD_BOOTSTRAP_ROUTE_MODEL_ID)
    {
        return Ok(PAYLOAD_BOOTSTRAP_ROUTE_MODEL_ID.into());
    }
    match captured.first() {
        Some(id) => Ok(id.clone()),
        None => {
            eprintln!(
                "captured catalog {captured:?} has no model; keeping {BOOTSTRAP_ROUTE_MODEL_ID} as the startup route"
            );
            Ok(BOOTSTRAP_ROUTE_MODEL_ID.into())
        }
    }
}

pub(super) fn configure(
    home: &Path,
    base_url: &str,
    control: Option<&ModelCatalogControl>,
) -> Result<()> {
    // Accept only an explicit IPv4 loopback endpoint; never consult real credentials.
    let remainder = base_url
        .strip_prefix("http://127.0.0.1:")
        .ok_or_else(|| anyhow::anyhow!("model catalog fixture must use IPv4 loopback HTTP"))?;
    let port = remainder.split('/').next().unwrap_or_default();
    ensure!(
        port.parse::<u16>().is_ok_and(|port| port != 0),
        "invalid model catalog fixture port"
    );
    let file = home.join("config.toml");
    let mut config: StudioConfig = toml::from_str(&fs::read_to_string(&file)?)?;
    let catalog = builtin_account_catalog()?;
    ensure_catalog_discovery_declarations(&catalog)?;
    let route_model_id = bootstrap_route_model_id(control)?;
    for (id, preset, suffix) in INSTANCES {
        let preset = catalog
            .templates
            .iter()
            .find(|candidate| candidate.id.as_str() == preset)
            .ok_or_else(|| anyhow::anyhow!("model catalog fixture preset is missing"))?;
        let mut account = preset.account.clone();
        account.name = id.to_owned();
        account.base_url = format!("{}/{suffix}", base_url.trim_end_matches('/'));
        account.bearer_token_env = None;
        account.bearer_token = None;
        if id == "catalog-openai"
            && let AccountModelCatalogConfig::Bundled {
                connection_overrides,
                auto_compact_overrides,
                ..
            } = &mut account.catalog
        {
            connection_overrides.insert(route_model_id.clone(), ConnectionMode::Http);
            auto_compact_overrides.insert(route_model_id.clone(), 12_000);
        }
        config.models.accounts.insert(AccountId::new(id)?, account);
    }
    let openai = AccountId::new("catalog-openai")?;
    for route in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        route.account_id = openai.clone();
        route.model_id = route_model_id.clone();
        route.effort = None;
    }
    // Discovery instances keep withdrawn-model_id routes and overrides before the
    // first successful observation; strict `validate` would reject them.
    config.validate_declarations()?;
    fs::write(file, toml::to_string_pretty(&config)?)?;
    Ok(())
}

fn ensure_catalog_discovery_declarations(catalog: &AccountCatalogRegistry) -> Result<()> {
    for preset in catalog
        .templates
        .iter()
        .filter(|preset| ["openai", "deepseek", "mimo-api"].contains(&preset.id.as_str()))
    {
        ensure!(
            preset.account.discovery_profile()?.is_some(),
            "fixture account must support discovery"
        );
    }
    Ok(())
}

/// Resolves a named inventory or an operator-supplied control file without
/// writing it. Argument validation inspects the selection before any temporary
/// environment exists; the coordinator then materializes the same resolution.
pub(super) fn resolve_control(
    inventory: Option<&str>,
    source: Option<&Path>,
) -> Result<ModelCatalogControl> {
    ensure!(
        inventory.is_some() || source.is_some(),
        "model catalog control requires --model-catalog-inventory or --model-catalog-control"
    );
    let control = match (inventory, source) {
        (None, Some(path)) => ModelCatalogControl::load(path)?,
        (Some(name), None) => ModelCatalogControl::named(name)?,
        (None, None) => {
            bail!(
                "model catalog control requires --model-catalog-inventory or --model-catalog-control"
            )
        }
        (Some(_), Some(_)) => {
            bail!("--model-catalog-inventory cannot be combined with --model-catalog-control")
        }
    };
    Ok(control)
}

/// Materializes a named inventory or copies an operator-supplied control file.
pub(super) fn materialize_control(
    destination: &Path,
    inventory: Option<&str>,
    source: Option<&Path>,
) -> Result<ModelCatalogControl> {
    let control = resolve_control(inventory, source)?;
    control.write(destination)?;
    Ok(control)
}

pub(super) fn default_control_path(working: &Path) -> std::path::PathBuf {
    working.join(MODEL_CATALOG_CONTROL_FILE_NAME)
}

/// Human-readable restart-driven checklist written next to screenshots/logs.
pub(super) fn write_runbook(
    output: &Path,
    home: &Path,
    control_path: &Path,
    control: &ModelCatalogControl,
    fixture_base_url: &str,
) -> Result<()> {
    let cache_dir = home.join("data/model-catalogs");
    let config = home.join("config.toml");
    let runbook = format!(
        r#"# 在线目录发现人工验收 Runbook

既有 `--model-catalog-restart` 场景仍验证重启初始化。Issue 168 的同进程场景使用下述 loopback 控制端点切换后继模拟响应，不需要重启 fixture 或 GUI；这些动作只是环境设置证据，不代表产品已应用目录结果。

## 环境

- 隔离 home: `{home}`（临时目录，运行结束即删；`--scenario gui` 与 catalog 重启旅程可加 `--retain-environment` 保留整个隔离环境）
- config.toml: `{config}`（随隔离 home 删除；结束时脱敏副本写入证据目录 `{output}/config.toml`，重启旅程为 `{output}/config-phase-a.toml` / `{output}/config-phase-b.toml`）
- 控制文件（启动时读取一次）: `{control}`；证据副本 `{output}/model-catalog.json`
- 成功观察缓存: `{cache}`（随隔离 home 删除；协调器把 model_id/`checkedAt`/`cachePath` 写进证据目录的 phase JSON）
- fixture `/v1` 前缀: `{base}`
- 证据目录: `{output}`（截图/快照/请求/日志沿用既有产物）
- 发现实例: `catalog-openai`（`{base}/openai/models`）、`catalog-openai-second`（`{base}/openai-second/models`）、`catalog-deepseek`（`{base}/deepseek/models`）、`catalog-mimo`（`{base}/mimo/models`，Chat 传输语义，仅需 `/models`）
- MiMo 媒体 model_id（完整发布）: {media_ids}
- 当前控制文件库存:
{inventory}

命名库存用 `--model-catalog-inventory a|b|empty|reject-all|reject-second|real`；自定义文件用 `--model-catalog-control PATH`。这些参数只确定本次启动的初始库存；运行中切换后继库存请使用上面的 loopback control endpoint，不需要重启。

## 同进程运行时控制（Issue 168）

fixture 仅绑定 IPv4 loopback。发送 `POST http://127.0.0.1:<port>/__model_catalog/control`，其中 `<port>` 与 `{base}` 相同。控制只作用于后续接纳的目录 GET，不改产品配置、目录缓存或 GUI 状态，不接受 URL、路径或真实 credential。

```json
{{"action":"inventory","name":"b"}}
{{"action":"failure","provider":"openai","enabled":true}}
{{"action":"gate","provider":"openai","enabled":true}}
{{"action":"release","provider":"openai"}}
{{"action":"state"}}
```

库存仅接受 `a`、`b`、`empty`、`real`、`reject-all`、`reject-second`；provider 仅接受 `openai`、`openai-second`、`deepseek`、`mimo`。`failure` 让该 provider 后续请求返回 HTTP 401，`enabled:false` 解除。成功返回 HTTP 200 快照：`providers` map 每项含 `requests` 计数、`gated`、`failing`、`accepted` 合成身份数组和 `waiting` 身份数组。Gate 在接纳时生效；关闭 gate 只影响新请求，已等待请求仍须 `release`。先轮询 `state` 确认 `waiting` 含身份，再 `release`，不用固定 sleep。每个已接纳请求冻结其响应计划，后续切换库存/失败不会替换在途响应。每个 provider 最多保留 256 个已接纳身份、最多 16 个 gate waiter；全状态 JSON 不超过 64 KiB。触顶时新目录 GET 在接纳前返回 HTTP 503 `{{"error":"..."}}`，不增加计数或留身份。未知 action/provider/inventory 和额外字段返回 HTTP 422；JSON 语法错误保持 Axum 原始状态码（例如 `{{` 返回 HTTP 400）。

```sh
curl -sS -X POST http://127.0.0.1:PORT/__model_catalog/control \
  -H 'content-type: application/json' -d '{{"action":"state"}}'
```

JSON 字段（每个 account：`openai` / `openai-second` / `deepseek` / `mimo`）:

```json
{{
  "openai": {{ "models": ["gpt-6-astra"], "reject": false, "status": 401, "protocolError": false, "hang": false }}
}}
```

- `models`: 任意 model_id 列表；空名单是合法成功替换。
- `payload`: 可选，原样返回编译进 fixture 的真实 `/models` 响应（见第 8 项）；不能与 `models` 同时声明，否则 fixture 启动即报错。
- 失败开关互斥，判定顺序 **`hang` > `protocolError` > `status`/`reject`**：同时给出时只生效最先匹配的一项，不会静默组合。
- `hang: true`: 挂起直到进程停止（超时隔离）。
- `protocolError: true`: HTTP 200 + error envelope，验证协议失败回退。
- `status`: 非 2xx 验证 HTTP 失败回退。
- `status` 为 2xx 时不改写成功响应码：`models` 列表与 `payload` 原样报文都恒为 HTTP 200。
- `reject: true`: 未给 `status` 时 HTTP 401。

## 1. 旧模型移除

一条命令完成第 1 项和第 5 项（同 home、同端口，必须重启 fixture + GUI）：

```text
cargo xtask manual-gui --scenario gui --model-catalog-inventory a --model-catalog-restart
```

状态机：库存 A 启动 → 协调器断言 `catalog-openai` 缓存 model_id 集合含 `fixture-model-old`、`gpt-6-astra`、`gpt-6.1-sol` → 停 GUI（保留 home）→ 停 fixture（shutdown 后复制 `<evidence>/model-catalog-requests-a.json`）→ 写库存 B（去掉 `fixture-model-old` 与内置 model_id `gpt-6.1-sol`，保留 `gpt-6-astra`；`openai-second` 改为 `gpt-6-sol`）→ **同一端口**重启 fixture → 同一 home 重启 GUI → 协调器断言 old 与 `gpt-6.1-sol` 消失、`gpt-6-astra` 仍在、`checkedAt` 前进，并记录被选中的 `cachePath`。阶段 A 把 `catalog-openai` 路由设为 `fixture-model-old` 并写入连接/压缩覆盖；阶段 B 断言 `config.toml` 仍保留该路由与覆盖。

协调器断言 = 原始在线缓存 model_id 集合（present/absent）+ `checkedAt` 前进 + 路由与覆盖保留。上述内置项的“消失”仅指在线缓存；管理目录仍须保留 `gpt-6.1-sol`，显示 `origin=bundled` 且自动默认关闭，显式启用后恢复选择资格。线上独有的 `fixture-model-old` 则从管理目录消失，覆盖不得将它重新注入。`origin=online` / `source=online` 由第 6 项（`--model-catalog-inventory a` 的成功在线观测）的人工观察与截图确认（缓存文件无法直接断言 origin/source）。`--model-catalog-restart` 只产出协调器断言与缓存/日志证据，**不产出 GUI 截图**；要看来源徽标/`source=online` 需另跑一次 `--scenario gui --model-catalog-inventory a`。协调器失败即非零退出并打印缓存片段。改库存只刷新界面不够。

阶段 B 证据：`<evidence>/model-catalog-requests-b.json`（对应 fixture shutdown 后）、`catalog-phase-b-gui.log`、`fixture-restart.log`、`requests-restart.json`、`model-catalog-phase-a.json` / `model-catalog-phase-b.json`、脱敏 `config-phase-a.toml` / `config-phase-b.toml`。

## 2. 无观察回退

本工具每次运行都是全新隔离 home，并自带 fixture 子进程。不要在同一会话里改控制文件后热重启。

```text
cargo xtask manual-gui --scenario gui --model-catalog-inventory reject-all
```

1. 全新隔离 home（无既有 `{cache}` 成功观察）。
2. fixture 四实例均 `reject: true`（HTTP 401）。
3. 启动 GUI 后打开发现实例设置页。
4. 应观察：account `status.source=default`（尚未同步），模型级 `origin=bundled`；bundled 默认模型重新出现。失败时 `error` 为类型化 Http/Protocol/Timeout，不是自由文本。
5. 证据：设置页截图、runtime 日志、本目录 `fixture.log`、`<evidence>/model-catalog-requests.json`（fixture 停止后复制）。

也可用自定义控制文件把该实例设为 `protocolError: true` 后同样重跑一次，验证协议失败回退。

## 3. 手动模型区分与删除

1. 在某一发现实例上新增手动模型（不与在线 model_id 冲突）。
2. 应观察：GUI 「手动模型」分组 + 徽标；`{config}` 的 `additional_models` 写入该 model_id。
3. 详情卡删除该手动模型。
4. 应观察：列表与 `additional_models` 同时消失；该 model_id 的压缩阈值/连接覆盖一并清除。
5. 证据：设置页截图；结束时证据目录的脱敏 `{output}/config.toml`（`additional_models` 与该 model_id 的连接/压缩覆盖应已消失）。删除前状态请自行另存一份，或加 `--retain-environment` 复核隔离 home 里的 `{config}`。

## 4. 计费不丢失

发现实例已挂 `/{{suffix}}/responses` 与 `/{{suffix}}/chat/completions`，剥前缀后委托既有严格脚本 `handle`（不复制推理实现）。已知在线 model_id（`gpt-6-astra`）应显示内置价格行；未知在线 model_id（`mimo-v2.6-pro`、`fixture-model-old`）显示未计价/空行。对已知 model_id 发调用应产生 `estimated_costs`；对未知 model_id 发调用应 `has_unpriced_usage=true`。历史会话费用在重启前后不变。

## 5. 路由不可用

由 `--model-catalog-restart` 同一旅程完成。阶段 A 将 `catalog-openai` 全部角色/模式路由设为 `fixture-model-old`，并写入该 model_id 的连接覆盖与压缩阈值。阶段 B 断言 `config.toml` 路由与覆盖未被改写；有效目录不再含该 model_id，选择以 unavailable 保留。对照证据目录的脱敏 `config-phase-a.toml` / `config-phase-b.toml`。

## 6. MiMo 发现

```text
cargo xtask manual-gui --scenario gui --model-catalog-inventory a
```

1. 控制文件 MiMo 段包含 `mimo-v2.5-pro`、`mimo-v2.5`、`mimo-v2.6-pro` 以及 4 个媒体 model_id。
2. 启动后打开 `catalog-mimo`。
3. 应观察：供应商设置保留 TTS/ASR 四个 model_id 与其他在线 model_id；会话和 Agent 菜单只列出最终合并后支持文本输入、文本输出且解析上下文为正数的模型，模式切换不得改变该选择项集合。已保存的不合格选择保留并展示筛选原因。
4. 证据：MiMo 列表截图、`<evidence>/model-catalog-requests.json`（path/status/account/hits/rejected；`account` 为实例名 `openai`/`openai-second`/`deepseek`/`mimo`）、`{cache}` 下 `model.json`、studio 日志。不要使用严格脚本的 `requests.json`。

## 7. 失败隔离

本工具每次运行都是全新隔离 home。验证失败隔离请单独重跑，不要依赖上一趟库存 A 的进程：

```text
cargo xtask manual-gui --scenario gui --model-catalog-inventory reject-second
```

1. `catalog-openai` 走库存 A（含 `gpt-6-astra`）；`catalog-openai-second` 返回 401。
2. 启动后打开两个实例。
3. 应观察：仅 `catalog-openai-second` 显示错误状态；`catalog-openai` / DeepSeek / MiMo 正常；首屏不受影响。
4. 证据：两个实例设置页截图、首屏截图、`gui.log`、`<evidence>/model-catalog-requests.json`。

超时隔离可用自定义控制文件把该实例设为 `hang: true` 后同样重跑一次。

## 8. 真实报文复刻（payload 模式）

`real` 预设让 fixture 原样返回抓取下来的真实 `/models` 响应，用于离线复现真实报文字段（`context_window`、`max_output_tokens`、`input_modalities`、`effort`、`api_capabilities` 等），**不联网、不校验真实凭据**。

```text
cargo xtask manual-gui --scenario gui --model-catalog-inventory real
```

1. 控制文件：`catalog-openai` 与 `catalog-openai-second` 用 `payload: "openai-aggregator"`（19 个 id），`catalog-deepseek` 用 `payload: "deepseek"`（2 个 id），`catalog-mimo` 仍是库存 A 的合成名单（含 4 个 TTS/ASR 媒体 model_id）。
2. payload 实例不做任何增删改：HTTP 200、`content-type: application/json`，正文与 `code/pl-provider-fixture/assets/model-lists/` 下的资源逐字节一致。
3. 打开 `catalog-openai` 设置页：应观察全部 19 个 model_id，包括全部 gpt-image 项；会话所有模式和 Agent 菜单共用文本筛选结果。无上下文声明且不能由精确 ID 补全的模型不出现在菜单中，已有选择保留并说明原因。
4. 打开 `catalog-deepseek`：应观察 2 个 model_id，且详情卡显示真实上下文/输出上限与 effort 档位（`context_window=1048576`、`max_output_tokens=393216`、`supported_levels` 为 `low/high/max`，模型声明默认 `high`）。合成名单模式没有这些字段。
5. payload 模式下启动路由优先使用实际存在的 `gpt-6-astra`，否则取报文第一个精确 ID；空名单保留原选择并标记不可用。
6. 这是离线复刻，报文内容取自资源文件而非实时探测；把控制文件的 `payload` 去掉即回到 `models` 列表模式（两种模式共用 `reject` / `protocolError` / `status` / `hang` 失败开关，优先级不变）。
7. 证据：两个实例的设置页截图、运行目录的 `model-catalog.json`、`model-catalog-requests.json`、`gui.log`。自检可用 `pl-provider-fixture --model-catalog-inventory real --model-catalog-check`，输出每个路径的 `payload=`/`ids=`/`image=`/`non_image=`/`ids_match=true`/`body_match=true`。

完成后在本目录记录 `verdict.json` 与 `operations.json`，保持既有截图/快照/请求/日志机制。
"#,
        home = home.display(),
        config = config.display(),
        control = control_path.display(),
        cache = cache_dir.display(),
        base = fixture_base_url.trim_end_matches('/'),
        output = output.display(),
        media_ids = MIMO_MEDIA_MODEL_IDS.join(", "),
        inventory = inventory_summary(control),
    );
    fs::write(output.join("model-catalog-runbook.md"), runbook)
        .context("failed to write model catalog runbook")?;
    control
        .write(output.join(MODEL_CATALOG_CONTROL_FILE_NAME))
        .context("failed to copy model catalog control into evidence")?;
    Ok(())
}

fn inventory_summary(control: &ModelCatalogControl) -> String {
    format!(
        "- openai: models={:?} payload={:?} reject={} status={:?} protocolError={} hang={}\n- openai-second: models={:?} payload={:?} reject={} status={:?} protocolError={} hang={}\n- deepseek: models={:?} payload={:?} reject={} status={:?} protocolError={} hang={}\n- mimo: models={:?} payload={:?} reject={} status={:?} protocolError={} hang={}",
        control.openai.models,
        control.openai.payload,
        control.openai.reject,
        control.openai.status,
        control.openai.protocol_error,
        control.openai.hang,
        control.openai_second.models,
        control.openai_second.payload,
        control.openai_second.reject,
        control.openai_second.status,
        control.openai_second.protocol_error,
        control.openai_second.hang,
        control.deepseek.models,
        control.deepseek.payload,
        control.deepseek.reject,
        control.deepseek.status,
        control.deepseek.protocol_error,
        control.deepseek.hang,
        control.mimo.models,
        control.mimo.payload,
        control.mimo.reject,
        control.mimo.status,
        control.mimo.protocol_error,
        control.mimo.hang,
    )
}

pub(super) const WITHDRAWN_MODEL_ID: &str = "fixture-model-old";
pub(super) const KEPT_BUNDLED_MODEL_ID: &str = "gpt-6-astra";
pub(super) const WITHDRAWN_BUNDLED_MODEL_ID: &str = "gpt-6.1-sol";

#[derive(Debug, Clone, Copy)]
pub(super) struct CatalogPhaseExpectation {
    pub present: &'static [&'static str],
    pub absent: &'static [&'static str],
}

pub(super) fn phase_a_expectation() -> CatalogPhaseExpectation {
    CatalogPhaseExpectation {
        present: &[
            WITHDRAWN_MODEL_ID,
            KEPT_BUNDLED_MODEL_ID,
            WITHDRAWN_BUNDLED_MODEL_ID,
        ],
        absent: &[],
    }
}

pub(super) fn phase_b_expectation() -> CatalogPhaseExpectation {
    CatalogPhaseExpectation {
        present: &[KEPT_BUNDLED_MODEL_ID],
        absent: &[WITHDRAWN_MODEL_ID, WITHDRAWN_BUNDLED_MODEL_ID],
    }
}

pub(super) fn rewrite_inventory_b(path: &Path) -> Result<()> {
    ModelCatalogControl::inventory_b().write(path)
}

pub(super) fn bind_port(base_url: &str) -> Result<u16> {
    let remainder = base_url
        .strip_prefix("http://127.0.0.1:")
        .context("fixture base_url must use IPv4 loopback")?;
    let port = remainder
        .split('/')
        .next()
        .context("fixture base_url missing port")?;
    port.parse().context("fixture base_url port is not u16")
}

pub(super) struct CatalogCacheAssertion {
    pub checked_at: i64,
    pub cache_path: String,
}

pub(super) fn wait_for_online_cache(
    home: &Path,
    expected: CatalogPhaseExpectation,
    previous_checked_at: Option<i64>,
) -> Result<CatalogCacheAssertion> {
    let deadline = Instant::now() + Duration::from_secs(45);
    let mut last = String::from("(no cache yet)");
    while Instant::now() < deadline {
        match read_openai_cache(home) {
            Ok((path, cache)) => {
                last = serde_json::to_string(&cache).unwrap_or_else(|_| cache.to_string());
                if let Ok(checked) = assert_openai_cache(&cache, expected, previous_checked_at) {
                    return Ok(CatalogCacheAssertion {
                        checked_at: checked,
                        cache_path: path.display().to_string(),
                    });
                }
            }
            Err(error) => last = error.to_string(),
        }
        thread::sleep(Duration::from_millis(250));
    }
    bail!("catalog cache assertion failed; last fragment: {last}")
}

fn read_openai_cache(home: &Path) -> Result<(PathBuf, Value)> {
    let root = home.join("data/model-catalogs");
    let mut matching = Vec::new();
    collect_openai_caches(&root, &mut matching)?;
    matching
        .into_iter()
        .max_by_key(|(modified, _, _)| *modified)
        .map(|(_, path, cache)| (path, cache))
        .context("no catalog-openai model.json under data/model-catalogs")
}

fn collect_openai_caches(
    dir: &Path,
    matching: &mut Vec<(std::time::SystemTime, PathBuf, Value)>,
) -> Result<()> {
    if !dir.is_dir() {
        return Ok(());
    }
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_openai_caches(&path, matching)?;
            continue;
        }
        if path.file_name().and_then(|name| name.to_str()) != Some("model.json") {
            continue;
        }
        let cache: Value = serde_json::from_slice(&fs::read(&path)?)?;
        // catalog-openai uniquely lists gpt-6-astra; openai-second uses gpt-6-sol.
        if cache_model_ids(&cache)
            .iter()
            .any(|model_id| model_id == KEPT_BUNDLED_MODEL_ID)
        {
            matching.push((entry.metadata()?.modified()?, path, cache));
        }
    }
    Ok(())
}

fn assert_openai_cache(
    cache: &Value,
    expected: CatalogPhaseExpectation,
    previous_checked_at: Option<i64>,
) -> Result<i64> {
    let model_ids = cache_model_ids(cache);
    for model_id in expected.present {
        ensure!(
            model_ids.iter().any(|value| value == model_id),
            "expected {model_id} in cache, had {model_ids:?}"
        );
    }
    for model_id in expected.absent {
        ensure!(
            !model_ids.iter().any(|value| value == model_id),
            "did not expect {model_id} in cache, had {model_ids:?}"
        );
    }
    let checked = cache
        .get("checkedAt")
        .and_then(Value::as_i64)
        .context("cache missing checkedAt")?;
    if let Some(previous) = previous_checked_at {
        ensure!(
            checked > previous,
            "checkedAt {checked} did not advance past {previous}"
        );
    }
    Ok(checked)
}

fn cache_model_ids(cache: &Value) -> Vec<String> {
    cache
        .get("models")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|model| {
            model
                .get("model_id")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .collect()
}

pub(super) fn assert_route_preserved(home: &Path) -> Result<()> {
    let config: StudioConfig = toml::from_str(&fs::read_to_string(home.join("config.toml"))?)?;
    let openai = config
        .models
        .accounts
        .get(&AccountId::new("catalog-openai")?)
        .context("catalog-openai missing after restart")?;
    ensure!(
        config
            .models
            .routes
            .values()
            .chain(config.mode_model_routes.values())
            .all(|route| route.account_id.as_str() == "catalog-openai"
                && route.model_id == WITHDRAWN_MODEL_ID),
        "routes were rewritten across catalog restart"
    );
    match &openai.catalog {
        AccountModelCatalogConfig::Bundled {
            connection_overrides,
            auto_compact_overrides,
            ..
        } => {
            ensure!(
                connection_overrides.get(WITHDRAWN_MODEL_ID) == Some(&ConnectionMode::Http),
                "connection override for {WITHDRAWN_MODEL_ID} was removed"
            );
            ensure!(
                auto_compact_overrides.get(WITHDRAWN_MODEL_ID) == Some(&12_000),
                "auto-compact override for {WITHDRAWN_MODEL_ID} was removed"
            );
        }
        _ => bail!("catalog-openai is no longer a bundled catalog"),
    }
    Ok(())
}

pub(super) fn copy_hits(source: &Path, dest: &Path, required: bool) -> Result<()> {
    if source.is_file() {
        fs::copy(source, dest)?;
        return Ok(());
    }
    eprintln!(
        "catalog hits missing after fixture shutdown: {}",
        source.display()
    );
    ensure!(
        !required,
        "catalog hits missing after fixture shutdown: {}",
        source.display()
    );
    Ok(())
}

/// Non-interactive coordinator check: bind, rewrite inventory B, rebind the same port.
pub(super) fn restart_bind_check(executable: &Path, control_path: &Path) -> Result<()> {
    let first = spawn_bind_fixture(executable, control_path, None)?;
    let port = first.port;
    stop_child(first.child);
    rewrite_inventory_b(control_path)?;
    let second = spawn_bind_fixture(executable, control_path, Some(port))?;
    ensure!(
        second.port == port,
        "restart rebound {port} as {}",
        second.port
    );
    stop_child(second.child);
    Ok(())
}

struct BindFixture {
    child: std::process::Child,
    port: u16,
}

fn spawn_bind_fixture(
    executable: &Path,
    control_path: &Path,
    port: Option<u16>,
) -> Result<BindFixture> {
    let ready = control_path.with_extension("ready.json");
    let _ = fs::remove_file(&ready);
    let mut command = Command::new(executable);
    command
        .arg("--scenario")
        .arg("gui")
        .arg("--ready-file")
        .arg(&ready)
        .arg("--model-catalog-control")
        .arg(control_path)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if let Some(port) = port {
        command.arg("--bind-port").arg(port.to_string());
    }
    let mut child = command
        .spawn()
        .context("failed to start catalog bind-check fixture")?;
    let deadline = Instant::now() + Duration::from_secs(20);
    while Instant::now() < deadline {
        if ready.is_file() {
            let ready: Value = serde_json::from_slice(&fs::read(&ready)?)?;
            let url = ready
                .get("base_url")
                .and_then(Value::as_str)
                .context("ready file missing base_url")?;
            return Ok(BindFixture {
                child,
                port: bind_port(url)?,
            });
        }
        if child.try_wait()?.is_some() {
            bail!("catalog bind-check fixture exited before ready-file");
        }
        thread::sleep(Duration::from_millis(50));
    }
    stop_child(child);
    bail!("catalog bind-check fixture did not publish ready-file")
}

fn stop_child(mut child: std::process::Child) {
    let _ = child.kill();
    let _ = child.wait();
}
