//! Standard HTTP proxy with TLS termination for the official ACP host.
//!
//! The product reaches the fixed Google distribution URL through the ordinary
//! `HTTPS_PROXY` contract: the acceptance harness exports the proxy address and an
//! isolated CA file, so `reqwest`/rustls performs a real CONNECT, a real TLS
//! handshake and real certificate validation. This peer only answers for that one
//! official host, never forwards traffic, and only listens on loopback.

use std::convert::Infallible;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, ensure};
use http_body_util::combinators::BoxBody;
use http_body_util::{BodyExt, Full, StreamBody};
use hyper::body::{Bytes, Frame, Incoming};
use hyper::header;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use rustls::ServerConfig;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;

use super::archive::ArchiveBuild;
use super::certs::{Certs, DISTRIBUTION_HOST};
use super::control::{AcpInstallControl, RedirectTarget};
use super::fixed;
use super::state;

/// Official distribution path prefix.
pub const ARCHIVE_PREFIX: &str = "/agy-extensions/releases/";

type ResponseBody = BoxBody<Bytes, std::io::Error>;

/// One served lifecycle.
pub struct ProxyState {
    control: AcpInstallControl,
    target: String,
    archive: ArchiveBuild,
    archive_etag: String,
    acceptor: TlsAcceptor,
    log: Mutex<std::fs::File>,
    sequence: AtomicU64,
    connects: AtomicU32,
    archive_requests: AtomicU32,
    archive_failures: AtomicU32,
    archive_drops: AtomicU32,
    archive_redirects: AtomicU32,
    /// 记录尝试数与成功数：两者不等说明日志丢过行，最终证据必须失败。
    log_attempts: AtomicU64,
    log_successes: AtomicU64,
    log_error: Mutex<Option<String>>,
}

/// Starts the peer on an ephemeral loopback port and serves until a stop signal
/// or the control stop file asks it to finish.
pub async fn serve(
    state_dir: PathBuf,
    control: AcpInstallControl,
    target: String,
    archive: ArchiveBuild,
    certs: Certs,
) -> Result<()> {
    let archive_etag = format!("\"fixture-archive-{}\"", archive.sha256);
    let acceptor = TlsAcceptor::from(Arc::new(tls_config(&certs)?));
    let log = state::open_requests(&state_dir)?;
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .context("failed to bind the ACP install fixture proxy")?;
    let address = listener.local_addr()?;
    ensure!(
        address.ip().is_loopback(),
        "the ACP install fixture proxy must stay on loopback"
    );
    let state = Arc::new(ProxyState {
        control,
        target,
        archive,
        archive_etag,
        acceptor,
        log: Mutex::new(log),
        sequence: AtomicU64::new(0),
        connects: AtomicU32::new(0),
        archive_requests: AtomicU32::new(0),
        archive_failures: AtomicU32::new(0),
        archive_drops: AtomicU32::new(0),
        archive_redirects: AtomicU32::new(0),
        log_attempts: AtomicU64::new(0),
        log_successes: AtomicU64::new(0),
        log_error: Mutex::new(None),
    });
    state::write_ready(&state_dir, &state.ready(address, &certs))?;

    // Every connection and tunnel handler is registered in one tracker. Stopping
    // the peer closes admission first, then cancels and joins the handlers; the
    // final report is only written after they are gone, so "stopped" cannot hide
    // a live task.
    let tracker = tokio_util::task::TaskTracker::new();
    let cancel = tokio_util::sync::CancellationToken::new();
    let stop_file = state.control.stop_file.clone();
    let stop = wait_for_stop();
    tokio::pin!(stop);
    loop {
        tokio::select! {
                _ = &mut stop => break,
                _ = tokio::time::sleep(Duration::from_millis(200)) => {
                    if stop_file.as_ref().is_some_and(|path| path.is_file()) {
                        break;
                    }
                }
                accepted = listener.accept() => {
                    let (stream, peer) = accepted?;
                    let state = Arc::clone(&state);
                    let connection_cancel = cancel.clone();
                let service_cancel = cancel.clone();
                    let handler_tracker = tracker.clone();
                    tracker.spawn(async move {
                        let logging = Arc::clone(&state);
                        let service = service_fn(move |request| {
                            handle_connect(
                                Arc::clone(&state),
                                request,
                                handler_tracker.clone(),
                            service_cancel.clone(),
                            )
                        });
                        let connection = http1::Builder::new()
                            .serve_connection(TokioIo::new(stream), service)
                            .with_upgrades();
                        tokio::select! {
                            result = connection => {
                                if let Err(error) = result {
                            logging.log(serde_json::json!({
                                "kind": "connectionError",
                                "peer": peer.to_string(),
                                "message": error.to_string(),
                            }));
                        }
                }
                            _ = connection_cancel.cancelled() => {}
            }
                    });
        }
            }
    }
    tracker.close();
    let closed = tokio::time::timeout(Duration::from_secs(10), async {
        cancel.cancel();
        tracker.wait().await;
    })
    .await
    .is_ok();
    // 报告只在所有 handler 收束后写；日志丢行时报告必须标为不完整，进程也不能
    // 以成功退出掩盖它。
    let log_complete = state.log_complete();
    state::write_report(&state_dir, &state.report(address, closed && log_complete))?;
    ensure!(
        closed,
        "the ACP install fixture proxy did not close every handler within the shutdown budget"
    );
    ensure!(
        log_complete,
        "the ACP install fixture request log lost records; the evidence is incomplete"
    );
    Ok(())
}

/// Resolves when the operating system asks the peer to stop.
///
/// On Unix the harness sends a normal SIGTERM/SIGINT to the peer's process
/// group; on Windows only the portable Ctrl-C notification exists, so the peer
/// additionally honours its control stop file there. Both paths end the server
/// loop so the final report is written; neither is used by production code.
async fn wait_for_stop() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{SignalKind, signal};
        let mut terminate = match signal(SignalKind::terminate()) {
            Ok(signal) => signal,
            Err(_) => return,
        };
        let mut interrupt = match signal(SignalKind::interrupt()) {
            Ok(signal) => signal,
            Err(_) => return,
        };
        tokio::select! {
            _ = terminate.recv() => {}
            _ = interrupt.recv() => {}
        }
    }
    #[cfg(windows)]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}

impl ProxyState {
    fn ready(&self, address: SocketAddr, certs: &Certs) -> serde_json::Value {
        let archive_url = fixed::archive_url(&self.target).unwrap_or_default();
        serde_json::json!({
            "proxyAddress": address.to_string(),
            "proxyUrl": format!("http://{address}"),
            "archiveUrl": archive_url,
            "target": self.target,
            "version": fixed::SERVER_VERSION,
            "archiveSha256": self.archive.sha256,
            "archiveBytes": self.archive.bytes.len(),
            "programMember": self.archive.program_member,
            "members": self.archive.members,
            "caPem": certs.ca_pem,
            "variant": self.control.archive.variant,
            "agentControlMember": fixed::AGENT_CONTROL_MEMBER,
            "agentStateDir": self.control.archive.agent_state_dir,
            "hosts": [DISTRIBUTION_HOST],
        })
    }

    fn report(&self, address: SocketAddr, closed: bool) -> serde_json::Value {
        serde_json::json!({
            "proxyAddress": address.to_string(),
            "closed": closed,
            "target": self.target,
            "version": fixed::SERVER_VERSION,
            "archiveSha256": self.archive.sha256,
            "archiveBytes": self.archive.bytes.len(),
            "connects": self.connects.load(Ordering::SeqCst),
            "archiveRequests": self.archive_requests.load(Ordering::SeqCst),
            "archiveFailures": self.archive_failures.load(Ordering::SeqCst),
            "archiveDrops": self.archive_drops.load(Ordering::SeqCst),
            "archiveRedirects": self.archive_redirects.load(Ordering::SeqCst),
            "requestLog": {
                "attempted": self.log_attempts.load(Ordering::SeqCst),
                "succeeded": self.log_successes.load(Ordering::SeqCst),
                "failed": !self.log_complete(),
                "firstError": self.log_error.lock().ok().and_then(|slot| slot.clone()),
            },
        })
    }

    fn next_sequence(&self) -> u64 {
        self.sequence.fetch_add(1, Ordering::SeqCst) + 1
    }

    /// 追加一条证据记录：失败会被计数、保留首个错误并打印，绝不当成成功。
    fn log(&self, entry: serde_json::Value) {
        self.log_attempts.fetch_add(1, Ordering::SeqCst);
        match state::append_request(&self.log, &entry) {
            Ok(()) => {
                self.log_successes.fetch_add(1, Ordering::SeqCst);
            }
            Err(error) => {
                eprintln!("anywork ACP install fixture: request log failure: {error:#}");
                if let Ok(mut slot) = self.log_error.lock()
                    && slot.is_none()
                {
                    *slot = Some(format!("{error:#}"));
                }
            }
        }
    }

    /// 日志完整性：尝试数必须等于成功数，且从未记录过独立失败。
    fn log_complete(&self) -> bool {
        let attempts = self.log_attempts.load(Ordering::SeqCst);
        let successes = self.log_successes.load(Ordering::SeqCst);
        attempts == successes
            && self
                .log_error
                .lock()
                .map(|slot| slot.is_none())
                .unwrap_or(false)
    }
}

fn tls_config(certs: &Certs) -> Result<ServerConfig> {
    let provider = rustls::crypto::aws_lc_rs::default_provider();
    let config = ServerConfig::builder_with_provider(Arc::new(provider))
        .with_safe_default_protocol_versions()
        .context("failed to select the fixture TLS protocol versions")?
        .with_no_client_auth()
        .with_single_cert(
            vec![CertificateDer::from(certs.leaf_der.clone())],
            PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(certs.key_der.clone())),
        )
        .context("failed to install the fixture leaf certificate")?;
    let mut config = config;
    // The peer answers HTTP/1.1 inside the tunnel; no other ALPN protocol is
    // offered, so a client that prefers h2 falls back instead of failing.
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(config)
}

async fn handle_connect(
    state: Arc<ProxyState>,
    mut request: Request<Incoming>,
    tracker: tokio_util::task::TaskTracker,
    cancel: tokio_util::sync::CancellationToken,
) -> Result<Response<ResponseBody>, Infallible> {
    let sequence = state.next_sequence();
    if request.method() != Method::CONNECT {
        state.log(serde_json::json!({
            "seq": sequence,
            "kind": "rejectedPlainRequest",
            "method": request.method().to_string(),
            "uri": request.uri().to_string(),
            "status": 405,
        }));
        return Ok(simple(StatusCode::METHOD_NOT_ALLOWED, Vec::new()));
    }
    let authority = request
        .uri()
        .authority()
        .map(ToString::to_string)
        .unwrap_or_default();
    let (host, port) = authority
        .rsplit_once(':')
        .map_or((authority.as_str(), 443), |(host, port)| {
            (host, port.parse::<u16>().unwrap_or(0))
        });
    if port != 443 || host != DISTRIBUTION_HOST {
        state.log(serde_json::json!({
            "seq": sequence,
            "kind": "rejectedTunnel",
            "authority": authority,
            "status": 403,
        }));
        return Ok(simple(StatusCode::FORBIDDEN, Vec::new()));
    }
    state.connects.fetch_add(1, Ordering::SeqCst);
    let on_upgrade = hyper::upgrade::on(&mut request);
    let host = host.to_owned();
    state.log(serde_json::json!({
        "seq": sequence,
        "kind": "connect",
        "host": host,
        "status": 200,
        "atMs": now_ms(),
    }));
    let tunnel_state = Arc::clone(&state);
    tracker.spawn(async move {
        tokio::select! {
            _ = cancel.cancelled() => {}
            result = async {
                match on_upgrade.await {
                    Ok(upgraded) => {
                        serve_tunnel(
                            Arc::clone(&tunnel_state),
                            &host,
                            TokioIo::new(upgraded),
                            cancel.clone(),
                        )
                        .await
            }
                    Err(error) => Err(anyhow::anyhow!("upgrade failed: {error}")),
        }
            } => {
                if let Err(error) = result {
                    tunnel_state.log(serde_json::json!({
                        "kind": "tunnelError",
                        "host": host,
                        "message": error.to_string(),
                    }));
                }
            }
        }
    });
    Ok(simple(StatusCode::OK, Vec::new()))
}

async fn serve_tunnel<I>(
    state: Arc<ProxyState>,
    host: &str,
    io: I,
    cancel: tokio_util::sync::CancellationToken,
) -> Result<()>
where
    I: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let tls = state
        .acceptor
        .accept(io)
        .await
        .context("the fixture TLS handshake failed")?;
    let host = host.to_owned();
    let service =
        service_fn(move |request| handle_official(Arc::clone(&state), host.clone(), request));
    let connection = http1::Builder::new().serve_connection(TokioIo::new(tls), service);
    tokio::select! {
            result = connection => result.context("the fixture HTTPS connection failed"),
            _ = cancel.cancelled() => Ok(()),
    }
}

async fn handle_official(
    state: Arc<ProxyState>,
    host: String,
    request: Request<Incoming>,
) -> Result<Response<ResponseBody>, Infallible> {
    let sequence = state.next_sequence();
    let path = request.uri().path().to_owned();
    // 生产只访问固定的 Google 分发地址：registry 元数据端点已删除，peer 不再提供。
    let response = if host == DISTRIBUTION_HOST && path.starts_with(ARCHIVE_PREFIX) {
        archive_response(&state, &request).await
    } else {
        Ok(simple(StatusCode::NOT_FOUND, Vec::new()))
    };
    let response = match response {
        Ok(response) => response,
        Err(error) => {
            state.log(serde_json::json!({
                "seq": sequence,
                "host": host,
                "path": path,
                "kind": "handlerError",
                "message": error.to_string(),
            }));
            simple(StatusCode::INTERNAL_SERVER_ERROR, Vec::new())
        }
    };
    state.log(serde_json::json!({
        "seq": sequence,
        "kind": "request",
        "host": host,
        "method": request.method().to_string(),
        "path": path,
        "range": header_str(&request, header::RANGE),
        "ifRange": header_str(&request, header::IF_RANGE),
        "ifNoneMatch": header_str(&request, header::IF_NONE_MATCH),
        "status": response.status().as_u16(),
        "etag": response
            .headers()
            .get(header::ETAG)
            .and_then(|value| value.to_str().ok()),
        "contentRange": response
            .headers()
            .get(header::CONTENT_RANGE)
            .and_then(|value| value.to_str().ok()),
        "contentLength": response
            .headers()
            .get(header::CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok()),
        "atMs": now_ms(),
    }));
    Ok(response)
}

/// One redirect response for the fixed archive URL.
///
/// The product validates every hop against the fixed official source policy; these
/// samples keep that rejection reachable now that no registry document is fetched.
fn archive_redirect(
    state: &Arc<ProxyState>,
    target: RedirectTarget,
    served: u32,
) -> Result<Response<ResponseBody>> {
    let path = fixed::archive_path(&state.target).context("no fixed archive path for target")?;
    let location = match target {
        RedirectTarget::AllowedPath => {
            format!("https://{DISTRIBUTION_HOST}{path}?hop={served}")
        }
        RedirectTarget::ForeignHost => format!("https://example.invalid{path}"),
        RedirectTarget::PlainHttp => format!("http://{DISTRIBUTION_HOST}{path}"),
        RedirectTarget::Loop => format!("https://{DISTRIBUTION_HOST}{path}"),
    };
    state.archive_redirects.fetch_add(1, Ordering::SeqCst);
    Ok(Response::builder()
        .status(StatusCode::FOUND)
        .header(header::LOCATION, location)
        .body(empty())?)
}

async fn archive_response(
    state: &Arc<ProxyState>,
    request: &Request<Incoming>,
) -> Result<Response<ResponseBody>> {
    let control = &state.control.archive;
    let served = state.archive_requests.fetch_add(1, Ordering::SeqCst) + 1;
    // Redirect samples stay on the fixed archive URL: the product validates each
    // hop against the official source policy, so a removed registry document must
    // not take this security case with it.
    if served <= control.redirects {
        let target = control
            .redirect_target
            .unwrap_or(RedirectTarget::AllowedPath);
        return archive_redirect(state, target, served);
    }
    if served <= control.fail_requests {
        state.archive_failures.fetch_add(1, Ordering::SeqCst);
        return Ok(Response::builder()
            .status(StatusCode::SERVICE_UNAVAILABLE)
            .header(header::RETRY_AFTER, "1")
            .body(empty())?);
    }
    // Scripted runs may change the validator between requests; everything else
    // keeps the single run validator and the historical behaviour.
    let base_etag = control
        .etag
        .clone()
        .unwrap_or_else(|| state.archive_etag.clone());
    let step = control.script.get(served.saturating_sub(1) as usize);
    let etag = step
        .and_then(|step| step.etag.clone())
        .unwrap_or_else(|| base_etag.clone());
    if header_str(request, header::IF_NONE_MATCH).as_deref() == Some(etag.as_str()) {
        return Ok(Response::builder()
            .status(StatusCode::NOT_MODIFIED)
            .header(header::ETAG, etag)
            .body(empty())?);
    }
    let total = state.archive.bytes.len() as u64;
    ensure!(
        total > 0,
        "the fixture archive must contain at least one byte"
    );
    // A conditional range only applies while the client still holds this exact
    // representation; a changed or missing validator falls back to the full body
    // (RFC 9110 §13.1.5), never to a stale partial response.
    let if_range = header_str(request, header::IF_RANGE);
    // If-Range names the representation the client already holds: that is the
    // previous response's validator, not the one this response will carry.
    let previous_etag = if served >= 2 {
        control
            .script
            .get((served - 2) as usize)
            .and_then(|step| step.etag.clone())
            .unwrap_or_else(|| base_etag.clone())
    } else {
        base_etag.clone()
    };
    let range_applies = if_range
        .as_deref()
        .is_none_or(|value| value == previous_etag);
    let requested_range = header_str(request, header::RANGE);
    let (start, end) = match requested_range.as_deref() {
        Some(value) if range_applies => match parse_single_range(value, total) {
            Ok(bounds) => bounds,
            Err(()) => {
                return Ok(Response::builder()
                    .status(StatusCode::RANGE_NOT_SATISFIABLE)
                    .header(header::CONTENT_RANGE, format!("bytes */{total}"))
                    .header(header::ETAG, etag)
                    .body(empty())?);
            }
        },
        _ => (0, total - 1),
    };
    let partial = requested_range.is_some() && range_applies;
    let length = end - start + 1;
    let drop_after = match step {
        Some(step) => step.drop_after_bytes,
        None => (served <= control.drop_requests)
            .then_some(control.drop_after_bytes)
            .flatten(),
    };
    if drop_after.is_some() {
        state.archive_drops.fetch_add(1, Ordering::SeqCst);
        state.log(serde_json::json!({
            "kind": "archiveDrop",
            "served": served,
            "etag": etag,
            "offset": start,
        }));
    }
    let stream = StreamState {
        bytes: Arc::clone(&state.archive.bytes),
        offset: start as usize,
        end: (end + 1) as usize,
        chunk: control.chunk_bytes,
        delay: Duration::from_millis(control.chunk_delay_ms),
        drop_after,
        sent: 0,
    };
    let body = StreamBody::new(futures::stream::unfold(stream, next_chunk)).boxed();
    let mut builder = Response::builder()
        .status(if partial {
            StatusCode::PARTIAL_CONTENT
        } else {
            StatusCode::OK
        })
        .header(header::CONTENT_TYPE, "application/zip")
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::ETAG, etag);
    if partial {
        builder = builder.header(
            header::CONTENT_RANGE,
            format!("bytes {start}-{end}/{total}"),
        );
    }
    // A partial response always carries its exact length; an unknown total is only
    // expressed on a full body.
    if partial || !control.unknown_length {
        builder = builder.header(header::CONTENT_LENGTH, length.to_string());
    }
    Ok(builder.body(body)?)
}

struct StreamState {
    bytes: Arc<Vec<u8>>,
    offset: usize,
    /// Exclusive end of this response body.
    end: usize,
    chunk: Option<usize>,
    delay: Duration,
    drop_after: Option<u64>,
    sent: u64,
}

async fn next_chunk(
    mut state: StreamState,
) -> Option<(std::io::Result<Frame<Bytes>>, StreamState)> {
    if let Some(drop_after) = state.drop_after {
        let remaining = drop_after.saturating_sub(state.sent);
        if remaining == 0 {
            // An aborted body is terminal: the transfer can never resume after the
            // injected failure, so the client observes a real truncated response.
            state.offset = state.end;
            state.drop_after = None;
            return Some((
                Err(std::io::Error::new(
                    std::io::ErrorKind::UnexpectedEof,
                    "fixture archive body aborted",
                )),
                state,
            ));
        }
    }
    if state.offset >= state.end {
        return None;
    }
    if !state.delay.is_zero() {
        tokio::time::sleep(state.delay).await;
    }
    let mut end = match state.chunk {
        Some(chunk) => (state.offset + chunk).min(state.end),
        None => state.end,
    };
    if let Some(drop_after) = state.drop_after {
        let remaining = drop_after.saturating_sub(state.sent) as usize;
        end = end.min(state.offset + remaining.max(1));
    }
    let chunk = Bytes::copy_from_slice(&state.bytes[state.offset..end]);
    state.offset = end;
    state.sent += chunk.len() as u64;
    Some((Ok(Frame::data(chunk)), state))
}

/// Parses one standard single-range request into inclusive byte bounds.
///
/// Multiple ranges are not implemented: a real proxy would answer them with a
/// multipart body, and the fixture deliberately rejects them instead of pretending
/// to support a form the product never sends.
fn parse_single_range(value: &str, total: u64) -> Result<(u64, u64), ()> {
    let spec = value.strip_prefix("bytes=").ok_or(())?.trim();
    if spec.contains(',') {
        return Err(());
    }
    let (start, end) = spec.split_once('-').ok_or(())?;
    if start.is_empty() {
        let suffix = end.parse::<u64>().map_err(|_| ())?;
        if suffix == 0 || total == 0 {
            return Err(());
        }
        let length = suffix.min(total);
        return Ok((total - length, total - 1));
    }
    let start = start.parse::<u64>().map_err(|_| ())?;
    if start >= total {
        return Err(());
    }
    let end = if end.is_empty() {
        total - 1
    } else {
        end.parse::<u64>().map_err(|_| ())?.min(total - 1)
    };
    if end < start {
        return Err(());
    }
    Ok((start, end))
}

fn header_str(request: &Request<Incoming>, name: header::HeaderName) -> Option<String> {
    request
        .headers()
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned)
}

fn simple(status: StatusCode, body: Vec<u8>) -> Response<ResponseBody> {
    let mut response = Response::new(full(body));
    *response.status_mut() = status;
    response
}

fn empty() -> ResponseBody {
    full(Vec::new())
}

fn full(body: Vec<u8>) -> ResponseBody {
    Full::new(Bytes::from(body))
        .map_err(|never: Infallible| match never {})
        .boxed()
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_millis() as u64)
}
