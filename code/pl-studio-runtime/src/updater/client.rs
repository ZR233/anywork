use super::error::{StudioUpdateError, StudioUpdateErrorCode};
use super::install::{self, PreparedStudioUpdate, StudioUpdateCancellation};
use super::manifest::{LATEST_MANIFEST_URL, evaluate_manifest, validate_redirect_url};
use super::types::{StudioUpdate, StudioUpdateCheck, StudioUpdateEvent};
use futures::StreamExt;
use reqwest::{Client, Response, StatusCode};
use std::env;
use std::error::Error;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc::Sender;
use url::Url;

const MAX_REDIRECTS: usize = 5;
const MAX_MANIFEST_BYTES: u64 = 1024 * 1024;
pub(crate) const STUDIO_VERSION: &str = include_str!("../../../../studio-version.txt");

/// GitHub Release 稳定更新客户端。
#[derive(Clone)]
pub struct StudioUpdater {
    pub(super) client: Client,
    pub(super) downloader: downlowd::Client,
    pub(super) cache_dir: PathBuf,
    pub(super) public_key: &'static str,
    pub(super) install_active: Arc<std::sync::atomic::AtomicBool>,
}

impl StudioUpdater {
    /// 创建使用生产清单、公钥和应用缓存目录的更新客户端。
    pub fn new_default() -> Result<Self, StudioUpdateError> {
        let client = http_client()
            .connect_timeout(Duration::from_secs(15))
            .read_timeout(Duration::from_secs(30))
            .timeout(Duration::from_secs(15 * 60))
            .build()
            .map_err(network_error)?;
        let download_client = http_client()
            .connect_timeout(Duration::from_secs(5))
            .read_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(15 * 60))
            .build()
            .map_err(network_error)?;
        let downloader = downlowd::Client::builder()
            .reqwest_client(download_client)
            .max_retries(Some(3))
            .build()
            .map_err(super::transfer::download_error)?;
        let cache_root = env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(env::temp_dir)
            .join("anywork")
            .join("updates");
        Ok(Self {
            client,
            downloader,
            cache_dir: cache_root,
            public_key: include_str!("anywork.pub"),
            install_active: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        })
    }

    /// 检查稳定更新；同版或降级统一返回 [`StudioUpdateCheck::UpToDate`]。
    pub async fn check(
        &self,
        current_version: &str,
    ) -> Result<StudioUpdateCheck, StudioUpdateError> {
        let url = Url::parse(LATEST_MANIFEST_URL).map_err(|error| {
            StudioUpdateError::new(
                StudioUpdateErrorCode::InvalidManifest,
                format!("invalid built-in update URL: {error}"),
            )
        })?;
        let bytes = tokio::time::timeout(
            Duration::from_secs(60),
            self.request_bytes(url, MAX_MANIFEST_BYTES),
        )
        .await
        .map_err(|_| {
            StudioUpdateError::new(
                StudioUpdateErrorCode::Network,
                "update check exceeded its 60 second deadline",
            )
        })??;
        evaluate_manifest(&bytes, current_version)
    }

    /// 下载并验证更新，仅返回文件租约，不关闭应用或启动安装器。
    pub async fn download(
        &self,
        update: StudioUpdate,
        progress: Sender<StudioUpdateEvent>,
        cancellation: StudioUpdateCancellation,
    ) -> Result<PreparedStudioUpdate, StudioUpdateError> {
        install::download(self, update, progress, cancellation).await
    }

    async fn request(&self, url: Url) -> Result<Response, StudioUpdateError> {
        validate_redirect_url(&url)?;
        let response = self.client.get(url).send().await.map_err(network_error)?;
        if response.status() != StatusCode::OK {
            return Err(StudioUpdateError::new(
                StudioUpdateErrorCode::Network,
                format!("update request failed with HTTP {}", response.status()),
            ));
        }
        Ok(response)
    }

    pub(super) async fn request_bytes(
        &self,
        url: Url,
        max_bytes: u64,
    ) -> Result<Vec<u8>, StudioUpdateError> {
        let response = self.request(url).await?;
        if response
            .content_length()
            .is_some_and(|size| size > max_bytes)
        {
            return Err(StudioUpdateError::new(
                StudioUpdateErrorCode::DownloadTooLarge,
                "update response exceeds the allowed size",
            ));
        }
        let mut stream = response.bytes_stream();
        let mut bytes = Vec::new();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(network_error)?;
            let next_len = bytes.len().checked_add(chunk.len()).ok_or_else(|| {
                StudioUpdateError::new(
                    StudioUpdateErrorCode::DownloadTooLarge,
                    "update response size overflow",
                )
            })?;
            if u64::try_from(next_len).unwrap_or(u64::MAX) > max_bytes {
                return Err(StudioUpdateError::new(
                    StudioUpdateErrorCode::DownloadTooLarge,
                    "update response exceeds the allowed size",
                ));
            }
            bytes.extend_from_slice(&chunk);
        }
        Ok(bytes)
    }
}

fn http_client() -> reqwest::ClientBuilder {
    Client::builder()
        .user_agent(format!("anywork/{}", STUDIO_VERSION.trim()))
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() > MAX_REDIRECTS {
                return attempt.error("update download exceeded five redirects");
            }
            match validate_redirect_url(attempt.url()) {
                Ok(()) => attempt.follow(),
                Err(error) => attempt.error(error),
            }
        }))
}

pub(super) fn network_error(error: reqwest::Error) -> StudioUpdateError {
    // Redirect URLs contain temporary CDN credentials; retain causes without URLs.
    let error = error.without_url();
    let mut message = format!("update network request failed: {error}");
    let mut cause = error.source();
    while let Some(source) = cause {
        message.push_str(&format!(": {source}"));
        cause = source.source();
    }
    StudioUpdateError::new(StudioUpdateErrorCode::Network, message)
}
