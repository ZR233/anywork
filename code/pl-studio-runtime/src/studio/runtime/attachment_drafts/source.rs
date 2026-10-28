//! 附件来源读取：本地文件读取与受约束的 HTTPS 远程快照下载（重定向、公网地址与字节上限）。

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use futures::StreamExt;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use reqwest::header::LOCATION;
use tokio::io::AsyncReadExt;
use tokio_util::sync::CancellationToken;
use url::{Host, Url};

const MAX_REDIRECTS: usize = 3;
const REMOTE_FETCH_TOTAL_TIMEOUT: Duration = Duration::from_secs(45);

pub(super) async fn read_local_file(path: &Path, max_bytes: u64) -> Result<Vec<u8>> {
    // Refuse directories/devices/FIFOs before opening; recheck the opened handle below.
    let metadata = tokio::fs::metadata(path)
        .await
        .context(StudioError::invalid_argument("无法读取附件的文件信息。"))?;
    ensure!(
        metadata.is_file(),
        StudioError::invalid_argument("附件必须是常规文件，不能是目录。")
    );
    ensure!(
        metadata.len() <= max_bytes,
        StudioError::invalid_argument("附件文件大小超过限制。")
    );
    let file = tokio::fs::File::open(path)
        .await
        .context(StudioError::invalid_argument(
            "无法打开附件，请检查文件是否存在及访问权限。",
        ))?;
    let metadata = file
        .metadata()
        .await
        .context(StudioError::invalid_argument("无法读取附件的文件信息。"))?;
    ensure!(
        metadata.is_file(),
        StudioError::invalid_argument("附件必须是常规文件，不能是目录。")
    );
    ensure!(
        metadata.len() <= max_bytes,
        StudioError::invalid_argument("附件文件大小超过限制。")
    );
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.take(max_bytes.saturating_add(1))
        .read_to_end(&mut bytes)
        .await
        .context(StudioError::invalid_argument(
            "无法读取附件内容，请重新选择文件。",
        ))?;
    ensure!(
        bytes.len() as u64 <= max_bytes,
        StudioError::invalid_argument("附件文件大小超过限制。")
    );
    Ok(bytes)
}

pub(super) struct LoadedSource {
    // The archived snapshot, not the original URL, is the authority for native input and replay.
    // Retaining an initial_remote_url here would allow a mutable remote source to replace it.
    pub(super) bytes: Vec<u8>,
}

pub(super) async fn fetch_remote_snapshot(
    raw_url: &str,
    max_bytes: u64,
    cancellation: &CancellationToken,
) -> Result<LoadedSource> {
    tokio::time::timeout(
        REMOTE_FETCH_TOTAL_TIMEOUT,
        fetch_remote_snapshot_with_redirects(raw_url, max_bytes, cancellation),
    )
    .await
    .context("attachment URL fetch exceeded the total timeout")?
}

async fn fetch_remote_snapshot_with_redirects(
    raw_url: &str,
    max_bytes: u64,
    cancellation: &CancellationToken,
) -> Result<LoadedSource> {
    let mut url = validate_remote_url(Url::parse(raw_url).context("invalid attachment URL")?)?;
    for redirect in 0..=MAX_REDIRECTS {
        if cancellation.is_cancelled() {
            return Err(remote_cancelled());
        }
        let port = url
            .port_or_known_default()
            .context("attachment URL has no port")?;
        // Url::host_str() includes brackets for IPv6. Use its typed host instead of treating a
        // failed IpAddr parse as a domain/IP validation success (url's host API contract).
        let host = url.host().context("attachment URL has no host")?;
        let addresses = match host {
            Host::Ipv4(ip) => vec![SocketAddr::new(IpAddr::V4(ip), port)],
            Host::Ipv6(ip) => vec![SocketAddr::new(IpAddr::V6(ip), port)],
            Host::Domain(domain) => tokio::net::lookup_host((domain, port))
                .await
                .context("attachment URL host cannot be resolved")?
                .collect::<Vec<_>>(),
        };
        ensure!(
            !addresses.is_empty(),
            "attachment URL host has no addresses"
        );
        for address in &addresses {
            ensure_public_ip(address.ip())?;
        }
        if cancellation.is_cancelled() {
            return Err(remote_cancelled());
        }
        let mut builder = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30));
        if let Host::Domain(domain) = host {
            // reqwest's DNS override binds *all* checked A/AAAA results without a second lookup.
            // Literals are already typed/checked above and reqwest connects to that literal.
            builder = builder.resolve_to_addrs(domain, &addresses);
        }
        let client = builder.build()?;
        let response = tokio::select! {
            biased;
            _ = cancellation.cancelled() => return Err(remote_cancelled()),
            response = client.get(url.clone()).send() => response.context("attachment URL fetch failed")?,
        };
        if response.status().is_redirection() {
            ensure!(
                redirect < MAX_REDIRECTS,
                "attachment URL has too many redirects"
            );
            let location = response
                .headers()
                .get(LOCATION)
                .context("attachment redirect has no Location")?
                .to_str()
                .context("attachment redirect Location is invalid")?;
            url = validate_remote_url(url.join(location).context("invalid attachment redirect")?)?;
            continue;
        }
        ensure!(
            response.status().is_success(),
            "attachment URL returned an error status"
        );
        if let Some(length) = response.content_length() {
            ensure!(length <= max_bytes, "remote attachment is too large");
        }
        let mut bytes = Vec::new();
        let mut stream = response.bytes_stream();
        loop {
            let chunk = tokio::select! {
                biased;
                _ = cancellation.cancelled() => return Err(remote_cancelled()),
                chunk = stream.next() => chunk,
            };
            let Some(chunk) = chunk else { break };
            let chunk = chunk.context("remote attachment stream failed")?;
            ensure!(
                bytes.len().saturating_add(chunk.len()) as u64 <= max_bytes,
                "remote attachment is too large"
            );
            bytes.extend_from_slice(&chunk);
        }
        return Ok(LoadedSource { bytes });
    }
    bail!("attachment URL redirect handling failed")
}

pub(super) fn validate_remote_url(url: Url) -> Result<Url> {
    ensure!(url.scheme() == "https", "attachment URL must use HTTPS");
    ensure!(
        url.username().is_empty(),
        "attachment URL must not contain credentials"
    );
    ensure!(
        url.password().is_none(),
        "attachment URL must not contain credentials"
    );
    ensure!(
        url.fragment().is_none(),
        "attachment URL must not contain a fragment"
    );
    match url.host().context("attachment URL has no host")? {
        Host::Ipv4(ip) => ensure_public_ip(IpAddr::V4(ip))?,
        Host::Ipv6(ip) => ensure_public_ip(IpAddr::V6(ip))?,
        Host::Domain(domain) => ensure!(
            !domain
                .trim_end_matches('.')
                .eq_ignore_ascii_case("localhost"),
            "attachment URL host is not public"
        ),
    }
    Ok(url)
}

fn ensure_public_ip(ip: IpAddr) -> Result<()> {
    let public = match ip {
        IpAddr::V4(ip) => is_public_ipv4(ip),
        IpAddr::V6(ip) => is_public_ipv6(ip),
    };
    ensure!(public, "attachment URL resolved to a non-public address");
    Ok(())
}

fn is_public_ipv4(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    // Conservative HTTPS origin policy, not a replacement for unstable std::is_global:
    // https://www.iana.org/assignments/iana-ipv4-special-registry/ (2025-10-09).
    // Reject every special-purpose prefix, even globally reachable protocol/anycast services;
    // std's stable private/link-local/documentation helpers cover the ordinary reserved ranges.
    !(ip.is_private()
        || ip.is_loopback()
        || ip.is_link_local()
        || ip.is_broadcast()
        || ip.is_documentation()
        || ip.is_multicast()
        || ip.is_unspecified()
        || octets[0] == 0
        || octets[0] >= 240
        || (octets[0] == 100 && (64..=127).contains(&octets[1]))
        || (octets[0] == 198 && (18..=19).contains(&octets[1]))
        || matches!(
            octets,
            [192, 0, 0, _]
                | [192, 31, 196, _]
                | [192, 52, 193, _]
                | [192, 88, 99, _]
                | [192, 175, 48, _]
        ))
}

fn is_public_ipv6(ip: Ipv6Addr) -> bool {
    if let Some(ipv4) = ip.to_ipv4_mapped() {
        return is_public_ipv4(ipv4);
    }
    let segments = ip.segments();
    // Native IPv6 HTTPS origins must be in the currently allocated RIR unicast prefixes:
    // https://www.iana.org/assignments/ipv6-unicast-address-assignments/ (2025-10-10).
    // The rest of 2000::/3 is reserved for future allocation; testing only its first bits
    // would admit reserved space (including the returned 6bone prefix). These explicit ranges
    // are this origin policy's conservative snapshot, not a general IP classification engine.
    // https://www.iana.org/assignments/iana-ipv6-special-registry/ (2025-10-09).
    // Protocol assignments, transition, local, multicast and unallocated ranges are not RIR
    // origins. Only documentation and AS112 special-purpose subranges remain inside this set.
    let allocated = match segments {
        [0x2001, second, ..] => matches!(second,
            0x0200..=0x0fff | 0x1200..=0x3fff | 0x4000..=0x4dff
            | 0x5000..=0x5fff | 0x8000..=0xbfff),
        [0x2003, second, ..] => second <= 0x3fff,
        [0x2610 | 0x2620, second, ..] => second <= 0x01ff,
        [first, ..] => matches!(first, 0x2400..=0x241f | 0x2600..=0x260f
            | 0x2630..=0x263f | 0x2800..=0x280f | 0x2a00..=0x2a1f | 0x2c00..=0x2c0f),
    };
    allocated
        && !(segments[0] == 0x2001 && segments[1] == 0x0db8)
        && !(segments[0] == 0x2620 && segments[1] == 0x004f && segments[2] == 0x8000)
}

fn remote_cancelled() -> anyhow::Error {
    StudioError::new(StudioErrorCode::Cancelled, "附件下载已取消。", true).into()
}
