//! A19 storage work, not UI latency or physical IO. All data is synthetic.
use super::*;
use crate::studio::storage::history::{EffectCommit, HistoryStore, TimelinePage};
use anyhow::{Context, Result, ensure};
use pl_core::chat::{
    ChatContent, ChatContentKey, ChatContents, ChatDraft, ChatHistory, ChatItem, ChatKey,
    ContentData, ContentDescriptor, ContentReadRequest, TimelineEpoch,
};
use pl_protocol::ReadDemand;
use pl_protocol::*;
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
    time::Instant,
};

const BODY_BYTES: usize = 4096;
const MEMBERS: usize = 1024;
const PAGE_ITEMS: u32 = 16;
const PAGE_BYTES: u32 = 64 * 1024;
// Deduplicate SQL templates rather than emit thousands of identical statements.
// Both total callback invocations and retained template memory have hard bounds.
const MAX_CALLS: usize = 65_536;
const MAX_TEMPLATES: usize = 128;
const MAX_SQL_BYTES: usize = 32 * 1024;

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct SqlSample {
    calls: usize,
    elapsed_micros: u64,
    failed: usize,
}

struct Capture {
    started: Instant,
    calls: usize,
    overflow: bool,
    sql: BTreeMap<String, SqlSample>,
}

#[derive(Default)]
struct Metrics(Mutex<Option<Capture>>);

struct Phase {
    elapsed_micros: u64,
    calls: usize,
    sql: BTreeMap<String, SqlSample>,
}

fn micros(duration: std::time::Duration) -> u64 {
    u64::try_from(duration.as_micros()).unwrap_or(u64::MAX)
}

impl Metrics {
    fn begin(&self) -> Result<()> {
        let mut capture = self.0.lock().unwrap();
        ensure!(capture.is_none(), "overlapping work measurement phases");
        *capture = Some(Capture {
            started: Instant::now(),
            calls: 0,
            overflow: false,
            sql: BTreeMap::new(),
        });
        Ok(())
    }

    fn observe(&self, info: &sea_orm::metric::Info<'_>) {
        let mut guard = self.0.lock().unwrap();
        let Some(capture) = guard.as_mut() else {
            return; // Seed writes and stock audits are deliberately not measured.
        };
        if capture.calls == MAX_CALLS {
            capture.overflow = true;
            return;
        }
        capture.calls += 1;
        // Never format Statement (Display substitutes bind values), or retain values.
        let sql = &info.statement.sql;
        if sql.len() > MAX_SQL_BYTES
            || (!capture.sql.contains_key(sql) && capture.sql.len() == MAX_TEMPLATES)
        {
            capture.overflow = true;
            return;
        }
        let sample = capture.sql.entry(sql.clone()).or_default();
        sample.calls += 1;
        sample.elapsed_micros = sample.elapsed_micros.saturating_add(micros(info.elapsed));
        sample.failed += usize::from(info.failed);
    }

    fn end(&self) -> Result<Phase> {
        let capture = self
            .0
            .lock()
            .unwrap()
            .take()
            .context("missing work phase")?;
        ensure!(!capture.overflow, "SQL evidence collection overflowed");
        ensure!(
            capture.sql.values().all(|sample| sample.failed == 0),
            "measured SQL failed"
        );
        Ok(Phase {
            elapsed_micros: micros(capture.started.elapsed()),
            calls: capture.calls,
            sql: capture.sql,
        })
    }
}

impl Phase {
    fn report(&self, name: &str, items: usize, members: usize, bytes: usize) -> Value {
        json!({
            "phase": name,
            "elapsedMicros": self.elapsed_micros,
            "seaOrmCallbackCalls": self.calls,
            "sqlTemplates": self.sql,
            "returnedItemRows": items,
            "returnedMemberRows": members,
            "contentBytes": bytes,
            "actualSqlFetchRows": null,
            "physicalIoBytes": null,
        })
    }

    fn signature(&self) -> Vec<(&str, usize)> {
        self.sql
            .iter()
            .map(|(sql, sample)| (sql.as_str(), sample.calls))
            .collect()
    }

    fn assert_no_bodies(&self) {
        for sql in self.sql.keys() {
            let sql = sql.to_ascii_lowercase();
            assert!(!sql.contains("conversation_contents"), "{sql}");
            assert!(!sql.contains("conversation_content_chunks"), "{sql}");
            assert!(
                !sql.contains("select payload from conversation_items"),
                "{sql}"
            );
        }
    }

    fn assert_main(&self) {
        assert!(self.calls > 0, "must observe the real connection");
        self.assert_no_bodies();
        assert!(
            self.sql
                .keys()
                .any(|sql| { sql.contains("FROM timeline_items WHERE location='history'") }),
            "Main must hit the saved summary index"
        );
        for sql in self.sql.keys() {
            let sql = sql.to_ascii_lowercase();
            assert!(!sql.contains("timeline_item_members"), "{sql}");
            assert!(!sql.contains("conversation_items"), "{sql}");
            assert!(!sql.contains("count(") && !sql.contains(" join "), "{sql}");
        }
    }
}

fn member_id(index: usize) -> String {
    format!("member-{index:04}")
}

fn body(index: usize) -> Vec<u8> {
    (0..BODY_BYTES)
        .map(|offset| ((index + offset) % 251) as u8)
        .collect()
}

fn source() -> ChatSourceId {
    ChatSourceId::ForegroundTurn {
        turn_id: "work".into(),
    }
}

fn position(effect: u64, suborder: u32) -> ChatFactPosition {
    ChatFactPosition {
        effect_seq: effect,
        suborder,
    }
}

fn body_reference(database: &str, id: &str) -> ContentRef {
    ContentRef {
        database_id: database.into(),
        target: ContentTarget::Body {
            owner: ContentOwner::Item { item_id: id.into() },
            key: "body".into(),
        },
    }
}

async fn commit(
    store: &HistoryStore,
    projection: &mut TimelineProjection,
    effect: u64,
    completions: &[Arc<ChatItem>],
    sources: Vec<ChatSourceState>,
) -> Result<()> {
    projection.commit_ready()?;
    let timeline: Vec<_> = projection
        .take_committed()
        .into_iter()
        .map(|item| PreparedTimelineItem { item })
        .collect();
    let mut current = CurrentProjection::empty(effect, ThreadStatus::Idle);
    current.items = projection.current_items();
    current.sources = sources.clone();
    let prepared = PreparedCurrent {
        projection: current,
        timeline_commit: if timeline.is_empty() { 0 } else { effect },
        timeline: timeline.into(),
        timeline_update: Arc::new(projection.take_update()?),
        source_changes: sources.into(),
        changes: Arc::from([]),
        contents: Arc::from([]),
    };
    store
        .commit_effect(
            effect,
            EffectCommit {
                items: &[],
                completions,
                current: &prepared,
                rolled_back_turns: &Default::default(),
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            },
        )
        .await?;
    Ok(())
}

struct Fixture {
    // Only one HistoryStore owner; no Session or live owner pre-caches the members.
    store: HistoryStore,
    _directory: tempfile::TempDir,
    count: usize,
    effect: u64,
    metrics: Arc<Metrics>,
}

impl Fixture {
    async fn seed(count: usize) -> Result<Self> {
        let directory = tempfile::tempdir()?;
        let mut store = HistoryStore::open(&directory.path().join("history.sqlite"), "a19").await?;
        store.prepare_write().await?;
        let (database, generation, next, _) = store
            .timeline_snapshot()
            .await?
            .context("initialized Timeline")?;
        let mut projection = TimelineProjection::new(database.clone(), generation, next);
        for index in 0..count {
            let id = member_id(index);
            let effect = index as u64 + 1;
            let start = ChatAtom {
                id: id.clone(),
                completion_item_id: None,
                completion_seq: None,
                source: source(),
                source_state: None,
                source_order: Some(effect),
                kind: ChatAtomKind::Reasoning,
                delivery: ChatDeliveryKind::Foreground,
                lifecycle: ChatAtomLifecycle::Active {
                    started: Some(position(effect, 0)),
                    status: ChatActiveStatus::Running,
                },
                turn_id: Some("work".into()),
                attempt_id: None,
                tool: None,
                wait: None,
                text_channel: None,
                started_at: Some(effect as i64 * 2),
                finished_at: None,
                content_present: Some(true),
                contents: vec![ChatAtomContent {
                    role: ChatContentRole::ReasoningSummary,
                    reference: body_reference(&database, &id),
                }],
                payload: None,
            };
            projection.observe(&start, None)?;
            let mut terminal = start.clone();
            terminal.lifecycle = ChatAtomLifecycle::Terminal {
                started: Some(position(effect, 0)),
                ended: Some(position(effect, 1)),
                outcome: ChatTerminalOutcome::Completed,
            };
            terminal.completion_item_id = Some(id.clone());
            terminal.completion_seq = Some(effect);
            terminal.finished_at = Some(effect as i64 * 2 + 1);
            let payload: Arc<[u8]> = serde_json::to_vec(&json!({
                "contract": "anywork.chat/1", "type": "thinking",
                "data": {"content": body_reference(&database, &id), "byteLength": BODY_BYTES}
            }))?
            .into();
            let key = ChatContentKey {
                owner: ChatKey::new("item", &id)?,
                key: "body".into(),
            };
            let content = Arc::new(ChatContent {
                descriptor: ContentDescriptor {
                    key: key.clone(),
                    byte_length: BODY_BYTES as u64,
                    generation: 1,
                    media_type: None,
                },
                data: ContentData::Bytes(body(index).into()),
            });
            let mut draft = ChatDraft::new(&id, "conversation", payload.clone());
            draft.parent_id = Some(ChatKey::new("turn", "work")?);
            let mut metadata = terminal.clone();
            metadata.completion_seq = None;
            draft.metadata = serde_json::to_vec(&metadata)?.into();
            draft.contents = Arc::new(ChatContents::from([(key, content)]));
            let record = Arc::new(ChatItem::complete(draft, effect));
            projection.complete(
                terminal,
                effect,
                Some(PayloadData::Deferred {
                    reference: ContentRef {
                        database_id: database.clone(),
                        target: ContentTarget::ItemPayload { item_id: id },
                    },
                    byte_length: payload.len() as u64,
                }),
            )?;
            // A real synthetic start and terminal share this effect, with distinct
            // suborders. Only one active member is ever retained in the fold.
            let changes = if index == 0 {
                vec![ChatSourceState {
                    source: source(),
                    lifecycle: ChatSourceLifecycle::Active,
                    started: Some(position(1, 0)),
                    ended: None,
                }]
            } else {
                Vec::new()
            };
            commit(&store, &mut projection, effect, &[record], changes).await?;
        }
        let effect = count as u64 + 1;
        projection.end_source(&source());
        commit(
            &store,
            &mut projection,
            effect,
            &[],
            vec![ChatSourceState {
                source: source(),
                lifecycle: ChatSourceLifecycle::Ended {
                    outcome: ChatTerminalOutcome::Completed,
                },
                started: Some(position(1, 0)),
                ended: Some(position(effect, 0)),
            }],
        )
        .await?;
        drop(projection);
        // Initialize the independent actual reader outside the timed/SQL phases.
        store.reader().await?.context("independent reader")?;
        store.timeline_generation().await?;
        let metrics = Arc::new(Metrics::default());
        {
            let state = Arc::get_mut(&mut store.state)
                .context("A19 must exclusively own the real HistoryStore state")?;
            for connection in [&mut state.writer, &mut state.reader] {
                let connection = connection
                    .get_mut()
                    .context("original initialized connection")?;
                let metrics = metrics.clone();
                // Mutate each original wrapper, never a DatabaseConnection clone.
                connection
                    .db
                    .set_metric_callback(move |info| metrics.observe(info));
            }
        }
        Ok(Self {
            store,
            _directory: directory,
            count,
            effect,
            metrics,
        })
    }

    async fn main_page(&self) -> Result<TimelinePage> {
        self.store
            .timeline_page(
                &ChatScope::Main,
                None,
                i64::MAX as u64,
                self.effect,
                ReadDemand {
                    max_items: 1,
                    max_bytes: PAGE_BYTES,
                },
                0,
            )
            .await
    }

    async fn members(
        &self,
        reference: &TimelineMembersRef,
        before: Option<u64>,
    ) -> Result<TimelinePage> {
        self.store
            .timeline_page(
                &ChatScope::GroupMembers {
                    reference: reference.clone(),
                },
                before,
                self.count as u64,
                self.effect,
                ReadDemand {
                    max_items: PAGE_ITEMS,
                    max_bytes: PAGE_BYTES,
                },
                0,
            )
            .await
    }

    async fn stock(&self) -> Result<Value> {
        let db = &self.store.reader().await?.context("stock reader")?.db;
        let mut rows = serde_json::Map::new();
        for table in [
            "conversation_items",
            "conversation_contents",
            "conversation_content_chunks",
            "conversation_atom_facts",
            "conversation_sources",
            "timeline_items",
            "timeline_item_members",
        ] {
            let row = db
                .query_one_raw(statement(
                    &format!("SELECT COUNT(*) AS rows FROM {table}"),
                    vec![],
                ))
                .await?
                .context("stock row count")?;
            rows.insert(table.into(), json!(row.try_get::<i64>("", "rows")?));
        }
        assert_eq!(rows["conversation_items"], json!(self.count));
        assert_eq!(rows["conversation_contents"], json!(self.count));
        assert_eq!(rows["conversation_atom_facts"], json!(self.count * 2));
        assert_eq!(rows["conversation_sources"], json!(1));
        assert_eq!(rows["timeline_items"], json!(1));
        assert_eq!(rows["timeline_item_members"], json!(self.count));
        let mut encoded = serde_json::Map::new();
        for (table, column) in [
            ("conversation_items", "payload"),
            ("conversation_atom_facts", "metadata"),
            ("conversation_content_chunks", "data"),
            ("timeline_items", "metadata"),
            ("timeline_item_members", "metadata"),
            ("timeline_projection_state", "recovery"),
        ] {
            let row = db
                .query_one_raw(statement(
                    &format!("SELECT COALESCE(SUM(length({column})),0) AS bytes FROM {table}"),
                    vec![],
                ))
                .await?
                .context("encoded stock bytes")?;
            encoded.insert(table.into(), json!(row.try_get::<i64>("", "bytes")?));
        }
        assert_eq!(
            encoded["conversation_content_chunks"],
            json!(self.count * BODY_BYTES)
        );
        // SQLite's official optional module is the only source for actual B-tree space.
        let dbstat = if db
            .query_one_raw(statement(
                "SELECT 1 FROM pragma_module_list WHERE name='dbstat'",
                vec![],
            ))
            .await?
            .is_some()
        {
            let entries = db
                .query_all_raw(statement(
                    "SELECT name,SUM(pgsize) AS bytes FROM dbstat
                 WHERE name='timeline_item_members' OR name IN
                   (SELECT name FROM sqlite_schema WHERE type='index'
                    AND tbl_name='timeline_item_members') GROUP BY name",
                    vec![],
                ))
                .await?;
            let mut btrees = Vec::new();
            for entry in entries {
                btrees.push(json!({"name": entry.try_get::<String>("", "name")?,
                    "bytes": entry.try_get::<i64>("", "bytes")?}));
            }
            json!({"status":"measured", "module":"dbstat", "btrees": btrees})
        } else {
            json!({"status":"unavailable", "module":"dbstat", "btrees": null})
        };
        Ok(json!({"rows": rows, "encodedColumnBytes": encoded, "memberBtreeSpace": dbstat}))
    }

    async fn read_body(&self, index: usize) -> Result<usize> {
        let request = ContentReadRequest {
            epoch: TimelineEpoch::new("a19")?,
            reference: pl_core::chat::ContentRef::Body(ChatContentKey {
                owner: ChatKey::new("item", &member_id(index))?,
                key: "body".into(),
            }),
            offset: 0,
            max_bytes: BODY_BYTES,
            generation: Some(1),
        };
        let window = ChatHistory::read_content(&self.store, &request).await?;
        assert_eq!(window.bytes.as_bytes(), body(index));
        assert_eq!(window.available_through, BODY_BYTES as u64);
        assert!(window.sealed);
        Ok(window.bytes.as_bytes().len())
    }

    async fn inventory(&self, reference: &TimelineMembersRef) -> Result<(Vec<String>, usize)> {
        let mut ids = Vec::new();
        let mut before = None;
        let mut pages = 0;
        loop {
            let page = self.members(reference, before).await?;
            check_members(&page, reference, self.count, before)?;
            for entry in page.entries.iter().rev() {
                let ChatEntry::Atom(atom) = entry else {
                    unreachable!()
                };
                ids.push(atom.id.clone());
            }
            pages += 1;
            if page.before.is_none() {
                break;
            }
            ensure!(page.before != before, "member cursor failed to advance");
            before = page.before;
        }
        assert_eq!(
            ids,
            (0..self.count).rev().map(member_id).collect::<Vec<_>>()
        );
        Ok((ids, pages))
    }
}

fn group(page: &TimelinePage, count: usize) -> Result<TimelineItem> {
    let [ChatEntry::Item(item)] = page.entries.as_slice() else {
        anyhow::bail!("Main must return exactly one saved WorkGroup");
    };
    assert_eq!(item.kind, TimelineItemKind::WorkGroup);
    let summary = item.summary.as_ref().context("group summary")?;
    assert_eq!(summary.member_count as usize, count);
    assert_eq!(
        (
            summary.active_count,
            summary.failed_count,
            summary.cancelled_count
        ),
        (0, 0, 0)
    );
    assert_eq!(
        summary.categories,
        vec![TimelineCategoryCount {
            category: TimelineCategory::Thinking,
            count: count as u32,
        }]
    );
    assert_eq!(summary.started_at, Some(2));
    assert_eq!(summary.finished_at, Some(count as i64 * 2 + 1));
    assert!(item.contents.is_empty() && item.payload.is_none());
    assert!(item.content_item_id.is_none());
    assert_eq!(item.position, Some(0));
    assert!(item.admission_closed);
    assert_eq!(page.ceiling, 1);
    assert!(page.before.is_none());
    Ok(item.as_ref().clone())
}

fn check_members(
    page: &TimelinePage,
    reference: &TimelineMembersRef,
    count: usize,
    before: Option<u64>,
) -> Result<()> {
    assert_eq!(page.generation, reference.projection_generation);
    assert!(page.entries.len() <= PAGE_ITEMS as usize);
    assert!(
        page.entries
            .iter()
            .map(entry_bytes)
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .sum::<usize>()
            <= PAGE_BYTES as usize
    );
    let upper = before.unwrap_or(count as u64) as usize;
    let first = upper.saturating_sub(page.entries.len());
    for (index, entry) in (first..upper).zip(&page.entries) {
        let ChatEntry::Atom(atom) = entry else {
            anyhow::bail!("member scope returned non-Atom")
        };
        assert_eq!(atom.id, member_id(index));
        assert_eq!(atom.source_order, Some(index as u64 + 1));
        assert_eq!(atom.kind, ChatAtomKind::Reasoning);
        assert!(matches!(
            atom.lifecycle,
            ChatAtomLifecycle::Terminal {
                outcome: ChatTerminalOutcome::Completed,
                ..
            }
        ));
        assert_eq!(
            atom.contents,
            vec![ChatAtomContent {
                role: ChatContentRole::ReasoningSummary,
                reference: body_reference(&reference.database_id, &atom.id),
            }]
        );
        assert!(
            matches!(&atom.payload, Some(PayloadData::Deferred { reference: payload, .. })
            if payload.database_id == reference.database_id
            && payload.target == ContentTarget::ItemPayload { item_id: atom.id.clone() })
        );
    }
    Ok(())
}

#[tokio::test]
async fn a19_large_folded_group_uses_constant_main_sql_and_independent_member_body_work()
-> Result<()> {
    let mut phases = Vec::new();
    let small = Fixture::seed(32).await?;
    let fixture = Fixture::seed(MEMBERS).await?;
    let small_stock = small.stock().await?;
    let before_stock = fixture.stock().await?;
    small.metrics.begin()?;
    let small_page = small.main_page().await?;
    group(&small_page, 32)?;
    let small_main = small.metrics.end()?;
    small_main.assert_main();
    phases.push(small_main.report("main32", 1, 0, 0));

    fixture.metrics.begin()?;
    let main = fixture.main_page().await?;
    let original = group(&main, MEMBERS)?;
    let main_work = fixture.metrics.end()?;
    main_work.assert_main();
    assert_eq!(
        small_main.signature(),
        main_work.signature(),
        "32 and 1024 members must use identical Main SQL work"
    );
    phases.push(main_work.report("main1024", 1, 0, 0));
    let reference = original.members.as_ref().context("typed members ref")?;
    let main_cursor = (main.before, main.ceiling);

    fixture.metrics.begin()?;
    let window = fixture.members(reference, None).await?;
    check_members(&window, reference, MEMBERS, None)?;
    assert_eq!(window.entries.len(), PAGE_ITEMS as usize);
    let member_work = fixture.metrics.end()?;
    member_work.assert_no_bodies();
    assert!(
        member_work
            .sql
            .keys()
            .any(|sql| sql.contains("FROM timeline_item_members"))
    );
    phases.push(member_work.report("firstMemberWindow", 0, window.entries.len(), 0));
    let selected = MEMBERS - PAGE_ITEMS as usize;
    fixture.metrics.begin()?;
    let bytes = fixture.read_body(selected).await?;
    let body_work = fixture.metrics.end()?;
    let mut body_report = body_work.report("explicitSelectedBody", 0, 0, bytes);
    body_report["contentRangeRequests"] = json!(1);
    body_report["actualContentSqlQueries"] = Value::Null;
    body_report["sqlCoverage"] = json!("SeaORM only; native SQLx/BLOB range SQL is not observed");
    phases.push(body_report);

    fixture.metrics.begin()?;
    let main_after_members = fixture.main_page().await?;
    assert_eq!(main_after_members.entries, main.entries);
    assert_eq!(
        (main_after_members.before, main_after_members.ceiling),
        main_cursor
    );
    let reread = fixture.metrics.end()?;
    reread.assert_main();
    phases.push(reread.report("mainAfterMemberWindow", 1, 0, 0));

    fixture.metrics.begin()?;
    let (old_order, pages) = fixture.inventory(reference).await?;
    let inventory = fixture.metrics.end()?;
    inventory.assert_no_bodies();
    let mut inventory_report = inventory.report("completeMemberInventory", 0, old_order.len(), 0);
    inventory_report["returnedPages"] = json!(pages);
    phases.push(inventory_report);
    // Original byte verification is explicit and separate from folded/member reads.
    fixture.metrics.begin()?;
    let mut bytes = 0;
    for index in 0..MEMBERS {
        bytes += fixture.read_body(index).await?;
    }
    let mut report = fixture
        .metrics
        .end()?
        .report("originalBodyInventory", 0, 0, bytes);
    report["contentRangeRequests"] = json!(MEMBERS);
    report["actualContentSqlQueries"] = Value::Null;
    report["sqlCoverage"] = json!("SeaORM only; native SQLx/BLOB range SQL is not observed");
    phases.push(report);

    // Delete only the reproducible model, outside measured rebuild; retain every
    // canonical start/terminal/source boundary, completion, manifest and body.
    fixture.store.writer().await?.db.execute_unprepared(
        "DROP TABLE timeline_item_members; DROP TABLE timeline_items; DROP TABLE timeline_projection_state;"
    ).await?;
    fixture.metrics.begin()?;
    fixture.store.maintain_timeline().await?;
    let rebuild = fixture.metrics.end()?;
    let rebuild_elapsed = rebuild.elapsed_micros;
    assert!(
        rebuild.calls > 0,
        "must observe the original rebuilding writer"
    );
    assert!(
        rebuild
            .sql
            .keys()
            .any(|sql| sql.contains("conversation_atom_facts")),
        "rebuild must read original canonical facts"
    );
    rebuild.assert_no_bodies();
    phases.push(rebuild.report("rebuildFromOriginalFacts", 0, 0, 0));
    fixture.metrics.begin()?;
    let rebuilt_main = fixture.main_page().await?;
    let rebuilt = group(&rebuilt_main, MEMBERS)?;
    let after_main = fixture.metrics.end()?;
    after_main.assert_main();
    phases.push(after_main.report("rebuiltMain", 1, 0, 0));
    let rebuilt_ref = rebuilt.members.as_ref().context("rebuilt member ref")?;
    assert_ne!(
        reference.projection_generation,
        rebuilt_ref.projection_generation
    );
    let mut logical = rebuilt.clone();
    logical.members.as_mut().unwrap().projection_generation =
        reference.projection_generation.clone();
    assert_eq!(logical, original);
    let stale = fixture
        .members(reference, None)
        .await
        .err()
        .context("old member ref was accepted")?;
    assert!(matches!(
        stale.downcast_ref::<pl_core::chat::ChatError>(),
        Some(pl_core::chat::ChatError::StaleContent)
    ));
    fixture.metrics.begin()?;
    let (new_order, pages) = fixture.inventory(rebuilt_ref).await?;
    assert_eq!(new_order, old_order);
    let rebuilt_inventory = fixture.metrics.end()?;
    rebuilt_inventory.assert_no_bodies();
    let mut report = rebuilt_inventory.report("rebuiltMemberInventory", 0, new_order.len(), 0);
    report["returnedPages"] = json!(pages);
    phases.push(report);
    fixture.metrics.begin()?;
    let mut bytes = 0;
    for index in 0..MEMBERS {
        bytes += fixture.read_body(index).await?;
    }
    let mut report = fixture
        .metrics
        .end()?
        .report("rebuiltBodyInventory", 0, 0, bytes);
    report["contentRangeRequests"] = json!(MEMBERS);
    report["actualContentSqlQueries"] = Value::Null;
    report["sqlCoverage"] = json!("SeaORM only; native SQLx/BLOB range SQL is not observed");
    phases.push(report);
    let after_stock = fixture.stock().await?;
    assert_eq!(before_stock["rows"], after_stock["rows"]);
    for table in [
        "conversation_items",
        "conversation_atom_facts",
        "conversation_content_chunks",
    ] {
        assert_eq!(
            before_stock["encodedColumnBytes"][table],
            after_stock["encodedColumnBytes"][table]
        );
    }
    let evidence = json!({
        "schemaVersion": 1,
        "platform": {"os": std::env::consts::OS, "arch": std::env::consts::ARCH},
        "buildMode": if cfg!(debug_assertions) { "debug" } else { "release" },
        "fixture": {"smallMembers": 32, "smallStock": small_stock,
            "largeMembers": MEMBERS, "bodyBytesPerMember": BODY_BYTES,
            "originalBodyBytes": MEMBERS * BODY_BYTES, "stockBefore": before_stock,
            "stockAfter": after_stock},
        "measurement": {"component": "SeaORM 2.0.4 real original reader/writer metric callbacks",
            "bindValuesRecorded": false, "sqlTemplateLimit": MAX_TEMPLATES,
            "sqlBytesPerTemplateLimit": MAX_SQL_BYTES, "callbackCallsPerPhaseLimit": MAX_CALLS,
            "overflowInvalidatesEvidence": true, "seedAndStockAuditsIncluded": false,
            "sqlActualFetchRows": null, "nativeSqlxBlobSqlQueries": null},
        "phases": phases,
        "rebuild": {"elapsedMicros": rebuild_elapsed, "sameLogicalItem": true,
            "sameMemberOrder": true, "allOriginalBodyBytesVerified": true,
            "generationChanged": true, "oldRefRejected": true},
        "notMeasured": {"physicalIoBytes": null, "osCacheState": null,
            "flutterLayout": null, "realMediaFiles": null, "nativeFirstContentP95Micros": null},
    });
    fixture.store.close_for_deletion().await?;
    small.store.close_for_deletion().await?;
    if let Some(path) = std::env::var_os("ANYWORK_TIMELINE_STORAGE_EVIDENCE") {
        std::fs::write(path, serde_json::to_vec_pretty(&evidence)?)
            .context("writing A19 storage evidence failed")?;
    }
    eprintln!(
        "A19 storage: 32/1024-member Main SQL matched; explicit bodies and rebuild verified; not UI p95"
    );
    Ok(())
}
