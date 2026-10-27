//! Paginated export: never aggregate complete Turn histories or content bodies in memory.
use super::super::evidence::{Evidence, MAX_ITEMS, Manifest, ThreadExport};
use anyhow::{Context, Result};
use pl_protocol::{TimelineDetailQuery, TimelinePageQuery};
use pl_studio_runtime::StudioRuntime;
use std::io::Write;

pub(super) async fn thread(
    runtime: &StudioRuntime,
    evidence: &Evidence,
    id: &str,
    index: usize,
    manifest: &mut Manifest,
    budget: &super::super::Boundary,
) -> Result<()> {
    budget.check()?;
    let prefix = format!("threads/{index:03}");
    let export_index = manifest.thread_exports.len();
    manifest.thread_exports.push(ThreadExport {
        thread_id: id.into(),
        directory: prefix.clone(),
        ..ThreadExport::default()
    });
    let snapshot = budget.read(runtime.thread_snapshot(id)).await?;
    manifest.thread_exports[export_index].snapshot_revision = Some(snapshot.revision);
    manifest.thread_exports[export_index].storage = snapshot.storage.clone();
    evidence.json(&format!("{prefix}/snapshot.json"), id, &snapshot)?;
    let mut cursor = None;
    let mut page_index = 0;
    loop {
        let page = budget
            .read(runtime.list_thread_turns(id, cursor.as_deref(), 200))
            .await
            .with_context(|| format!("read Turn page {page_index} for {id}"))?;
        // Runtime enforces its independent <=200-row/2MiB decoded page budget.
        if page_index == 0 {
            manifest.thread_exports[export_index].latest_turn =
                page.turns.first().map(|history| history.turn.clone());
        }
        evidence.json(&format!("{prefix}/turns/{page_index:05}.json"), id, &page)?;
        manifest.thread_exports[export_index].turn_pages += 1;
        let next = page.next_cursor;
        anyhow::ensure!(
            next.is_none() || next != cursor,
            "Turn cursor did not advance"
        );
        cursor = next;
        page_index += 1;
        if cursor.is_none() {
            break;
        }
        evidence.check_disk_budget()?;
    }
    let mut before = None;
    page_index = 0;
    loop {
        let page = budget
            .read(runtime.timeline_page(
                id,
                &TimelinePageQuery {
                    before: before.clone(),
                    limit: Some(100),
                },
            ))
            .await
            .with_context(|| format!("read timeline page {page_index} for {id}"))?;
        evidence.check_limit(
            manifest.timeline_items + page.items.len() <= MAX_ITEMS,
            "timeline item budget exceeded (10000)",
        )?;
        evidence.json(
            &format!("{prefix}/timeline/{page_index:05}.json"),
            id,
            &page,
        )?;
        manifest.thread_exports[export_index].timeline_pages += 1;
        #[derive(serde::Serialize)]
        #[serde(rename_all = "camelCase")]
        struct NonterminalTool<'a> {
            item_id: &'a str,
            call_id: &'a str,
            task_id: Option<&'a str>,
            state: &'a pl_protocol::ThreadToolState,
        }
        let nonterminal: Vec<_> = page
            .items
            .iter()
            .filter_map(|item| {
                let tool = item.preview.tool()?;
                (!tool.state().is_terminal()).then(|| NonterminalTool {
                    item_id: &item.preview.id,
                    call_id: tool.invocation().tool_call_id(),
                    task_id: tool.invocation().task_id(),
                    state: tool.state(),
                })
            })
            .collect();
        if !nonterminal.is_empty() {
            let path = format!("{prefix}/timeline/{page_index:05}.nonterminal.json");
            evidence.json(&path, id, &nonterminal)?;
            manifest.thread_exports[export_index].nonterminal_tools += nonterminal.len();
            manifest.unfinished.push(format!(
                "{id}: {} exported tools have nonterminal states; see {path}",
                nonterminal.len()
            ));
        }
        for (item_index, item) in page.items.iter().enumerate() {
            budget.check()?;
            manifest.timeline_items += 1;
            for (field_index, detail) in item.details.iter().enumerate() {
                let relative = format!(
                    "{prefix}/details/{page_index:05}-{item_index:03}-{field_index:03}.txt"
                );
                let mut file = evidence.create(&relative, &item.preview.id)?;
                let result: Result<()> = async {
                    let mut continuation = None;
                    let mut bytes = 0u64;
                    loop {
                        let chunk = budget
                            .read(runtime.read_timeline_detail(
                                id,
                                &item.preview.id,
                                &TimelineDetailQuery {
                                    field: detail.field,
                                    revision: detail.revision,
                                    continuation: continuation.clone(),
                                    max_bytes: Some(64 * 1024),
                                },
                            ))
                            .await?;
                        anyhow::ensure!(
                            chunk.thread_id == id
                                && chunk.item_id == item.preview.id
                                && chunk.field == detail.field
                                && chunk.revision == detail.revision
                                && chunk.total_bytes == detail.total_bytes,
                            "detail identity/revision/length changed; refusing to splice versions"
                        );
                        file.write_all(chunk.text.as_bytes())?;
                        budget.check()?;
                        bytes = bytes
                            .checked_add(chunk.text.len() as u64)
                            .context("detail byte overflow")?;
                        anyhow::ensure!(
                            bytes <= detail.total_bytes,
                            "detail exceeds declared length"
                        );
                        anyhow::ensure!(
                            chunk.continuation.is_none()
                                || (!chunk.text.is_empty() && chunk.continuation != continuation),
                            "detail cursor did not advance"
                        );
                        continuation = chunk.continuation;
                        if continuation.is_none() {
                            break;
                        }
                    }
                    anyhow::ensure!(
                        bytes == detail.total_bytes,
                        "detail ended before declared length"
                    );
                    Ok(())
                }
                .await;
                let finish = file.finish(result.is_ok());
                match (result, finish) {
                    (Err(error), Err(finish)) => {
                        return Err(
                            error.context(format!("also failed finishing {relative}: {finish:#}"))
                        );
                    }
                    (Err(error), _) | (_, Err(error)) => return Err(error.context(relative)),
                    _ => (),
                }
                // Detail identity maps the opaque item/field/revision to an indexed file, never
                // puts an opaque ID into a filesystem path. Page metadata retains saved/lifecycle.
                #[derive(serde::Serialize)]
                #[serde(rename_all = "camelCase")]
                struct DetailMapping<'a> {
                    thread_id: &'a str,
                    item_id: &'a str,
                    detail: &'a pl_protocol::TimelineDetailRef,
                    file: &'a str,
                }
                evidence.json(
                    &format!("{relative}.ref.json"),
                    &item.preview.id,
                    &DetailMapping {
                        thread_id: id,
                        item_id: &item.preview.id,
                        detail,
                        file: &relative,
                    },
                )?;
                manifest.thread_exports[export_index].detail_fields += 1;
            }
        }
        if !page.has_older {
            break;
        }
        let next = page
            .before
            .context("hasOlder without an opaque before cursor")?;
        anyhow::ensure!(
            before.as_ref() != Some(&next),
            "timeline cursor did not advance"
        );
        before = Some(next);
        page_index += 1;
        evidence.check_disk_budget()?;
    }
    manifest.thread_exports[export_index].complete = true;
    Ok(())
}
