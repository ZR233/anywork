//! Per-HTTP-instance, exact-destination gates for real blocking file operations.
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::Duration;

use anyhow::{Context, Result, ensure};
use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;
use url::Url;

use crate::bots::commands::archive_tests::Fixture;
use crate::bots::inbound::InboundAttachment;
use pl_tool::workspace::{SessionFiles, SessionTempBackend};

const RESOURCE_BODY: &str = "local image bytes from the real resource response";

#[derive(Clone)]
pub(super) struct ResourceControl {
    pub(super) base_url: Url,
    pub(super) gate: Arc<FileGate>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum FileStage {
    Setup,
    Persist,
}

pub(super) struct FileGate {
    pub(super) destination: PathBuf,
    stage: FileStage,
    started: Notify,
    released: Mutex<bool>,
    release: Condvar,
    completed: AtomicBool,
    pub(super) cancellation: OnceLock<CancellationToken>,
}

impl FileGate {
    fn new(destination: PathBuf, stage: FileStage) -> Arc<Self> {
        Arc::new(Self {
            destination,
            stage,
            started: Notify::new(),
            released: Mutex::new(false),
            release: Condvar::new(),
            completed: AtomicBool::new(false),
            cancellation: OnceLock::new(),
        })
    }

    pub(super) fn enter(
        self: &Arc<Self>,
        stage: FileStage,
        destination: &Path,
    ) -> Option<OperationFinished> {
        if self.stage != stage || self.destination != destination {
            return None;
        }
        // Runs inside the actual spawn_blocking closure owning the file/temp.
        self.started.notify_one();
        let mut released = self.released.lock().unwrap();
        while !*released {
            released = self.release.wait(released).unwrap();
        }
        Some(OperationFinished(self.clone()))
    }

    fn open(&self) {
        *self.released.lock().unwrap() = true;
        self.release.notify_all();
    }
}

pub(super) struct OperationFinished(Arc<FileGate>);

impl Drop for OperationFinished {
    fn drop(&mut self) {
        self.0.completed.store(true, Ordering::SeqCst);
    }
}

struct ReleaseOnDrop(Arc<FileGate>);

impl Drop for ReleaseOnDrop {
    fn drop(&mut self) {
        // An assertion failure must not strand a real blocking worker.
        self.0.open();
    }
}

struct LocalMediaServer {
    base_url: Url,
    stop: CancellationToken,
    task: tokio::task::JoinHandle<Result<()>>,
}

impl LocalMediaServer {
    async fn start() -> Result<Self> {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let base_url = Url::parse(&format!("http://{}/", listener.local_addr()?))?;
        let stop = CancellationToken::new();
        let cancellation = stop.clone();
        let task = tokio::spawn(async move {
            loop {
                let (mut stream, _) = tokio::select! {
                    _ = cancellation.cancelled() => return Ok(()),
                    accepted = listener.accept() => accepted?,
                };
                let mut request = Vec::new();
                let header_end = loop {
                    let mut buffer = [0; 1024];
                    let read = stream.read(&mut buffer).await?;
                    ensure!(read > 0, "fixture request ended before headers");
                    request.extend_from_slice(&buffer[..read]);
                    ensure!(request.len() <= 8192, "fixture request exceeded its bound");
                    if let Some(end) = request.windows(4).position(|bytes| bytes == b"\r\n\r\n") {
                        break end + 4;
                    }
                };
                let headers = std::str::from_utf8(&request[..header_end])?;
                let body_length = headers
                    .lines()
                    .find_map(|line| {
                        let (name, value) = line.split_once(':')?;
                        name.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>())
                    })
                    .transpose()?
                    .unwrap_or(0);
                let token_request = headers.starts_with("POST ");
                while request.len() < header_end + body_length {
                    let mut buffer = [0; 1024];
                    let read = stream.read(&mut buffer).await?;
                    ensure!(read > 0, "fixture request body ended early");
                    request.extend_from_slice(&buffer[..read]);
                    ensure!(request.len() <= 8192, "fixture request exceeded its bound");
                }
                let body = if token_request {
                    r#"{"code":0,"access_token":"local-fixture-token","expires_in":3600,"token_type":"Bearer"}"#
                } else {
                    RESOURCE_BODY
                };
                stream.write_all(format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len(),
                ).as_bytes()).await?;
                stream.shutdown().await?;
            }
        });
        Ok(Self {
            base_url,
            stop,
            task,
        })
    }

    async fn close(self) -> Result<()> {
        self.stop.cancel();
        self.task.await?
    }
}

async fn registered_media_window(stage: FileStage, lose_claim: bool) -> Result<()> {
    let fixture = Fixture::new().await?;
    let server = LocalMediaServer::start().await?;
    let inbound = fixture
        .inbound_with_attachments(
            "file-window",
            true,
            vec![InboundAttachment::Image {
                key: "local-image-key".into(),
            }],
        )
        .await?;
    let files = SessionFiles::new(&inbound.creation_id);
    let workspace = fixture
        .bots
        .inner
        .paths
        .bot_dir(&inbound.bot_id)
        .join("workspace");
    let destination = workspace
        .join(files.uploads())
        .join(hex::encode(Sha256::digest(inbound.message_id.as_bytes())))
        .join(hex::encode(Sha256::digest(b"local-image-key")))
        .join("image.png");
    let gate = FileGate::new(destination.clone(), stage);
    let release = ReleaseOnDrop(gate.clone());
    *fixture.bots.inner.http.resource_control.lock().unwrap() = Some(ResourceControl {
        base_url: server.base_url.clone(),
        gate: gate.clone(),
    });
    let managed = fixture.bots.managed(&inbound.bot_id).await?;
    // Synthetic local credential material only: no credential store or real
    // Feishu endpoints. TokenLease's HTTP clone shares this instance's control.
    managed
        .token
        .replace(inbound.app_id.clone(), "local-fixture-marker".into())
        .await;
    fixture.enqueue(inbound.clone()).await?;
    tokio::time::timeout(Duration::from_secs(10), gate.started.notified())
        .await
        .context("registered dispatch did not reach the actual file operation")?;
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 31);
    assert!(
        destination.parent().unwrap().is_dir(),
        "the filesystem task has already created its real destination directory"
    );
    if stage == FileStage::Persist {
        assert!(destination.parent().unwrap().read_dir()?.next().is_some());
    }
    if lose_claim {
        let probe = fixture.ledger_probe().await?;
        assert_eq!(
            probe
                .execute_raw(Statement::from_string(
                    DatabaseBackend::Sqlite,
                    "UPDATE inbound_work SET claimed_by='successor' WHERE status='claimed'",
                ))
                .await?
                .rows_affected(),
            1
        );
        // Observe the real heartbeat's child cancellation, not a direct call to
        // the task container or a replacement heartbeat implementation.
        tokio::time::timeout(
            Duration::from_secs(20),
            gate.cancellation.get().unwrap().cancelled(),
        )
        .await
        .context("heartbeat did not observe the lost claim")?;
    }
    let targets = [inbound.creation_id.clone()];
    let quiesce = fixture.bots.quiesce_archive_threads(&targets);
    tokio::pin!(quiesce);
    assert!(
        tokio::time::timeout(Duration::from_millis(50), &mut quiesce)
            .await
            .is_err(),
        "quiesce must join the running file operation before reporting stop"
    );
    assert!(gate.cancellation.get().unwrap().is_cancelled());
    assert!(!gate.completed.load(Ordering::SeqCst));
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 31);
    gate.open();
    let guard = tokio::time::timeout(Duration::from_secs(5), quiesce).await??;
    assert!(gate.completed.load(Ordering::SeqCst));
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
    if lose_claim {
        let probe = fixture.ledger_probe().await?;
        let row = probe
            .query_one_raw(Statement::from_string(
                DatabaseBackend::Sqlite,
                "SELECT claimed_by, status FROM inbound_work",
            ))
            .await?
            .context("original ledger row")?;
        assert_eq!(row.try_get::<String>("", "claimed_by")?, "successor");
        assert_eq!(row.try_get::<String>("", "status")?, "claimed");
    } else {
        assert_eq!(
            managed.store.list_due_inbound(&inbound.bot_id).await?,
            vec![inbound]
        );
    }
    // This is the same dedicated-temp cleanup primitive the archive consumes,
    // on the real media producer's frozen physical root, after its true join.
    SessionTempBackend::Local(&workspace).remove(&files).await?;
    assert!(!workspace.join(files.temp()).exists());
    assert!(!destination.exists());
    assert!(
        gate.completed.load(Ordering::SeqCst),
        "no file worker survives cleanup"
    );
    drop(guard);
    drop(release);
    fixture.shutdown().await?;
    server.close().await
}

#[tokio::test]
async fn archive_media_cancel_drains_started_directory_and_tempfile_setup() -> Result<()> {
    registered_media_window(FileStage::Setup, false).await
}

#[tokio::test]
async fn archive_media_cancel_drains_started_persist_before_temp_cleanup() -> Result<()> {
    registered_media_window(FileStage::Persist, false).await
}

#[tokio::test]
async fn archive_media_lost_claim_drains_started_persist_without_finishing_successor() -> Result<()>
{
    registered_media_window(FileStage::Persist, true).await
}

#[tokio::test]
async fn archive_queued_submit_lost_claim_drains_retention_before_releasing_draft() -> Result<()> {
    use crate::bots::BotInputRead;
    use crate::resource_store::{FileResourceStore, RESOURCE_ID_PREFIX, retention_test};
    use pl_core::context::{ResourceReader, ResourceReference};

    let fixture = Fixture::new_with_file_input().await?;
    let server = LocalMediaServer::start().await?;
    let inbound = fixture
        .inbound_with_attachments(
            "retain-window",
            true,
            vec![InboundAttachment::File {
                key: "local-resource-key".into(),
                filename: "resource.txt".into(),
            }],
        )
        .await?;
    let files = SessionFiles::new(&inbound.creation_id);
    let workspace = fixture
        .bots
        .inner
        .paths
        .bot_dir(&inbound.bot_id)
        .join("workspace");
    let destination = workspace
        .join(files.uploads())
        .join(hex::encode(Sha256::digest(inbound.message_id.as_bytes())))
        .join(hex::encode(Sha256::digest(b"local-resource-key")))
        .join("file-resource.txt");
    // Keep download unblocked; the separate root-keyed gate below is inside the
    // real queued-submit retention worker, after resource temp creation.
    let download = FileGate::new(destination.clone(), FileStage::Persist);
    download.open();
    *fixture.bots.inner.http.resource_control.lock().unwrap() = Some(ResourceControl {
        base_url: server.base_url.clone(),
        gate: download.clone(),
    });
    let managed = fixture.bots.managed(&inbound.bot_id).await?;
    managed
        .token
        .replace(inbound.app_id.clone(), "local-fixture-marker".into())
        .await;
    let root = fixture
        .host
        .resources_dir(&inbound.workspace_id, &inbound.creation_id)?;
    let retention = retention_test::pause(root.clone());
    fixture.enqueue(inbound.clone()).await?;
    tokio::time::timeout(Duration::from_secs(10), retention.wait_started())
        .await
        .context("queued submit did not start real resource retention")?;
    assert!(download.completed.load(Ordering::SeqCst));
    assert_eq!(
        tokio::fs::read(&destination).await?,
        RESOURCE_BODY.as_bytes()
    );
    assert!(
        root.read_dir()?.next().is_some(),
        "retention created its real temp file"
    );

    let drafts = std::fs::read_dir(fixture.host.drafts_dir())?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    assert_eq!(drafts.len(), 1);
    let draft = &drafts[0];
    assert_eq!(tokio::fs::read(draft).await?, RESOURCE_BODY.as_bytes());
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 31);
    let probe = fixture.ledger_probe().await?;
    assert_eq!(
        probe
            .execute_raw(Statement::from_string(
                DatabaseBackend::Sqlite,
                "UPDATE inbound_work SET claimed_by='successor' WHERE status='claimed'",
            ))
            .await?
            .rows_affected(),
        1
    );
    tokio::time::timeout(
        Duration::from_secs(20),
        download.cancellation.get().unwrap().cancelled(),
    )
    .await
    .context("real heartbeat did not observe successor ownership")?;

    let targets = [inbound.creation_id.clone()];
    let quiesce = fixture.bots.quiesce_archive_threads(&targets);
    tokio::pin!(quiesce);
    assert!(
        tokio::time::timeout(Duration::from_millis(50), &mut quiesce)
            .await
            .is_err(),
        "queued submit must drain its already-started resource copy"
    );
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 31);
    assert_eq!(
        tokio::fs::read(draft).await?,
        RESOURCE_BODY.as_bytes(),
        "cancellation must not release the source draft before retention ACK"
    );
    retention.release();
    let guard = tokio::time::timeout(Duration::from_secs(5), quiesce).await??;
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
    assert!(
        !draft.exists(),
        "draft release follows actual queued-submit completion"
    );
    let row = probe
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT claimed_by, status FROM inbound_work",
        ))
        .await?
        .context("original frozen inbound ledger row")?;
    assert_eq!(row.try_get::<String>("", "claimed_by")?, "successor");
    assert_eq!(row.try_get::<String>("", "status")?, "claimed");
    let input_id = format!(
        "bot:{}:{}:{}",
        inbound.bot_id, inbound.chat_id, inbound.message_id
    );
    assert_eq!(
        fixture
            .host
            .runtime
            .bot_input_fact(&inbound.creation_id, &input_id)
            .await?,
        BotInputRead::Absent,
        "the safe pre-core cancellation boundary did not submit a new input",
    );
    let hash = hex::encode(Sha256::digest(RESOURCE_BODY.as_bytes()));
    let reference = ResourceReference::new(
        format!("{RESOURCE_ID_PREFIX}{hash}"),
        format!("sha256:{hash}"),
        RESOURCE_BODY.len() as u64,
        "text/plain".into(),
    )?;
    let resources = FileResourceStore::new(root);
    assert_eq!(
        resources
            .read(reference.clone(), CancellationToken::new())
            .await?
            .as_ref(),
        RESOURCE_BODY.as_bytes(),
        "an actual retained resource is not rolled back as if copying never happened",
    );
    SessionTempBackend::Local(&workspace).remove(&files).await?;
    assert!(!workspace.join(files.temp()).exists());
    assert!(!destination.exists());
    assert!(!draft.exists());
    assert_eq!(
        resources
            .read(reference, CancellationToken::new())
            .await?
            .as_ref(),
        RESOURCE_BODY.as_bytes(),
        "reliable resource and finished draft cleanup survive temp removal",
    );
    drop(guard);
    drop(retention);
    fixture.shutdown().await?;
    server.close().await
}
