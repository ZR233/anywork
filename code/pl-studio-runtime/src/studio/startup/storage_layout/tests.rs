use super::*;
use sea_orm::sqlx::{Connection, Executor};
use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};

const OWNER: &str = "original-workspace";
const THREAD: &str = "original-thread";
const BODY: &[u8] = b"attachment and tool share exact bytes";

async fn fixture(home: &Path, grouped: bool, standalone: bool) -> Result<(StudioPaths, PathBuf)> {
    let paths = StudioPaths::from_home(home.to_owned());
    let legacy = home.join("v2");
    tokio::fs::create_dir_all(&legacy).await?;
    let settings =
        crate::studio::store::settings::SettingsStore::load(legacy.join("settings.toml")).await?;
    settings.persist_if_absent().await?;
    let kind = if standalone { "standalone" } else { "project" };
    tokio::fs::write(legacy.join("workspaces.toml"), format!("schemaVersion = 2\nrevision = 7\n[[workspaces]]\nid = '{OWNER}'\nkind = '{kind}'\nname = 'Owner'\npath = '/isolated-workspace'\ncreatedAt = 1\nupdatedAt = 2\nclosed = false\n")).await?;
    tokio::fs::write(legacy.join("catalog.toml"), format!("schemaVersion = 4\nrevision = 9\n[[entries]]\nid = '{THREAD}'\nprojectId = '{OWNER}'\ntitle = 'kept title'\nmode = 'mode.simple'\nworkspaceMode = 'local'\nworkspacePath = '/isolated-workspace'\nrootThreadId = '{THREAD}'\nrole = 'root'\nagentPath = '{THREAD}'\nstatus = 'idle'\ndelegationMode = 'profile'\ndelegationPreference = 'balanced'\nexplicitlyClosed = false\ncreatedAt = 1\nupdatedAt = 2\narchived = false\n")).await?;
    let key = storage_key(THREAD, "Thread")?;
    let session = if grouped {
        let root = legacy
            .join("projects")
            .join(storage_key(OWNER, "Workspace")?);
        tokio::fs::create_dir_all(&root).await?;
        tokio::fs::write(
            root.join("project.toml"),
            format!("schemaVersion = 1\nprojectId = '{OWNER}'\npath = '/isolated-workspace'\n"),
        )
        .await?;
        root.join("sessions").join(key)
    } else {
        legacy.join("sessions").join(key)
    };
    tokio::fs::create_dir_all(session.join("blobs/checkpoint")).await?;
    tokio::fs::create_dir_all(session.join("thread-resources")).await?;
    tokio::fs::create_dir_all(session.join("scratch/commands")).await?;
    tokio::fs::write(session.join("scratch/commands/capture"), b"temporary").await?;
    tokio::fs::write(
        session.join("blobs/checkpoint/saved"),
        b"opaque checkpoint body",
    )
    .await?;
    tokio::fs::write(session.join("session.toml"), format!("schemaVersion = 1\nthreadId = '{THREAD}'\nprojectId = '{OWNER}'\nrootThreadId = '{THREAD}'\nworkspaceMode = 'local'\nworkspacePath = '/isolated-workspace'\ncreatedAt = 1\n")).await?;
    let hash = hex::encode(Sha256::digest(BODY));
    let blob = session.join("blobs").join(&hash);
    tokio::fs::write(&blob, BODY).await?;
    tokio::fs::write(session.join("thread-resources").join(&hash), BODY).await?;
    let mut record = toml::Table::new();
    record.insert("id".into(), "kept-attachment-id".into());
    record.insert("threadId".into(), THREAD.into());
    record.insert("modality".into(), "file".into());
    record.insert("mediaType".into(), "text/plain".into());
    record.insert("filename".into(), "original.txt".into());
    record.insert(
        "storagePath".into(),
        blob.to_str().context("fixture path UTF8")?.into(),
    );
    record.insert("byteSize".into(), (BODY.len() as i64).into());
    record.insert("contentSha256".into(), hash.into());
    record.insert("createdAt".into(), 3.into());
    let catalog = toml::Table::from_iter([
        ("schemaVersion".into(), 1.into()),
        ("threadId".into(), THREAD.into()),
        ("records".into(), toml::Value::Array(vec![record.into()])),
    ]);
    tokio::fs::write(session.join("attachments.toml"), toml::to_string(&catalog)?).await?;
    tokio::fs::create_dir_all(legacy.join("bots/bot-test-one/workspace/.anywork/sessions")).await?;
    tokio::fs::write(
        legacy.join("bots/bot-test-one/config.toml"),
        format!("schema_version=2\nid='bot-test-one'\nname='Preserved bot'\nproject_id='{OWNER}'\napp_id='cli_original'\nplatform='feishuChina'\nenabled=false\ntools_enabled=false\ntrusted_open_ids=[]\ntrusted_chat_ids=[]\nconfig_revision=9\ncreated_at=1\nupdated_at=2\n"),
    )
    .await?;
    tokio::fs::write(
        legacy.join("bots/bot-test-one/workspace/owned"),
        b"bot workspace bytes",
    )
    .await?;
    let calls =
        crate::studio::storage::calls::CallsStore::open(&legacy.join("calls/calls.sqlite")).await?;
    calls.close().await?;
    // A canonical v2 installation owns both necessary database families.
    wal_family(&legacy.join("studio.sqlite"), true).await?;
    tokio::fs::write(
        legacy.join("calls/logs/preserved.txt"),
        b"original raw log bytes\0",
    )
    .await?;
    tokio::fs::create_dir_all(home.join("skills/private-user")).await?;
    tokio::fs::write(
        home.join("skills/private-user/SKILL.md"),
        b"private skill source",
    )
    .await?;
    tokio::fs::write(home.join("studio.sqlite"), b"pre-v2 product untouched").await?;
    tokio::fs::create_dir_all(home.join("v1")).await?;
    tokio::fs::write(home.join("v1/unknown"), b"pre-v2 unknown untouched").await?;
    Ok((paths, session))
}

/// Snapshot a committed WAL family from a separate live donor. No connection ever opens the
/// fixture family while the migration moves it.
async fn wal_family(target: &Path, product: bool) -> Result<BTreeMap<String, Vec<u8>>> {
    let donor = tempfile::tempdir()?;
    let live = donor.path().join("donor.sqlite");
    let mut connection = sea_orm::sqlx::SqliteConnection::connect_with(
        &sea_orm::sqlx::sqlite::SqliteConnectOptions::new()
            .filename(&live)
            .create_if_missing(true),
    )
    .await?;
    connection
        .execute("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
        .await?;
    if product {
        connection
            .execute(include_str!("../../store/product_schema.sql"))
            .await?;
        connection
            .execute(include_str!("../../store/agent_evaluations.sql"))
            .await?;
        connection.execute("PRAGMA user_version=26;").await?;
    } else {
        connection.execute("CREATE TABLE retained (id TEXT PRIMARY KEY, body BLOB); INSERT INTO retained VALUES ('identity', x'006f7061717565');").await?;
    }
    if target
        .file_name()
        .is_some_and(|name| name == "state.sqlite")
    {
        connection.execute("CREATE TABLE bot_meta(id INTEGER PRIMARY KEY, schema_version INTEGER); INSERT INTO bot_meta VALUES(1,6); CREATE TABLE thread_bindings(thread_id TEXT, project_id TEXT, status TEXT);").await?;
    }
    let mut family = BTreeMap::new();
    tokio::fs::create_dir_all(target.parent().context("family parent")?).await?;
    for suffix in ["", "-wal", "-shm"] {
        let bytes = tokio::fs::read(format!("{}{suffix}", live.display())).await?;
        tokio::fs::write(format!("{}{suffix}", target.display()), &bytes).await?;
        family.insert(suffix.to_owned(), bytes);
    }
    connection.close().await?;
    Ok(family)
}

#[tokio::test]
async fn grouped_and_flat_v2_preserve_sqlite_families_and_share_resources() -> Result<()> {
    for (grouped, standalone) in [(true, false), (false, true)] {
        let temp = tempfile::tempdir()?;
        let (paths, old_session) = fixture(temp.path(), grouped, standalone).await?;
        let family = wal_family(&old_session.join("history.sqlite"), false).await?;
        // Exercise split roots without duplicating the fixture's authoritative product family.
        for suffix in ["", "-wal", "-shm"] {
            tokio::fs::remove_file(temp.path().join(format!("v2/studio.sqlite{suffix}"))).await?;
        }
        let product = wal_family(&temp.path().join("studio/v2/studio.sqlite"), true).await?;
        let bot = wal_family(
            &temp.path().join("v2/bots/bot-test-one/state.sqlite"),
            false,
        )
        .await?;
        prepare(&paths).await?;
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert_eq!(journal.phase, Phase::Completed);
        let backup = backup_root(&paths, &journal);
        let saved_session = backup.join(old_session.strip_prefix(temp.path())?);
        for (suffix, expected) in &family {
            assert_eq!(
                tokio::fs::read(format!(
                    "{}{suffix}",
                    saved_session.join("history.sqlite").display()
                ))
                .await?,
                *expected
            );
        }
        for (suffix, expected) in &product {
            assert_eq!(
                tokio::fs::read(backup.join(format!("studio/v2/studio.sqlite{suffix}"))).await?,
                *expected
            );
        }
        for (suffix, expected) in &bot {
            assert!(
                tokio::fs::read(backup.join(format!("v2/bots/bot-test-one/state.sqlite{suffix}")))
                    .await?
                    == *expected,
                "original bot family {suffix} was not preserved"
            );
            if suffix == "-shm" {
                continue;
            } // SQLite owns mutable reader-coordination bytes.
            assert_eq!(
                tokio::fs::read(
                    paths
                        .bot_dir("bot-test-one")
                        .join(format!("state.sqlite{suffix}"))
                )
                .await?,
                *expected
            );
        }
        let session = paths.session_paths(OWNER, THREAD)?;
        assert_eq!(std::fs::read_dir(session.resources_dir())?.count(), 1);
        let hash = hex::encode(Sha256::digest(BODY));
        assert_eq!(
            tokio::fs::read(session.resources_dir().join(&hash)).await?,
            BODY
        );
        assert!(!session.root().join("blobs").join(&hash).exists());
        assert_eq!(
            tokio::fs::read(session.root().join("blobs/checkpoint/saved")).await?,
            b"opaque checkpoint body"
        );
        assert_eq!(
            tokio::fs::read(session.temp_dir().join("commands/capture")).await?,
            b"temporary"
        );
        assert_eq!(
            tokio::fs::read(paths.calls_dir().join("logs/preserved.txt")).await?,
            b"original raw log bytes\0"
        );
        assert!(backup.join("skills/private-user/SKILL.md").exists());
        assert!(!temp.path().join("skills").exists());
        let manifest: WorkspaceManifest =
            toml::from_str(&tokio::fs::read_to_string(paths.workspace_manifest(OWNER)?).await?)?;
        assert_eq!(
            manifest.kind == pl_protocol::studio::WorkspaceKind::Standalone,
            standalone
        );
        let store = StudioStore::prepare_database(&paths.database()).await?;
        let attachments = store.list_thread_attachments(THREAD).await?;
        assert_eq!(attachments[0].id, "kept-attachment-id");
        assert_eq!(
            attachments[0].blob_relative_path,
            format!("resources/{hash}")
        );
        assert_eq!(
            store
                .read_attachment_bytes(THREAD, "kept-attachment-id")
                .await?,
            BODY
        );
        assert_eq!(
            store
                .catalog()
                .get(THREAD)
                .context("retained catalog")?
                .last_user_message_at,
            None
        );
        for name in ["projects", "threads", "app_settings"] {
            assert!(
                store
                    .database()
                    .query_one_raw(Statement::from_sql_and_values(
                        DatabaseBackend::Sqlite,
                        "SELECT name FROM sqlite_schema WHERE name=?",
                        [name.into()]
                    ))
                    .await?
                    .is_none()
            );
        }
        store.close().await?;
        // Successful startup does not rescan a later invalid source or reset isolated old versions.
        tokio::fs::create_dir_all(temp.path().join("v2")).await?;
        tokio::fs::write(temp.path().join("v2/unowned"), b"not claimed").await?;
        prepare(&paths).await?;
        assert_eq!(
            tokio::fs::read(temp.path().join("studio.sqlite")).await?,
            b"pre-v2 product untouched"
        );
        assert_eq!(
            tokio::fs::read(temp.path().join("v1/unknown")).await?,
            b"pre-v2 unknown untouched"
        );
    }
    Ok(())
}

#[tokio::test]
async fn interrupted_move_copy_and_publication_resume_without_reclaiming_targets() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, _) = fixture(temp.path(), false, false).await?;
    let mut journal = Journal {
        schema_version: 1,
        operation_id: "layout-interrupted-operation".into(),
        phase: Phase::Preserving,
        roots: ROOTS
            .into_iter()
            .map(|source| RootMove {
                source: source.into(),
                present: temp.path().join(source).exists(),
                moved: false,
            })
            .collect(),
        copied: BTreeSet::new(),
        bot_roots: Vec::new(),
    };
    persist(&temp.path().join(JOURNAL), &journal).await?;
    managed_move(
        &temp.path().join("v2"),
        &backup_root(&paths, &journal).join("v2"),
    )
    .await?;
    // rename succeeded, journal update did not.
    prepare(&paths).await?;
    journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
    assert_eq!(journal.phase, Phase::Completed);
    journal.phase = Phase::Publishing;
    persist(&temp.path().join(JOURNAL), &journal).await?;
    // publishing directory move succeeded, journal update did not.
    prepare(&paths).await?;
    assert_eq!(
        decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?.phase,
        Phase::Completed
    );
    Ok(())
}

#[tokio::test]
async fn legacy_mid_move_journal_accepts_only_proven_grouped_destination() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, flat) = fixture(temp.path(), false, false).await?;
    let owner_key = storage_key(OWNER, "Workspace")?;
    let thread_key = storage_key(THREAD, "Thread")?;
    let grouped = temp
        .path()
        .join("v2/projects")
        .join(&owner_key)
        .join("sessions")
        .join(&thread_key);
    tokio::fs::create_dir_all(grouped.parent().context("parent")?).await?;
    tokio::fs::write(
        grouped
            .parent()
            .context("sessions")?
            .parent()
            .context("owner")?
            .join("project.toml"),
        format!("schemaVersion=1\nprojectId='{OWNER}'\npath='/isolated-workspace'\n"),
    )
    .await?;
    tokio::fs::rename(&flat, &grouped).await?;
    tokio::fs::create_dir_all(temp.path().join("v2/migrations")).await?;
    tokio::fs::write(temp.path().join("v2/migrations/session-project-layout.toml"), format!("schemaVersion=1\ncompleted=false\norphans=[]\n[[moves]]\nthreadId='{THREAD}'\nprojectId='{OWNER}'\nsourceKey='{thread_key}'\ntargetProjectKey='{owner_key}'\ntargetThreadKey='{thread_key}'\nphase='planned'\n")).await?;
    prepare(&paths).await?;
    assert!(
        paths
            .session_paths(OWNER, THREAD)?
            .attachments_catalog()
            .exists()
    );
    Ok(())
}

#[tokio::test]
async fn invalid_inputs_keep_originals_and_never_publish_default_layout() -> Result<()> {
    for fault in [
        "future-catalog",
        "missing-catalog",
        "missing-attachment",
        "resource-digest",
        "bad-journal",
        "conflicting-target",
        "orphan-wal",
    ] {
        let temp = tempfile::tempdir()?;
        let (paths, session) = fixture(temp.path(), false, false).await?;
        let hash = hex::encode(Sha256::digest(BODY));
        match fault {
            "future-catalog" => {
                let path = temp.path().join("v2/catalog.toml");
                let content = tokio::fs::read_to_string(&path)
                    .await?
                    .replace("schemaVersion = 4", "schemaVersion = 99");
                tokio::fs::write(path, content).await?;
            }
            "missing-catalog" => {
                tokio::fs::remove_file(temp.path().join("v2/catalog.toml")).await?
            }
            "missing-attachment" => {
                tokio::fs::remove_file(session.join("blobs").join(&hash)).await?
            }
            "resource-digest" => {
                tokio::fs::write(session.join("thread-resources").join(&hash), b"corrupt").await?
            }
            "bad-journal" => tokio::fs::write(temp.path().join(JOURNAL), b"bad = [").await?,
            "conflicting-target" => {
                tokio::fs::create_dir_all(paths.data_dir()).await?;
                tokio::fs::write(paths.data_dir().join("unknown"), b"untouched").await?;
            }
            "orphan-wal" => tokio::fs::write(session.join("history.sqlite-wal"), b"orphan").await?,
            _ => unreachable!(),
        }
        for _ in 0..2 {
            let error = prepare(&paths).await.expect_err(fault);
            assert!(
                error
                    .chain()
                    .any(|cause| cause.is::<SessionLayoutMigrationFailed>())
            );
            assert!(!paths.layout_file().exists(), "{fault}");
        }
        // Source bytes either remain in place or in the operation-bound backup, never reset.
        assert_eq!(
            tokio::fs::read(temp.path().join("studio.sqlite")).await?,
            b"pre-v2 product untouched"
        );
        if fault == "conflicting-target" {
            assert_eq!(
                tokio::fs::read(paths.data_dir().join("unknown")).await?,
                b"untouched"
            );
        } else if fault != "bad-journal" {
            let journal =
                decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
            assert!(
                backup_root(&paths, &journal)
                    .join("v2/workspaces.toml")
                    .exists()
            );
        }
    }
    Ok(())
}

#[tokio::test]
async fn registered_v2_sessions_without_sources_fail_on_every_restart() -> Result<()> {
    for grouped in [false, true] {
        let temp = tempfile::tempdir()?;
        let (paths, source) = fixture(temp.path(), grouped, !grouped).await?;
        let catalog = tokio::fs::read(temp.path().join("v2/catalog.toml")).await?;
        tokio::fs::remove_dir_all(source).await?;
        for _ in 0..2 {
            let error = prepare(&paths)
                .await
                .expect_err("missing registered session");
            assert!(format!("{error:#}").contains("registered v2 session source missing"));
            assert!(!paths.data_dir().exists());
            let journal =
                decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
            assert_eq!(journal.phase, Phase::Building);
            assert_eq!(
                tokio::fs::read(backup_root(&paths, &journal).join("v2/catalog.toml")).await?,
                catalog
            );
            let stage = staging(&paths, &journal);
            assert!(!stage.layout_file().exists());
            assert!(
                !stage
                    .session_paths(OWNER, THREAD)?
                    .root()
                    .join("session.toml")
                    .exists()
            );
        }
    }
    Ok(())
}

#[tokio::test]
async fn canonical_v2_missing_database_families_never_create_replacements() -> Result<()> {
    for name in ["studio.sqlite", "calls/calls.sqlite"] {
        let temp = tempfile::tempdir()?;
        let (paths, _) = fixture(temp.path(), true, false).await?;
        let catalog = tokio::fs::read(temp.path().join("v2/catalog.toml")).await?;
        for suffix in ["", "-wal", "-shm"] {
            let member = temp.path().join(format!("v2/{name}{suffix}"));
            if member.exists() {
                tokio::fs::remove_file(member).await?;
            }
        }
        for _ in 0..2 {
            let error = prepare(&paths).await.expect_err(name);
            assert!(
                format!("{error:#}").contains(&format!("v2 authoritative {name} missing")),
                "{error:#}"
            );
            assert!(!paths.data_dir().exists());
            let journal =
                decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
            let stage = staging(&paths, &journal);
            assert!(!stage.data_dir().join(name).exists());
            assert!(!stage.layout_file().exists());
            let backup = backup_root(&paths, &journal);
            assert_eq!(
                tokio::fs::read(backup.join("v2/catalog.toml")).await?,
                catalog
            );
            assert!(backup.join("v2/calls/logs/preserved.txt").exists());
        }
    }
    Ok(())
}

#[tokio::test]
async fn orphan_database_sidecars_in_other_v2_root_are_not_ignored() -> Result<()> {
    for name in ["studio.sqlite", "calls/calls.sqlite"] {
        let temp = tempfile::tempdir()?;
        let (paths, _) = fixture(temp.path(), false, false).await?;
        let sidecar = temp.path().join(format!("studio/v2/{name}-wal"));
        tokio::fs::create_dir_all(sidecar.parent().context("sidecar parent")?).await?;
        tokio::fs::write(&sidecar, b"orphan database bytes").await?;
        for _ in 0..2 {
            prepare(&paths).await.expect_err(name);
            assert!(!paths.layout_file().exists());
        }
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert_eq!(
            tokio::fs::read(backup_root(&paths, &journal).join(sidecar.strip_prefix(temp.path())?))
                .await?,
            b"orphan database bytes"
        );
    }
    Ok(())
}

#[tokio::test]
async fn fresh_and_cache_only_v2_homes_create_complete_current_installations() -> Result<()> {
    for cache_only in [false, true] {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::from_home(temp.path().to_owned());
        if cache_only {
            tokio::fs::create_dir_all(temp.path().join("v2/model-catalogs")).await?;
            tokio::fs::write(
                temp.path().join("v2/model-catalogs/cache"),
                b"rebuildable catalog bytes",
            )
            .await?;
        }
        prepare(&paths).await?;
        prepare(&paths).await?;
        let store = StudioStore::prepare_database(&paths.database()).await?;
        assert!(store.catalog().entries().is_empty());
        assert!(paths.calls_database().exists());
        assert!(paths.database().exists());
        assert!(paths.layout_file().exists());
        store.close().await?;
        if cache_only {
            assert_eq!(
                tokio::fs::read(paths.model_catalogs_dir().join("cache")).await?,
                b"rebuildable catalog bytes"
            );
        }
    }
    Ok(())
}

#[tokio::test]
async fn building_fresh_staging_resumes_product_and_documents_before_calls() -> Result<()> {
    for cache_only in [false, true] {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::from_home(temp.path().to_owned());
        if cache_only {
            tokio::fs::create_dir_all(temp.path().join("v2/model-catalogs")).await?;
            tokio::fs::write(
                temp.path().join("v2/model-catalogs/cache"),
                b"retained cache",
            )
            .await?;
        }
        let mut journal = Journal {
            schema_version: 1,
            operation_id: "layout-interrupted-fresh".into(),
            phase: Phase::Building,
            roots: ROOTS
                .into_iter()
                .map(|source| {
                    let present = temp.path().join(source).exists();
                    RootMove {
                        source: source.into(),
                        present,
                        moved: present,
                    }
                })
                .collect(),
            copied: BTreeSet::new(),
            bot_roots: Vec::new(),
        };
        let backup = backup_root(&paths, &journal);
        for root in &journal.roots {
            if root.present {
                managed_move(&temp.path().join(&root.source), &backup.join(&root.source)).await?;
            }
        }
        let journal_path = temp.path().join(JOURNAL);
        persist(&journal_path, &journal).await?;
        let stage = staging(&paths, &journal);
        tokio::fs::create_dir_all(stage.data_dir()).await?;
        let _ = build(&paths, &stage, &backup, &journal_path, &mut journal).await?;

        // Synthesize the precise interrupted phase from a closed production donor: product and
        // all canonical TOML exist, calls has never been created. This is not crash injection.
        let donor_home = tempfile::tempdir()?;
        let donor = StudioPaths::from_home(donor_home.path().to_owned());
        let store = StudioStore::prepare_database(&donor.database()).await?;
        let payload = r#"{"retained":"staging-owned"}"#;
        store.database().execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "INSERT INTO studio_objects VALUES ('thread','stage-owner','resumeProbe',7,1,?,?,42)",
            vec![payload.into(), pl_core::context::content_hash(payload.as_bytes()).into()],
        )).await?;
        store.close().await?;
        for name in [
            "studio.sqlite",
            "studio.sqlite-wal",
            "studio.sqlite-shm",
            "settings.toml",
            "catalog.toml",
            "workspaces.toml",
        ] {
            let source = donor.data_dir().join(name);
            if source.exists() {
                copy_tree(paths.home(), &source, &stage.data_dir().join(name)).await?;
            }
        }
        assert!(!stage.calls_database().exists());
        assert!(!stage.layout_file().exists());
        // The same files without the operation's capability still fail the normal Existing gate.
        let error = StudioStore::prepare_database(&stage.database())
            .await
            .err()
            .context("normal prepare must not treat a missing calls DB as fresh")?;
        assert!(format!("{error:#}").contains("calls/calls.sqlite is missing"));

        for _ in 0..2 {
            let runtime = crate::StudioRuntime::initialize(crate::StudioRuntimeOptions {
                studio_home: Some(temp.path().to_owned()),
                host: crate::StudioHostKind::Test,
                ..crate::StudioRuntimeOptions::desktop()
            })
            .await?;
            runtime.shutdown_runtime().await?;
            assert!(paths.database().exists());
            assert!(paths.calls_database().exists());
            let saved = decode_journal(&tokio::fs::read_to_string(&journal_path).await?)?;
            assert_eq!(saved.operation_id, journal.operation_id);
            assert_eq!(saved.phase, Phase::Completed);
            assert!(!stage.data_dir().exists());
        }
        let mut database = sea_orm::sqlx::SqliteConnection::connect_with(
            &sea_orm::sqlx::sqlite::SqliteConnectOptions::new()
                .filename(paths.database())
                .read_only(true),
        )
        .await?;
        let retained: (i64, String) = sea_orm::sqlx::query_as(
            "SELECT revision,payload_json FROM studio_objects WHERE object_kind='resumeProbe'",
        )
        .fetch_one(&mut database)
        .await?;
        assert_eq!(retained, (7, payload.into()));
        database.close().await?;
        if cache_only {
            assert_eq!(
                tokio::fs::read(backup.join("v2/model-catalogs/cache")).await?,
                b"retained cache"
            );
            assert_eq!(
                tokio::fs::read(paths.model_catalogs_dir().join("cache")).await?,
                b"retained cache"
            );
        }
    }
    Ok(())
}

#[tokio::test]
async fn unknown_v2_material_is_not_a_fresh_installation() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let paths = StudioPaths::from_home(temp.path().to_owned());
    tokio::fs::create_dir_all(temp.path().join("v2")).await?;
    tokio::fs::write(temp.path().join("v2/unknown"), b"unclassified state").await?;
    for _ in 0..2 {
        prepare(&paths)
            .await
            .expect_err("unknown installation evidence");
        assert!(!paths.data_dir().exists());
    }
    let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
    assert_eq!(
        tokio::fs::read(backup_root(&paths, &journal).join("v2/unknown")).await?,
        b"unclassified state"
    );
    Ok(())
}

#[tokio::test]
async fn failed_shared_attachment_batch_keeps_tool_and_prior_attachment_resources() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, _) = fixture(temp.path(), false, false).await?;
    prepare(&paths).await?;
    let store = StudioStore::prepare_database(&paths.database()).await?;
    let session = paths.session_paths(OWNER, THREAD)?;
    let hash = hex::encode(Sha256::digest(BODY));
    let draft = attachment::AttachmentDraftObject {
        draft_id: "new-draft".into(),
        modality: pl_protocol::studio::StudioAttachmentModality::File,
        media_type: "text/plain".into(),
        filename: "same.txt".into(),
        storage_path: session.resources_dir().join(&hash),
        byte_size: BODY.len() as u64,
        content_sha256: hash.clone(),
        width: None,
        height: None,
        initial_remote_url: None,
    };
    let mut missing = draft.clone();
    missing.storage_path = temp.path().join("not-created");
    assert!(
        store
            .promote_attachment_drafts(THREAD, &[draft.clone(), missing])
            .await
            .is_err()
    );
    assert_eq!(
        store
            .read_attachment_bytes(THREAD, "kept-attachment-id")
            .await?,
        BODY
    );
    assert_eq!(std::fs::read_dir(session.resources_dir())?.count(), 1);
    let promoted = store.promote_attachment_drafts(THREAD, &[draft]).await?;
    assert_eq!(promoted[0].blob_relative_path, format!("resources/{hash}"));
    assert_eq!(std::fs::read_dir(session.resources_dir())?.count(), 1);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn interrupted_build_resumes_verified_copies_and_current_missing_authority_is_not_reset()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, session) = fixture(temp.path(), false, false).await?;
    let hash = hex::encode(Sha256::digest(BODY));
    tokio::fs::remove_file(session.join("blobs").join(&hash)).await?;
    assert!(prepare(&paths).await.is_err());
    let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
    assert_eq!(journal.phase, Phase::Building);
    let original = backup_root(&paths, &journal).join(session.strip_prefix(temp.path())?);
    let checkpoint = staging(&paths, &journal)
        .session_paths(OWNER, THREAD)?
        .root()
        .join("blobs/checkpoint/saved");
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        assert!(checkpoint.as_os_str().encode_wide().count() > 260);
    }
    // The missing attachment interrupts the build only after deep owned copies are published.
    // Reuse requires identical bytes, and a conflicting copy must never reclaim that target.
    let saved = tokio::fs::read(original.join("blobs/checkpoint/saved")).await?;
    assert_eq!(tokio::fs::read(&checkpoint).await?, saved);
    copy_tree(
        paths.home(),
        &original.join("blobs/checkpoint/saved"),
        &checkpoint,
    )
    .await?;
    let error = copy_tree(
        paths.home(),
        &original.join("attachments.toml"),
        &checkpoint,
    )
    .await
    .expect_err("conflicting copy must preserve the already published checkpoint");
    assert!(format!("{error:#}").contains("conflicting migration copy"));
    assert_eq!(tokio::fs::read(&checkpoint).await?, saved);
    assert!(!paths.layout_file().exists());
    tokio::fs::write(original.join("blobs").join(&hash), BODY).await?;
    prepare(&paths).await?;
    let marker = tokio::fs::read(paths.layout_file()).await?;
    tokio::fs::remove_file(paths.catalog_file()).await?;
    for _ in 0..2 {
        assert!(prepare(&paths).await.is_err());
    }
    assert!(!paths.catalog_file().exists());
    assert_eq!(tokio::fs::read(paths.layout_file()).await?, marker);
    assert!(original.join("attachments.toml").exists());
    Ok(())
}

#[tokio::test]
async fn future_layout_and_storage_journal_versions_are_not_new_installations() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let paths = StudioPaths::from_home(temp.path().to_owned());
    for content in [
        "schemaVersion=99\noperationId='layout-future'\n",
        "schemaVersion=1\noperationId='../escape'\n",
    ] {
        tokio::fs::create_dir_all(paths.data_dir()).await?;
        tokio::fs::write(paths.layout_file(), content).await?;
        assert!(prepare(&paths).await.is_err());
        assert_eq!(
            tokio::fs::read_to_string(paths.layout_file()).await?,
            content
        );
    }
    assert!(
        decode_journal(
            "schemaVersion=99\noperationId='layout-future'\nphase='building'\nroots=[]\ncopied=[]\n"
        )
        .is_err()
    );
    Ok(())
}

fn bot_checkpoint(
    thread_id: &str,
    bot: &str,
    root: &str,
    child: bool,
) -> Result<pl_core::thread::ThreadCheckpoint> {
    use pl_core::{
        context::OpaquePayload,
        thread::{ThreadCheckpoint, ThreadSnapshot, extensions::ExtensionRecord},
    };
    let mut extensions = BTreeMap::from([
        (
            "studio.bot-owner".into(),
            ExtensionRecord {
                revision: 3,
                payload: crate::studio::model_route::encode_bot_owner(bot)?,
            },
        ),
        (
            "studio.project".into(),
            ExtensionRecord {
                revision: 5,
                payload: OpaquePayload::new(
                    "pl.studio.project",
                    1,
                    serde_json::to_string(&crate::studio::WorkspaceRecord {
                        id: OWNER.into(),
                        kind: pl_protocol::studio::WorkspaceKind::Project,
                        name: "Frozen effective owner".into(),
                        path: root.into(),
                        ssh_alias: None,
                        updated_at: 7,
                    })?,
                )?,
            },
        ),
        (
            "unrelated.opaque".into(),
            ExtensionRecord {
                revision: 2,
                payload: OpaquePayload::new(
                    "fixture.opaque",
                    1,
                    format!("original path string: {root}"),
                )?,
            },
        ),
    ]);
    if child {
        extensions.insert(
            "studio.workspace".into(),
            ExtensionRecord {
                revision: 9,
                payload: crate::studio::workspace_receipt::to_payload(
                    &pl_protocol::AgentWorkspaceAssignmentSnapshot {
                        mode: pl_protocol::AgentWorkspaceMode::Directory,
                        project_root: root.into(),
                        root: root.into(),
                        writable_paths: Some(Vec::new()),
                        worktree: None,
                        review_target: None,
                    },
                )?,
            },
        );
    }
    Ok(ThreadCheckpoint::capture(
        thread_id.into(),
        0,
        ThreadSnapshot {
            extensions,
            extension_sequence: 9,
            ..Default::default()
        },
    ))
}

async fn checkpoint_family(
    target: &Path,
    checkpoint: &pl_core::thread::ThreadCheckpoint,
) -> Result<()> {
    let donor = tempfile::tempdir()?;
    let live = donor.path().join("history.sqlite");
    let history =
        crate::studio::storage::history::HistoryStore::open(&live, &checkpoint.thread_id).await?;
    history.import_checkpoint(checkpoint, &[]).await?;
    // The donor is not a migration source. Snapshot its quiescent committed family; no
    // connection ever targets the independently copied fixture while layout migration moves it.
    for suffix in ["", "-wal", "-shm"] {
        let source = donor.path().join(format!("history.sqlite{suffix}"));
        if source.exists() {
            tokio::fs::copy(
                source,
                target.with_file_name(format!("history.sqlite{suffix}")),
            )
            .await?;
        }
    }
    Ok(())
}

async fn prepared_history_family(target: &Path, thread: &str, fence: u64) -> Result<()> {
    let donor = tempfile::tempdir()?;
    let live = donor.path().join("history.sqlite");
    let history = crate::studio::storage::history::HistoryStore::open(&live, thread).await?;
    // The real history owner initializes its schema and commits facts, but no checkpoint import
    // has happened yet. Capture only a quiescent donor, never open the migration fixture in flight.
    history.commit(fence, &[], &[]).await?;
    assert!(history.checkpoint().await?.is_none());
    for suffix in ["", "-wal", "-shm"] {
        let from = donor.path().join(format!("history.sqlite{suffix}"));
        if from.exists() {
            tokio::fs::copy(
                from,
                target.with_file_name(format!("history.sqlite{suffix}")),
            )
            .await?;
        }
    }
    Ok(())
}

async fn bot_binding_fixture(home: &Path, frozen_bot: &str) -> Result<(StudioPaths, String)> {
    // Keep the migration home and frozen workspace on the same native spelling too.
    let home = dunce::canonicalize(home)?;
    let home = home.as_path();
    let (paths, session) = fixture(home, true, false).await?;
    // Freeze the same host-native path representation as BotRuntime's workspace preparation.
    let old_root = dunce::canonicalize(home.join("v2/bots/bot-test-one/workspace"))?
        .to_str()
        .context("old root")?
        .to_owned();
    let catalog_path = home.join("v2/catalog.toml");
    let mut catalog: toml::Table =
        toml::from_str(&tokio::fs::read_to_string(&catalog_path).await?)?;
    let entries = catalog
        .get_mut("entries")
        .and_then(toml::Value::as_array_mut)
        .context("entries")?;
    entries[0]["workspacePath"] = old_root.clone().into();
    let mut child = entries[0].clone();
    child["id"] = "bot-child".into();
    child["agentPath"] = "bot-child".into();
    child["role"] = "child".into();
    child
        .as_table_mut()
        .context("child entry")?
        .insert("parentThreadId".into(), THREAD.into());
    entries.push(child);
    tokio::fs::write(catalog_path, toml::to_string(&catalog)?).await?;
    let manifest_path = session.join("session.toml");
    let mut manifest: toml::Table =
        toml::from_str(&tokio::fs::read_to_string(&manifest_path).await?)?;
    manifest["workspacePath"] = old_root.clone().into();
    tokio::fs::write(manifest_path, toml::to_string(&manifest)?).await?;
    checkpoint_family(
        &session.join("history.sqlite"),
        &bot_checkpoint(THREAD, frozen_bot, &old_root, false)?,
    )
    .await?;
    let child_session = session
        .parent()
        .context("sessions parent")?
        .join(storage_key("bot-child", "Thread")?);
    tokio::fs::create_dir_all(&child_session).await?;
    // A flat v2 child can be proven from canonical ancestry without a legacy manifest.
    let mut child_manifest = manifest;
    child_manifest["threadId"] = "bot-child".into();
    child_manifest.insert("parentThreadId".into(), THREAD.into());
    tokio::fs::write(
        child_session.join("session.toml"),
        toml::to_string(&child_manifest)?,
    )
    .await?;
    let checkpoint = bot_checkpoint("bot-child", frozen_bot, &old_root, true)?;
    tokio::fs::write(
        child_session.join("state.toml"),
        toml::to_string(&checkpoint)?,
    )
    .await?;
    let ledger = home.join("v2/bots/bot-test-one/state.sqlite");
    tokio::fs::create_dir_all(ledger.parent().context("ledger parent")?).await?;
    let mut db = sea_orm::sqlx::SqliteConnection::connect_with(
        &sea_orm::sqlx::sqlite::SqliteConnectOptions::new()
            .filename(&ledger)
            .create_if_missing(true),
    )
    .await?;
    db.execute("CREATE TABLE bot_meta(id INTEGER PRIMARY KEY, schema_version INTEGER); INSERT INTO bot_meta VALUES(1,6); CREATE TABLE thread_bindings(thread_id TEXT, project_id TEXT, status TEXT);").await?;
    sea_orm::sqlx::query("INSERT INTO thread_bindings VALUES (?,?, 'bound')")
        .bind(THREAD)
        .bind(OWNER)
        .execute(&mut db)
        .await?;
    db.close().await?;
    Ok((paths, old_root))
}

async fn frozen_workspace_identity(home: &Path, root: &str) -> Result<()> {
    let database = home.join("v2/studio.sqlite");
    wal_family(&database, true).await?;
    let mut db = sea_orm::sqlx::SqliteConnection::connect_with(
        &sea_orm::sqlx::sqlite::SqliteConnectOptions::new().filename(&database),
    )
    .await?;
    let payload =
        serde_json::json!({"owner":THREAD,"identity":{"endpoint":{"kind":"local"},"root":root}})
            .to_string();
    sea_orm::sqlx::query("INSERT INTO studio_objects(owner_kind,owner_id,object_kind,revision,schema_version,payload_json,payload_hash,updated_at) VALUES ('thread',?,'workspaceIdentity',1,1,?,?,42)")
        .bind(THREAD).bind(&payload).bind(pl_core::context::content_hash(payload.as_bytes())).execute(&mut db).await?;
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn proven_bot_root_and_child_relocate_only_typed_fields_on_demand() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
    frozen_workspace_identity(temp.path(), &old_root).await?;
    prepare(&paths).await?;
    let mapping = bot_roots::for_history(
        &paths.session_paths(OWNER, THREAD)?.history_database(),
        THREAD,
    )
    .await?
    .context("published migration proof")?;
    assert_eq!(
        mapping.threads.len(),
        2,
        "eligible proofs survive TOML serialization"
    );
    assert!(
        mapping
            .threads
            .values()
            .all(|proof| proof.proven_local_root)
    );
    let new_root = paths
        .bot_dir("bot-test-one")
        .join("workspace")
        .to_str()
        .context("new root")?
        .to_owned();
    let catalog: toml::Table =
        toml::from_str(&tokio::fs::read_to_string(paths.catalog_file()).await?)?;
    assert_eq!(
        catalog["revision"].as_integer(),
        Some(9),
        "representation maintenance keeps product revision"
    );
    let workspace: toml::Table =
        toml::from_str(&tokio::fs::read_to_string(paths.workspaces_file()).await?)?;
    assert_eq!(
        workspace["workspaces"][0]["path"].as_str(),
        Some("/isolated-workspace"),
        "real business project is not the managed root"
    );
    let store = StudioStore::prepare_database(&paths.database()).await?;
    assert_eq!(
        store.paths().home(),
        paths.home(),
        "database preparation must preserve the migration home's logical identity"
    );
    assert_eq!(
        store
            .workspace_identity(THREAD)
            .await?
            .context("frozen identity")?
            .root,
        new_root
    );
    for (thread, child) in [(THREAD, false), ("bot-child", true)] {
        assert_eq!(
            store
                .catalog()
                .get(thread)
                .context("catalog")?
                .workspace_path,
            new_root
        );
        let history = store.history_for(OWNER, thread).await?;
        if child {
            store
                .state_for(OWNER, thread)?
                .prepare_recovery(&history)
                .await?;
        }
        let checkpoint = history
            .prepare_model_access()
            .await?
            .context("checkpoint")?;
        assert_eq!(checkpoint.history_fence, 0);
        assert_eq!(checkpoint.state_revision, 0);
        let project = &checkpoint.state.extensions["studio.project"];
        assert_eq!(project.revision, 5);
        let record: crate::studio::WorkspaceRecord =
            serde_json::from_str(project.payload.content())?;
        assert_eq!(record.path, new_root);
        assert_eq!(record.id, OWNER);
        assert_eq!(
            checkpoint.state.extensions["unrelated.opaque"]
                .payload
                .content(),
            format!("original path string: {old_root}")
        );
        if child {
            let assignment = crate::studio::workspace_receipt::from_snapshot(&checkpoint.state)?
                .context("assignment")?;
            assert_eq!(assignment.root, new_root);
            assert_eq!(assignment.project_root, new_root);
            assert_eq!(assignment.writable_paths, Some(Vec::new()));
            assert_eq!(checkpoint.state.extensions["studio.workspace"].revision, 9);
        }
        assert_eq!(
            serde_json::to_value(history.prepare_model_access().await?.context("restart")?)?,
            serde_json::to_value(checkpoint)?
        );
    }
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn prepared_history_without_checkpoint_recovers_verified_toml_and_keeps_sqlite_canonical()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
    let sessions = temp
        .path()
        .join("v2/projects")
        .join(storage_key(OWNER, "Workspace")?)
        .join("sessions");
    let child = sessions.join(storage_key("bot-child", "Thread")?);
    prepared_history_family(&child.join("history.sqlite"), "bot-child", 7).await?;
    let mut original = bot_checkpoint("bot-child", "bot-test-one", &old_root, true)?;
    original.history_fence = 7;
    original.state_revision = 37;
    original.state.commit_sequence = 37;
    // Freeze an already-current delegation fact so this test isolates relocation rather than
    // the independent model-access migration that adds an absent delegation extension.
    original.state.extensions.insert(
        crate::studio::delegation::EXTENSION.into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: 8,
            payload: crate::studio::delegation::encode(Default::default())?,
        },
    );
    let (externalized, bodies) = original.externalize_bodies(0);
    assert!(!bodies.is_empty());
    tokio::fs::create_dir_all(child.join("blobs/checkpoint")).await?;
    for body in bodies {
        let hash = body
            .entry
            .reference
            .digest()
            .strip_prefix("sha256:")
            .context("body hash")?;
        let directory = child.join("blobs/checkpoint").join(&hash[..2]);
        tokio::fs::create_dir_all(&directory).await?;
        tokio::fs::write(directory.join(hash), body.bytes).await?;
    }
    let toml_bytes = toml::to_string(&externalized)?;
    tokio::fs::write(child.join("state.toml"), &toml_bytes).await?;
    // Root already has a committed SQLite checkpoint: even a contradictory/future stale TOML
    // must not supersede it or make owner evidence depend on the wrong source.
    tokio::fs::write(
        sessions
            .join(storage_key(THREAD, "Thread")?)
            .join("state.toml"),
        "schemaVersion = 999\nthreadId = 'stale-foreign-thread'\n",
    )
    .await?;
    prepare(&paths).await?;
    let session = paths.session_paths(OWNER, "bot-child")?;
    let mapping = bot_roots::for_history(&session.history_database(), "bot-child")
        .await?
        .context("published bot proof")?;
    assert!(mapping.threads["bot-child"].proven_local_root);
    let store = StudioStore::prepare_database(&paths.database()).await?;
    let history = store.history_for(OWNER, "bot-child").await?;
    store
        .state_for(OWNER, "bot-child")?
        .prepare_recovery(&history)
        .await?;
    let recovered = history
        .prepare_model_access()
        .await?
        .context("recovered checkpoint")?;
    assert_eq!(recovered.thread_id, original.thread_id);
    assert_eq!(recovered.history_fence, 7);
    assert_eq!(history.watermark().await?, 7);
    assert_eq!(recovered.state_revision, 37);
    assert_eq!(recovered.saved_at, original.saved_at);
    assert_eq!(
        recovered.state.extension_sequence,
        original.state.extension_sequence
    );
    assert_eq!(
        serde_json::to_value(&recovered.state.extensions["unrelated.opaque"])?,
        serde_json::to_value(&original.state.extensions["unrelated.opaque"])?
    );
    let assignment = crate::studio::workspace_receipt::from_snapshot(&recovered.state)?
        .context("child workspace assignment")?;
    assert_eq!(assignment.root, mapping.new_root);
    assert_eq!(assignment.project_root, mapping.new_root);
    assert_eq!(assignment.writable_paths, Some(Vec::new()));
    assert_eq!(recovered.state.extensions["studio.workspace"].revision, 9);
    let owner: crate::studio::WorkspaceRecord = serde_json::from_str(
        recovered.state.extensions["studio.project"]
            .payload
            .content(),
    )?;
    assert_eq!(owner.id, OWNER);
    assert_eq!(owner.path, mapping.new_root);
    assert_eq!(recovered.state.extensions["studio.project"].revision, 5);
    assert_eq!(
        store
            .workspaces()
            .get(OWNER)
            .context("business workspace")?
            .path,
        "/isolated-workspace"
    );
    let canonical_root = store.history_for(OWNER, THREAD).await?;
    assert_eq!(
        canonical_root
            .prepare_model_access()
            .await?
            .context("root checkpoint")?
            .thread_id,
        THREAD
    );
    assert_eq!(
        serde_json::to_value(history.prepare_model_access().await?.context("restart")?)?,
        serde_json::to_value(recovered)?
    );
    store.close().await?;
    let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
    assert_eq!(
        tokio::fs::read_to_string(
            backup_root(&paths, &journal)
                .join(child.strip_prefix(temp.path())?)
                .join("state.toml")
        )
        .await?,
        toml_bytes
    );
    Ok(())
}

#[tokio::test]
async fn prepared_history_toml_window_rejects_unknown_or_conflicting_evidence() -> Result<()> {
    for fault in [
        "foreign-history",
        "future-history",
        "missing-checkpoint-table",
        "unversioned-history",
        "corrupt-history",
        "future-toml",
        "foreign-toml",
        "owner-conflict",
        "missing-body",
        "corrupt-toml",
    ] {
        let temp = tempfile::tempdir()?;
        let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
        let child = temp
            .path()
            .join("v2/projects")
            .join(storage_key(OWNER, "Workspace")?)
            .join("sessions")
            .join(storage_key("bot-child", "Thread")?);
        let database = child.join("history.sqlite");
        let thread = if fault == "foreign-history" {
            "other-thread"
        } else {
            "bot-child"
        };
        prepared_history_family(&database, thread, 7).await?;
        let mut checkpoint = bot_checkpoint("bot-child", "bot-test-one", &old_root, true)?;
        checkpoint.history_fence = 7;
        checkpoint.state_revision = 37;
        checkpoint.state.commit_sequence = 37;
        match fault {
            "future-history" | "missing-checkpoint-table" => {
                let mut db = sea_orm::sqlx::SqliteConnection::connect_with(
                    &sea_orm::sqlx::sqlite::SqliteConnectOptions::new().filename(&database),
                )
                .await?;
                db.execute(if fault == "future-history" {
                    "UPDATE history_meta SET schema_version=999"
                } else {
                    "DROP TABLE session_checkpoint"
                })
                .await?;
                db.close().await?;
            }
            "unversioned-history" | "corrupt-history" => {
                for suffix in ["", "-wal", "-shm"] {
                    let member = child.join(format!("history.sqlite{suffix}"));
                    if member.exists() {
                        tokio::fs::remove_file(member).await?;
                    }
                }
                tokio::fs::write(
                    &database,
                    if fault == "corrupt-history" {
                        b"not sqlite".as_slice()
                    } else {
                        &[]
                    },
                )
                .await?;
            }
            "future-toml" => checkpoint.schema_version = 999,
            "foreign-toml" => checkpoint.thread_id = "foreign-thread".into(),
            "owner-conflict" => {
                checkpoint = bot_checkpoint("bot-child", "bot-other", &old_root, true)?
            }
            "missing-body" => {
                checkpoint = checkpoint.externalize_bodies(0).0;
                assert!(!checkpoint.external_bodies.is_empty());
            }
            _ => {}
        }
        let content = if fault == "corrupt-toml" {
            "broken = [".to_owned()
        } else {
            toml::to_string(&checkpoint)?
        };
        tokio::fs::write(child.join("state.toml"), &content).await?;
        for _ in 0..2 {
            prepare(&paths).await.expect_err(fault);
            assert!(!paths.layout_file().exists(), "{fault}");
        }
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert_eq!(
            tokio::fs::read_to_string(
                backup_root(&paths, &journal)
                    .join(child.strip_prefix(temp.path())?)
                    .join("state.toml")
            )
            .await?,
            content
        );
    }
    Ok(())
}

#[tokio::test]
async fn nonmanaged_identity_is_preserved_with_execution_diagnostic_and_readable_history()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, _) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
    let business_root = temp.path().join("business-project-not-owned-by-bot");
    tokio::fs::create_dir_all(&business_root).await?;
    let business_root = dunce::canonicalize(&business_root)?
        .to_str()
        .context("business root")?
        .to_owned();
    frozen_workspace_identity(temp.path(), &business_root).await?;
    prepare(&paths).await?;
    let store = StudioStore::prepare_database(&paths.database()).await?;
    assert_eq!(
        store
            .workspace_identity(THREAD)
            .await?
            .context("preserved identity")?
            .root,
        business_root
    );
    let history = store.history_for(OWNER, THREAD).await?;
    assert!(
        history.checkpoint().await?.is_some(),
        "content reads do not require execution rebinding"
    );
    let error = history
        .prepare_model_access()
        .await
        .expect_err("unsafe execution must be refused");
    assert!(
        format!("{error:#}").contains("original binding was preserved"),
        "{error:#}"
    );
    assert!(history.checkpoint().await?.is_some());
    store.close().await?;
    prepare(&paths).await?;
    Ok(())
}

#[tokio::test]
async fn conflicting_bot_owner_evidence_preserves_sources_without_publication() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, _) = bot_binding_fixture(temp.path(), "bot-conflicting-owner").await?;
    for _ in 0..2 {
        assert!(prepare(&paths).await.is_err());
        assert!(!paths.layout_file().exists());
    }
    let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
    assert!(
        backup_root(&paths, &journal)
            .join("v2/bots/bot-test-one/state.sqlite")
            .exists()
    );
    Ok(())
}

#[tokio::test]
async fn layout_failure_through_runtime_never_starts_global_reset() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let (paths, source) = fixture(temp.path(), false, false).await?;
    tokio::fs::write(source.join("attachments.toml"), b"bad = [").await?;
    for _ in 0..2 {
        let error = crate::StudioRuntime::initialize(crate::StudioRuntimeOptions {
            studio_home: Some(temp.path().to_owned()),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        })
        .await
        .err()
        .context("runtime must refuse the invalid layout")?;
        assert_eq!(error.kind, crate::StudioStartupErrorKind::Migration);
        assert!(!paths.layout_file().exists());
        assert!(!temp.path().join("startup-backups").exists());
        assert!(!temp.path().join("startup-recovery.toml").exists());
    }
    let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
    let original = backup_root(&paths, &journal).join(source.strip_prefix(temp.path())?);
    assert_eq!(
        tokio::fs::read(original.join("attachments.toml")).await?,
        b"bad = ["
    );
    Ok(())
}

#[cfg(unix)]
#[tokio::test]
async fn linked_sources_and_target_ancestors_fail_without_following_them() -> Result<()> {
    for source_link in [true, false] {
        let temp = tempfile::tempdir()?;
        let outside = tempfile::tempdir()?;
        let (paths, session) = fixture(temp.path(), false, false).await?;
        let sentinel = outside.path().join("sentinel");
        tokio::fs::write(&sentinel, b"unrelated bytes").await?;
        if source_link {
            std::os::unix::fs::symlink(&sentinel, session.join("thread-resources/link"))?;
        } else {
            std::os::unix::fs::symlink(outside.path(), paths.data_dir())?;
        }
        assert!(prepare(&paths).await.is_err());
        assert!(!paths.layout_file().exists());
        assert_eq!(tokio::fs::read(&sentinel).await?, b"unrelated bytes");
    }
    Ok(())
}
