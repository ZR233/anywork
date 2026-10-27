//! Startup-cached OpenAI-compatible `/models` inventories for catalog acceptance.
//!
//! The control file is read once when the fixture process starts. Changing the
//! file never affects a running listener; operators rewrite it and restart.

use std::collections::BTreeSet;
use std::sync::{Arc, Mutex};
use std::{fs, net::SocketAddr, path::Path, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use axum::{
    Json,
    body::Body,
    extract::State,
    http::{HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
};

use super::AppState;

/// Default control-file name written by the manual-GUI coordinator.
pub const CONTROL_FILE_NAME: &str = "model-catalog.json";

/// MiMo TTS/ASR model IDs retained in the complete product catalog.
pub const MIMO_MEDIA_MODEL_IDS: [&str; 4] = [
    "mimo-v2.5-asr",
    "mimo-v2.5-tts",
    "mimo-v2.5-tts-voiceclone",
    "mimo-v2.5-tts-voicedesign",
];

/// Path suffixes served under the fixture `/v1` prefix.
pub const OPENAI_PATH: &str = "/v1/openai/models";
pub const OPENAI_SECOND_PATH: &str = "/v1/openai-second/models";
pub const DEEPSEEK_PATH: &str = "/v1/deepseek/models";
pub const MIMO_PATH: &str = "/v1/mimo/models";

/// Image model ID prefix used only when reporting payload composition in the
/// self-check. The fixture returns the complete captured resource unchanged.
const IMAGE_MODEL_ID_PREFIX: &str = "gpt-image-";

/// One captured real `/models` response selectable from the control file.
///
/// The resource is compiled into the binary so acceptance runs never depend on
/// the source tree, and it is returned byte-for-byte: no synthesis, no
/// filtering and no re-serialization.
struct PayloadAsset {
    /// Stable control-file name; operators never reference the asset path.
    name: &'static str,
    json: &'static str,
}

const PAYLOAD_ASSETS: [PayloadAsset; 2] = [
    PayloadAsset {
        name: "deepseek",
        json: include_str!("../assets/model-lists/deepseek.json"),
    },
    PayloadAsset {
        name: "openai-aggregator",
        json: include_str!("../assets/model-lists/openai-aggregator.json"),
    },
];

/// Loopback suffixes used by discovery instances. Inference is served at
/// `/{suffix}/responses` and `/{suffix}/chat/completions` by stripping the
/// suffix and forwarding to the existing strict-script handler.
pub const PROVIDER_SUFFIXES: [&str; 4] = ["openai", "openai-second", "deepseek", "mimo"];

/// One catalog GET recorded separately from the strict conversation script.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ModelCatalogHit {
    pub provider: String,
    pub path: String,
    pub status: u16,
    pub rejected: bool,
}

/// Per-provider catalog GET counters written to evidence.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct ModelCatalogProviderHits {
    pub hits: usize,
    pub rejected: usize,
    pub last_status: Option<u16>,
}

/// Structured catalog evidence; never mixed into `requests.json`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct ModelCatalogRequestReport {
    pub openai: ModelCatalogProviderHits,
    #[serde(rename = "openai-second")]
    pub openai_second: ModelCatalogProviderHits,
    pub deepseek: ModelCatalogProviderHits,
    pub mimo: ModelCatalogProviderHits,
    pub requests: Vec<ModelCatalogHit>,
}

#[derive(Clone, Default)]
pub(super) struct ModelCatalogHits {
    inner: Arc<Mutex<ModelCatalogRequestReport>>,
}

impl ModelCatalogHits {
    fn record(&self, provider: CatalogProvider, path: &str, status: u16, rejected: bool) {
        let mut report = self.inner.lock().expect("fixture state poisoned");
        let bucket = match provider {
            CatalogProvider::Openai => &mut report.openai,
            CatalogProvider::OpenaiSecond => &mut report.openai_second,
            CatalogProvider::DeepSeek => &mut report.deepseek,
            CatalogProvider::Mimo => &mut report.mimo,
        };
        bucket.hits += 1;
        if rejected {
            bucket.rejected += 1;
        }
        bucket.last_status = Some(status);
        report.requests.push(ModelCatalogHit {
            provider: provider.instance().to_owned(),
            path: path.to_owned(),
            status,
            rejected,
        });
    }

    pub(super) fn snapshot(&self) -> ModelCatalogRequestReport {
        self.inner.lock().expect("fixture state poisoned").clone()
    }
}

/// One provider's startup inventory and failure switch.
///
/// Failure switches are exclusive in evaluation order: `hang` wins, then
/// `protocolError`, then explicit `status` or `reject`. Later flags are not
/// applied once an earlier one matches; operators must not rely on silent
/// combination.
///
/// A successful 2xx answer is either the synthesized list from [`models`](Self::models)
/// or, when [`payload`](Self::payload) is set, one captured real response
/// returned unchanged with HTTP 200. The two body sources are mutually exclusive;
/// failure switches apply to both.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelCatalogProviderControl {
    /// Exact model_ids returned in the OpenAI-compatible list. An empty list is a
    /// successful replacement, not a transport failure.
    #[serde(default)]
    pub models: Vec<String>,
    /// Captured real `/models` response returned verbatim instead of
    /// [`models`](Self::models). Declaring both is a startup error.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payload: Option<String>,
    /// When true, answer with HTTP 401 unless [`status`](Self::status) is set.
    #[serde(default)]
    pub reject: bool,
    /// Optional explicit HTTP status. Non-2xx values fail discovery as HTTP
    /// errors; a 2xx value serves the success body, which is always HTTP 200 for
    /// a [`payload`](Self::payload) instance so the capture matches the list
    /// mode and no journey depends on a reason phrase.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<u16>,
    /// Return HTTP 200 with an error envelope so decode fails as protocol error.
    #[serde(default)]
    pub protocol_error: bool,
    /// Hold the request until the fixture stops so the 10s discovery deadline
    /// expires. Used for failure isolation, not hot reload.
    #[serde(default)]
    pub hang: bool,
}

/// Control file covering the four loopback discovery instances.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelCatalogControl {
    #[serde(default)]
    pub openai: ModelCatalogProviderControl,
    #[serde(rename = "openai-second", default)]
    pub openai_second: ModelCatalogProviderControl,
    #[serde(default)]
    pub deepseek: ModelCatalogProviderControl,
    #[serde(default)]
    pub mimo: ModelCatalogProviderControl,
}

#[derive(Clone, Copy)]
enum CatalogProvider {
    Openai,
    OpenaiSecond,
    DeepSeek,
    Mimo,
}

impl CatalogProvider {
    fn path(self) -> &'static str {
        match self {
            Self::Openai => OPENAI_PATH,
            Self::OpenaiSecond => OPENAI_SECOND_PATH,
            Self::DeepSeek => DEEPSEEK_PATH,
            Self::Mimo => MIMO_PATH,
        }
    }

    fn owned_by(self) -> &'static str {
        match self {
            Self::Openai | Self::OpenaiSecond => "openai",
            Self::DeepSeek => "deepseek",
            Self::Mimo => "mimo",
        }
    }

    fn instance(self) -> &'static str {
        match self {
            Self::Openai => "openai",
            Self::OpenaiSecond => "openai-second",
            Self::DeepSeek => "deepseek",
            Self::Mimo => "mimo",
        }
    }
}

impl ModelCatalogControl {
    /// Reads and caches the control file. The caller must not reread later.
    pub fn load(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        let text = fs::read_to_string(path)
            .with_context(|| format!("failed to read model catalog control {}", path.display()))?;
        let control: Self = serde_json::from_str(&text).with_context(|| {
            format!("model catalog control {} is not valid JSON", path.display())
        })?;
        control.validate()?;
        Ok(control)
    }

    /// Writes the control file so an operator or coordinator can replace it
    /// before the next process start.
    pub fn write(&self, path: impl AsRef<Path>) -> Result<()> {
        self.validate()?;
        let path = path.as_ref();
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, format!("{}\n", serde_json::to_string_pretty(self)?))
            .with_context(|| format!("failed to write model catalog control {}", path.display()))
    }

    /// Inventory A: known bundled model_ids, a withdrawable `fixture-model-old`,
    /// unknown `mimo-v2.6-pro`, and MiMo's four TTS/ASR model IDs.
    pub fn inventory_a() -> Self {
        let openai = ModelCatalogProviderControl {
            models: vec![
                "gpt-6-astra".into(),
                "gpt-6.1-sol".into(),
                "fixture-model-old".into(),
            ],
            ..ModelCatalogProviderControl::default()
        };
        Self {
            openai,
            openai_second: ModelCatalogProviderControl {
                models: vec![
                    "gpt-6-sol".into(),
                    "gpt-6.1-sol".into(),
                    "fixture-model-old".into(),
                ],
                ..ModelCatalogProviderControl::default()
            },
            deepseek: ModelCatalogProviderControl {
                models: vec!["deepseek-flash".into(), "fixture-model-old".into()],
                ..ModelCatalogProviderControl::default()
            },
            mimo: ModelCatalogProviderControl {
                models: mimo_inventory(true),
                ..ModelCatalogProviderControl::default()
            },
        }
    }

    /// Inventory B withdraws online-only `fixture-model-old` and bundled `gpt-6.1-sol`.
    /// Only the raw online inventory loses both; management retains the bundled member disabled.
    pub fn inventory_b() -> Self {
        let openai = ModelCatalogProviderControl {
            models: vec!["gpt-6-astra".into()],
            ..ModelCatalogProviderControl::default()
        };
        Self {
            openai,
            openai_second: ModelCatalogProviderControl {
                models: vec!["gpt-6-sol".into()],
                ..ModelCatalogProviderControl::default()
            },
            deepseek: ModelCatalogProviderControl {
                models: vec!["deepseek-flash".into()],
                ..ModelCatalogProviderControl::default()
            },
            mimo: ModelCatalogProviderControl {
                models: mimo_inventory(false),
                ..ModelCatalogProviderControl::default()
            },
        }
    }

    /// Empty successful lists for every instance.
    pub fn inventory_empty() -> Self {
        Self::default()
    }

    /// Real captured `/models` responses: both OpenAI instances replay the
    /// aggregator gateway list (19 ids, 5 of them `gpt-image-*`), DeepSeek
    /// replays its own two-model list, and MiMo keeps inventory A's synthetic
    /// names so the product-side TTS/ASR exclusion still has fixtures to reject.
    pub fn inventory_real() -> Self {
        fn payload(name: &str) -> ModelCatalogProviderControl {
            ModelCatalogProviderControl {
                payload: Some(name.into()),
                ..ModelCatalogProviderControl::default()
            }
        }
        Self {
            openai: payload("openai-aggregator"),
            openai_second: payload("openai-aggregator"),
            deepseek: payload("deepseek"),
            mimo: ModelCatalogProviderControl {
                models: mimo_inventory(true),
                ..ModelCatalogProviderControl::default()
            },
        }
    }

    /// Every instance returns HTTP 401 so discovery falls back to bundled.
    pub fn inventory_reject_all() -> Self {
        let rejected = ModelCatalogProviderControl {
            reject: true,
            ..ModelCatalogProviderControl::default()
        };
        Self {
            openai: rejected.clone(),
            openai_second: rejected.clone(),
            deepseek: rejected.clone(),
            mimo: rejected,
        }
    }

    /// Only `catalog-openai-second` fails; the other instances stay on inventory A.
    pub fn inventory_reject_second() -> Self {
        let mut control = Self::inventory_a();
        control.openai_second = ModelCatalogProviderControl {
            models: Vec::new(),
            reject: true,
            ..ModelCatalogProviderControl::default()
        };
        control
    }

    /// Named presets the acceptance CLI can materialize into a control file.
    pub fn named(name: &str) -> Result<Self> {
        let control = match name {
            "a" | "inventory-a" => Self::inventory_a(),
            "b" | "inventory-b" => Self::inventory_b(),
            "empty" => Self::inventory_empty(),
            "real" => Self::inventory_real(),
            "reject-all" => Self::inventory_reject_all(),
            "reject-second" => Self::inventory_reject_second(),
            other => bail!("unknown model catalog inventory: {other}"),
        };
        // Presets reference embedded payloads, so validate them like a loaded
        // control file instead of trusting the built-in definitions.
        control.validate()?;
        Ok(control)
    }

    fn validate(&self) -> Result<()> {
        for (name, provider) in self.providers() {
            if let Some(status) = provider.status {
                ensure!(
                    (100..600).contains(&status),
                    "{name} status {status} is not an HTTP status"
                );
            }
            for model_id in &provider.models {
                ensure!(
                    !model_id.trim().is_empty(),
                    "{name} contains an empty model model_id"
                );
            }
            if let Some(payload) = provider.payload.as_deref() {
                ensure!(!payload.trim().is_empty(), "{name} payload name is empty");
                ensure!(
                    provider.models.is_empty(),
                    "{name} declares both `models` and `payload`; a payload instance returns the captured response unchanged, so choose one body source"
                );
                let asset = payload_asset(payload)?;
                payload_model_ids(asset.json, &format!("payload `{}`", asset.name))?;
            }
        }
        Ok(())
    }

    fn providers(&self) -> [(&'static str, &ModelCatalogProviderControl); 4] {
        [
            ("openai", &self.openai),
            ("openai-second", &self.openai_second),
            ("deepseek", &self.deepseek),
            ("mimo", &self.mimo),
        ]
    }

    fn entry(&self, provider: CatalogProvider) -> &ModelCatalogProviderControl {
        match provider {
            CatalogProvider::Openai => &self.openai,
            CatalogProvider::OpenaiSecond => &self.openai_second,
            CatalogProvider::DeepSeek => &self.deepseek,
            CatalogProvider::Mimo => &self.mimo,
        }
    }
}

fn mimo_inventory(include_old: bool) -> Vec<String> {
    let mut models = vec![
        "mimo-v2.5-pro".into(),
        "mimo-v2.5".into(),
        "mimo-v2.6-pro".into(),
    ];
    if include_old {
        models.push("fixture-model-old".into());
    }
    models.extend(MIMO_MEDIA_MODEL_IDS.map(str::to_owned));
    models
}

/// Known payload names, joined for error messages.
fn payload_names() -> String {
    PAYLOAD_ASSETS
        .iter()
        .map(|asset| asset.name)
        .collect::<Vec<_>>()
        .join(", ")
}

fn payload_asset(name: &str) -> Result<&'static PayloadAsset> {
    PAYLOAD_ASSETS
        .iter()
        .find(|asset| asset.name == name)
        .with_context(|| {
            format!(
                "unknown model catalog payload `{name}`; known payloads: {}",
                payload_names()
            )
        })
}

/// Extracts the model ids of an OpenAI-compatible `{"data":[{"id":..}]}` list.
///
/// Used both to validate embedded resources at startup and to compare a served
/// payload with its resource in the self-check; anything else is a hard error so
/// a malformed capture can never masquerade as a valid catalog.
fn payload_model_ids(raw: &str, label: &str) -> Result<Vec<String>> {
    let value: Value =
        serde_json::from_str(raw).with_context(|| format!("{label} is not valid JSON"))?;
    let data = value
        .get("data")
        .and_then(Value::as_array)
        .with_context(|| format!("{label} has no `data` array"))?;
    ensure!(!data.is_empty(), "{label} has an empty `data` array");
    let mut ids = Vec::with_capacity(data.len());
    for (index, entry) in data.iter().enumerate() {
        let id = entry
            .get("id")
            .and_then(Value::as_str)
            .with_context(|| format!("{label} entry {index} has no string `id`"))?;
        ensure!(
            !id.trim().is_empty(),
            "{label} entry {index} has an empty `id`"
        );
        ids.push(id.to_owned());
    }
    let unique: BTreeSet<&String> = ids.iter().collect();
    ensure!(
        unique.len() == ids.len(),
        "{label} repeats a model id; real `/models` responses never repeat ids"
    );
    Ok(ids)
}

impl ModelCatalogProviderControl {
    /// Model ids of the selected captured payload, or `None` for a synthesized
    /// [`models`](Self::models) inventory.
    ///
    /// The manual-GUI coordinator uses this to keep the startup route on a model_id
    /// the captured list really contains instead of assuming a fixed one.
    pub fn captured_model_ids(&self) -> Result<Option<Vec<String>>> {
        let Some(name) = self.payload.as_deref() else {
            return Ok(None);
        };
        let asset = payload_asset(name)?;
        Ok(Some(payload_model_ids(
            asset.json,
            &format!("payload `{}`", asset.name),
        )?))
    }
}

fn list_body(owned_by: &str, models: &[String]) -> Value {
    json!({
        "object": "list",
        "data": models.iter().map(|id| json!({
            "id": id,
            "object": "model",
            "owned_by": owned_by,
        })).collect::<Vec<_>>(),
    })
}

fn error_body(message: &str) -> Value {
    json!({
        "error": {
            "code": "fixture_catalog_rejected",
            "message": message,
        }
    })
}

/// Returns a captured response verbatim with `content-type: application/json`.
///
/// Startup validation already parsed every referenced payload, so a failure here
/// only means the control was built without validation; it is reported as a
/// visible 500 instead of a silently synthesized list.
fn payload_response(raw: &str, status: u16) -> Response {
    let mut response = Response::new(Body::from(raw.to_owned()));
    *response.status_mut() =
        StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/json"),
    );
    response
}

async fn respond(state: AppState, provider: CatalogProvider) -> Response {
    let Some(control) = state.model_catalog.as_ref() else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let entry = control.entry(provider);
    if entry.hang {
        // Record before waiting so a coordinator can observe the hang without
        // racing shutdown; the request still blocks until the listener stops.
        state
            .model_catalog_hits
            .record(provider, provider.path(), 503, true);
        state.stopping.cancelled().await;
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    }
    if entry.protocol_error {
        state
            .model_catalog_hits
            .record(provider, provider.path(), 200, true);
        return Json(json!({
            "error": {
                "code": "invalid_request",
                "message": "fixture catalog protocol error",
            },
            "success": false,
        }))
        .into_response();
    }
    let status = entry.status.unwrap_or(if entry.reject { 401 } else { 200 });
    if !(200..300).contains(&status) {
        state
            .model_catalog_hits
            .record(provider, provider.path(), status, true);
        return (
            StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            Json(error_body("fixture rejected the catalog request")),
        )
            .into_response();
    }
    // The payload body replaces the synthesized list only; failure switches
    // above still win, and the captured resource is never rewritten. Resolution
    // happens before recording so an unusable payload is reported as a 500
    // instead of being counted as a healthy catalog GET.
    let payload = match entry.payload.as_deref() {
        None => None,
        Some(name) => match payload_asset(name) {
            Ok(asset) => Some(asset.json),
            Err(error) => {
                state
                    .model_catalog_hits
                    .record(provider, provider.path(), 500, true);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(error_body(&format!("{error:#}"))),
                )
                    .into_response();
            }
        },
    };
    // A captured payload is compared byte-for-byte in the self-check, and product
    // code branches on the body rather than on the reason phrase. Serving it as
    // 200 keeps payload and synthesized-list modes identical for any 2xx
    // `status`; every failure switch above still wins.
    let status = if payload.is_some() { 200 } else { status };
    state
        .model_catalog_hits
        .record(provider, provider.path(), status, false);
    match payload {
        Some(raw) => payload_response(raw, status),
        None => Json(list_body(provider.owned_by(), &entry.models)).into_response(),
    }
}

pub(super) async fn openai_models(State(state): State<AppState>) -> Response {
    respond(state, CatalogProvider::Openai).await
}

pub(super) async fn openai_second_models(State(state): State<AppState>) -> Response {
    respond(state, CatalogProvider::OpenaiSecond).await
}

pub(super) async fn deepseek_models(State(state): State<AppState>) -> Response {
    respond(state, CatalogProvider::DeepSeek).await
}

pub(super) async fn mimo_models(State(state): State<AppState>) -> Response {
    respond(state, CatalogProvider::Mimo).await
}

/// Returns why a payload instance cannot serve its capture, or `None` when the
/// success path applies. Failure switches keep their existing priority, so a
/// payload under test is compared only when nothing overrides the 200 body.
fn payload_skip_reason(entry: &ModelCatalogProviderControl, status: u16) -> Option<&'static str> {
    if entry.protocol_error {
        Some("protocolError wins")
    } else if !(200..300).contains(&status) {
        Some("status outside 2xx; a failure switch wins")
    } else {
        None
    }
}

/// Probes the four catalog endpoints of a listening fixture and prints one line
/// per path. Hanging providers are skipped so the check can finish.
///
/// Payload instances are verified against their embedded resource: the served
/// body must match the capture byte-for-byte, be served as HTTP 200 and expose
/// exactly its model ids. A failure switch means the capture is not served at
/// all, so the comparison is skipped like a hang instead of masking the switch
/// under test.
pub async fn self_check(address: SocketAddr, control: &ModelCatalogControl) -> Result<()> {
    for (provider, entry) in [
        (CatalogProvider::Openai, &control.openai),
        (CatalogProvider::OpenaiSecond, &control.openai_second),
        (CatalogProvider::DeepSeek, &control.deepseek),
        (CatalogProvider::Mimo, &control.mimo),
    ] {
        if entry.hang {
            println!(
                "{} skipped=hang (probe continues until shutdown)",
                provider.path()
            );
            continue;
        }
        let (status, body) = get_path(address, provider.path()).await?;
        if let Some(name) = entry.payload.as_deref() {
            let asset = payload_asset(name)?;
            let resource_ids = payload_model_ids(asset.json, &format!("payload `{name}`"))?;
            if let Some(reason) = payload_skip_reason(entry, status) {
                println!(
                    "{} status={status} payload={name} ids=skipped({reason})",
                    provider.path()
                );
                continue;
            }
            let returned_ids = payload_model_ids(&body, &format!("{} response", provider.path()))?;
            let expected: BTreeSet<&str> = resource_ids.iter().map(String::as_str).collect();
            let actual: BTreeSet<&str> = returned_ids.iter().map(String::as_str).collect();
            ensure!(
                actual == expected,
                "{} payload `{name}` ids diverge from the embedded resource: resource={expected:?} fixture={actual:?}",
                provider.path()
            );
            ensure!(
                status == 200,
                "{} payload `{name}` served status {status}; a captured payload is always HTTP 200",
                provider.path()
            );
            ensure!(
                body == asset.json,
                "{} payload `{name}` body differs from the embedded resource byte-for-byte",
                provider.path()
            );
            let image = returned_ids
                .iter()
                .filter(|id| id.starts_with(IMAGE_MODEL_ID_PREFIX))
                .count();
            println!(
                "{} status={status} payload={name} ids={} image={} non_image={} ids_match=true body_match=true",
                provider.path(),
                returned_ids.len(),
                image,
                returned_ids.len() - image
            );
            continue;
        }
        let preview: Value = serde_json::from_str(&body).unwrap_or(Value::String(body.clone()));
        println!(
            "{} status={status} body={}",
            provider.path(),
            serde_json::to_string(&preview)?
        );
    }
    Ok(())
}

/// Reads one catalog GET and returns its status and **untrimmed** body, so a
/// payload self-check compares the served bytes with the resource as-is instead
/// of a pre-trimmed copy that would hide a diverging trailing newline.
async fn get_path(address: SocketAddr, path: &str) -> Result<(u16, String)> {
    let mut stream = tokio::time::timeout(Duration::from_secs(3), TcpStream::connect(address))
        .await
        .context("catalog self-check connect timed out")?
        .with_context(|| format!("catalog self-check could not connect to {address}"))?;
    let request = format!("GET {path} HTTP/1.1\r\nHost: {address}\r\nConnection: close\r\n\r\n");
    stream.write_all(request.as_bytes()).await?;
    let mut bytes = Vec::new();
    stream.read_to_end(&mut bytes).await?;
    let text = String::from_utf8_lossy(&bytes);
    let (head, body) = text.split_once("\r\n\r\n").unwrap_or((text.as_ref(), ""));
    let status = head
        .split_whitespace()
        .nth(1)
        .and_then(|value| value.parse().ok())
        .context("catalog self-check response had no HTTP status")?;
    Ok((status, body.to_owned()))
}

/// Starts catalog GETs against hanging providers so shutdown can record them.
pub async fn kick_hang_probes(
    address: SocketAddr,
    control: &ModelCatalogControl,
) -> Vec<tokio::task::JoinHandle<Result<(u16, String)>>> {
    let mut tasks = Vec::new();
    for (provider, entry) in [
        (CatalogProvider::Openai, &control.openai),
        (CatalogProvider::OpenaiSecond, &control.openai_second),
        (CatalogProvider::DeepSeek, &control.deepseek),
        (CatalogProvider::Mimo, &control.mimo),
    ] {
        if entry.hang {
            let path = provider.path();
            tasks.push(tokio::spawn(async move { get_path(address, path).await }));
        }
    }
    tasks
}
