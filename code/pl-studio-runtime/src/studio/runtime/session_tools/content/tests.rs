use super::*;

use crate::runtime_test_support as support;

fn reason(error: &anyhow::Error) -> Option<&str> {
    error
        .downcast_ref::<pl_protocol::studio::StudioError>()
        .and_then(|error| error.reason())
}

#[tokio::test]
async fn stopping_interrupts_first_open_and_first_set_and_failed_join_keeps_original_owner()
-> Result<()> {
    use crate::studio::runtime::thread_observation::ThreadLiveFeed;
    use std::{sync::Arc, time::Duration};

    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "tool open cancellation")
            .await?;
        let session = &thread.id;
        let slot = env.runtime.thread_observations.observation_slot(session);
        let (_owner, progress) = tokio::sync::watch::channel(Default::default());
        let feed = Arc::new(ThreadLiveFeed::new(None, progress));
        slot.install(feed.clone());
        let waiting = feed.arm_first_open_wait();
        let owners = ReadOwners::default();
        let (opened, closed) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                owners.open(&env.runtime, session, demand(1).unwrap(), None, None),
                async {
                    waiting.await?;
                    owners.close_all().await
                }
            )
        })
        .await?;
        assert_eq!(reason(&opened.unwrap_err()), Some("staleReadScope"));
        closed?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        slot.retire(&feed);

        // After a real feed is acquired, cancellation must join both registered owners.
        let owners = ReadOwners::default();
        let (entered, _release) = owners.arm_test_boundary(TestBoundary::FirstSet, 0).await;
        let (opened, closed) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                owners.open(&env.runtime, session, demand(1).unwrap(), None, None),
                async {
                    entered.await?;
                    owners.close_all().await
                }
            )
        })
        .await?;
        assert_eq!(reason(&opened.unwrap_err()), Some("staleReadScope"));
        closed?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);

        // Fail the first receive via real epoch invalidation, and fail its first join once.
        let owners = ReadOwners::default();
        let (entered, release) = owners.arm_test_boundary(TestBoundary::FirstSet, 0).await;
        let (opened, id) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                owners.open(&env.runtime, session, demand(1).unwrap(), None, None),
                async {
                    let id = entered.await?;
                    owners.readers.lock().await[&id]
                        .close_fault
                        .store(true, Ordering::Release);
                    slot.install(feed.clone());
                    slot.retire(&feed);
                    let _ = release.send(());
                    Ok::<_, anyhow::Error>(id)
                }
            )
        })
        .await?;
        let id = id?;
        let error = opened.unwrap_err();
        assert_eq!(reason(&error), Some("conversationResyncRequired"));
        assert!(format!("{error:#}").contains("injected read-resource join failure"));
        assert_eq!(owners.readers.lock().await.len(), 1);
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
        assert_eq!(
            reason(&owners.get(&id, session, None).await.unwrap_err()),
            Some("staleReadScope")
        );
        owners.close(&id).await?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        owners.close_all().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn search_new_scope_failures_and_cancellation_release_capacity_and_retain_failed_join()
-> Result<()> {
    use crate::studio::runtime::thread_observation::ThreadLiveFeed;
    use std::time::Duration;

    let env = support::Environment::new(
        vec![support::prompt_step(
            "search-new-scope",
            0,
            support::text_reply("a public text body", "search-new-response"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(pl_protocol::ThreadWorkspaceMode::Local, "search-new-scope")
            .await?;
        let session = &thread.thread.id;
        support::completed_prompt(&env.runtime, session, "search-new-scope").await?;
        let owners = ReadOwners::default();
        let slot = env.runtime.thread_observations.observation_slot(session);
        let original = slot
            .capture()
            .0
            .source
            .context("fixture has no live owner")?;
        let (_owner, progress) = tokio::sync::watch::channel(Default::default());
        let replacement = Arc::new(ThreadLiveFeed::new(None, progress));
        let input = || {
            serde_json::from_value::<SearchInput>(
                serde_json::json!({"sessionId":session,"query":"absent search needle"}),
            )
        };
        // More than the entire quota: both cancellation and a real epoch read error must reclaim
        // scopes that have never been transferred in a successful ToolOutput.
        for attempt in 0..MAX_READ_SCOPES + 2 {
            let cancel = CancellationToken::new();
            let (entered, release) = owners.arm_test_boundary(TestBoundary::SearchRead, 0).await;
            let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
                tokio::join!(
                    search(&env.runtime, &owners, input().unwrap(), &cancel),
                    async {
                        let id = entered.await?;
                        assert_eq!(owners.readers.lock().await.len(), 1);
                        if attempt % 2 == 0 {
                            cancel.cancel();
                        } else {
                            slot.install(replacement.clone());
                            slot.retire(&replacement);
                            slot.install(original.clone());
                        }
                        let _ = release.send(());
                        Ok::<_, anyhow::Error>(id)
                    }
                )
            })
            .await?;
            control?;
            let error = found
                .err()
                .with_context(|| format!("search attempt {attempt} returned a cursor"))?;
            if attempt % 2 == 0 {
                assert!(format!("{error:#}").contains("search cancelled"));
            } else {
                assert_eq!(reason(&error), Some("conversationResyncRequired"));
            }
            assert!(owners.readers.lock().await.is_empty());
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        }
        // The original typed read error wins over cleanup failure. Its original resource and permit
        // stay in the same owner table, closing and retryable, rather than being silently dropped.
        let cancel = CancellationToken::new();
        let (entered, release) = owners.arm_test_boundary(TestBoundary::SearchRead, 0).await;
        let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                search(&env.runtime, &owners, input().unwrap(), &cancel),
                async {
                    let id = entered.await?;
                    owners.readers.lock().await[&id]
                        .close_fault
                        .store(true, Ordering::Release);
                    slot.install(replacement.clone());
                    slot.retire(&replacement);
                    slot.install(original.clone());
                    let _ = release.send(());
                    Ok::<_, anyhow::Error>(id)
                }
            )
        })
        .await?;
        let id = control?;
        let error = found
            .err()
            .context("failed read returned a search result")?;
        assert_eq!(reason(&error), Some("conversationResyncRequired"));
        assert!(format!("{error:#}").contains("injected read-resource join failure"));
        assert_eq!(owners.readers.lock().await.len(), 1);
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
        owners.close(&id).await?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        owners.close_all().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn search_borrows_input_until_cross_session_result_commit_and_retries_original_cleanup()
-> Result<()> {
    use crate::studio::runtime::thread_observation::ThreadLiveFeed;
    use std::time::Duration;

    // A real successful first search stops inside the text window budget, not at a forged cursor.
    let body = format!("{}search-final-needle", "x".repeat(WINDOW as usize * 36));
    let env = support::Environment::new(
        vec![support::prompt_step(
            "search-borrowed-scope",
            0,
            support::text_reply(&body, "search-borrowed-response"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let older = env.runtime.create_thread(&env.project.id, "older empty search session").await?;
        let thread = env.start(pl_protocol::ThreadWorkspaceMode::Local, "search-borrowed-scope").await?;
        let session = &thread.thread.id;
        support::completed_prompt(&env.runtime, session, "search-borrowed-scope").await?;
        // Validate the actual directory order used by the production cross-session scan.
        let directory = env.runtime.agent_facility.product_events.query_threads(
            &pl_protocol::studio::ThreadDirectoryQuery {
                workspace_id: Some(env.project.id.clone()), ..Default::default()
            }, None, 1,
        ).await?;
        let directory = directory.state.value().context("directory unavailable")?;
        assert_eq!(directory.threads[0].id, *session);
        assert!(directory.next_cursor.is_some());
        let input = |cursor: Option<&str>| serde_json::from_value::<SearchInput>(
            serde_json::json!({"workspaceId":env.project.id,"query":"search-final-needle","cursor":cursor})
        );
        let owners = ReadOwners::default();
        let first = search(&env.runtime, &owners, input(None)?, &CancellationToken::new()).await?;
        let page: serde_json::Value = serde_json::from_str(first.payload().content())?;
        assert_eq!(page["complete"], false);
        let token = page["cursor"].as_str().context("successful search continuation")?;
        let cursor: Cursor = decode(token)?;
        assert_eq!(cursor.session_id.as_deref(), Some(session.as_str()));
        assert!(!cursor.directory_done);
        let id = cursor.read_scope_id.as_deref().context("transferred scope")?;
        let pending = cursor.pending.as_ref().context("real pending body window")?;
        let reader = owners.get(id, session, Some(&cursor.fingerprint)).await?;
        // Cancelling a borrowed read must not revoke the successful input cursor.
        let cancel = CancellationToken::new();
        let (entered, _release) = owners.arm_test_boundary(TestBoundary::SearchRead, 0).await;
        let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                search(&env.runtime, &owners, input(Some(token)).unwrap(), &cancel),
                async { assert_eq!(entered.await?, id); cancel.cancel(); Ok::<_, anyhow::Error>(()) }
            )
        }).await?;
        control?;
        assert!(format!("{:#}", found.err().context("cancelled search succeeded")?).contains("search cancelled"));
        owners.get(id, session, Some(&cursor.fingerprint)).await?;
        reader.read_content(&pending.reference, ContentRange { offset: pending.offset, max_bytes: 16 }).await?;

        // Crossing to another session cannot open a 17th scope or evict the input qualification.
        let mut occupied = Vec::new();
        for _ in 1..MAX_READ_SCOPES {
            let (reader, _) = owners.open(&env.runtime, session, demand(1)?, None, None).await?;
            occupied.push(reader.subscription_id().to_owned());
        }
        let error = search(&env.runtime, &owners, input(Some(token))?, &CancellationToken::new())
            .await.err().context("cross-session scan exceeded the quota")?;
        assert!(matches!(error.downcast_ref::<pl_core::chat::ChatError>(), Some(pl_core::chat::ChatError::Overloaded(_))));
        assert_eq!(owners.readers.lock().await.len(), MAX_READ_SCOPES);
        assert_eq!(owners.permits.available_permits(), 0);
        owners.get(id, session, Some(&cursor.fingerprint)).await?;
        owners.get(&occupied[0], session, None).await?;
        close_scopes(&owners, &occupied).await?;

        // Both cancellation and an actual first-Set read failure in the next session leave the
        // input scope unretired and release only this call's untransferred new scope.
        for fail_read in [false, true] {
            let cancel = CancellationToken::new();
            let (entered, release) = owners.arm_test_boundary(TestBoundary::FirstSet, 0).await;
            let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
                tokio::join!(
                    search(&env.runtime, &owners, input(Some(token)).unwrap(), &cancel),
                    async {
                        let new_id = entered.await?;
                        assert_ne!(new_id, id);
                        assert_eq!(owners.readers.lock().await.len(), 2);
                        assert_eq!(owners.readers.lock().await[&new_id].reader.thread_id(), older.id);
                        if fail_read {
                            let slot = env.runtime.thread_observations.observation_slot(&older.id);
                            let (_owner, progress) = tokio::sync::watch::channel(Default::default());
                            let replacement = Arc::new(ThreadLiveFeed::new(None, progress));
                            slot.install(replacement.clone());
                            slot.retire(&replacement);
                        } else {
                            cancel.cancel();
                        }
                        let _ = release.send(());
                        Ok::<_, anyhow::Error>(())
                    }
                )
            }).await?;
            control?;
            let error = found.err().context("cross-session failure returned an output")?;
            if fail_read {
                assert_eq!(reason(&error), Some("conversationResyncRequired"));
            } else {
                assert!(format!("{error:#}").contains("search cancelled"));
            }
            assert_eq!(owners.readers.lock().await.len(), 1);
            assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
            owners.get(id, session, Some(&cursor.fingerprint)).await?;
            reader.read_content(&pending.reference, ContentRange { offset: pending.offset, max_bytes: 16 }).await?;
        }

        // Once a complete output is encoded, a failed irreversible retirement keeps the original
        // owner closing for retry; it must not pretend the old cursor remains usable.
        let cancel = CancellationToken::new();
        let (entered, release) = owners.arm_test_boundary(TestBoundary::SearchCommit, 0).await;
        let (found, control) = tokio::time::timeout(Duration::from_secs(3), async {
            tokio::join!(
                search(&env.runtime, &owners, input(Some(token)).unwrap(), &cancel),
                async {
                    assert_eq!(entered.await?, id);
                    owners.readers.lock().await[id].close_fault.store(true, Ordering::Release);
                    let _ = release.send(());
                    Ok::<_, anyhow::Error>(())
                }
            )
        }).await?;
        control?;
        let error = found.err().context("failed result commit returned an output")?;
        assert!(format!("{error:#}").contains("injected read-resource join failure"));
        assert_eq!(owners.readers.lock().await.len(), 1);
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES - 1);
        assert_eq!(reason(&owners.get(id, session, Some(&cursor.fingerprint)).await.unwrap_err()), Some("staleReadScope"));
        owners.close(id).await?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        drop(reader);
        // The ordinary successful continuation path finally retires all snippet-only resources.
        let first = search(&env.runtime, &owners, input(None)?, &CancellationToken::new()).await?;
        let page: serde_json::Value = serde_json::from_str(first.payload().content())?;
        let next = page["cursor"].as_str().context("second first-page cursor")?;
        let last = search(&env.runtime, &owners, input(Some(next))?, &CancellationToken::new()).await?;
        let page: serde_json::Value = serde_json::from_str(last.payload().content())?;
        assert_eq!(page["complete"], true);
        assert!(page["matches"].as_array().context("matches")?.iter().any(|entry| entry["sessionId"] == *session));
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(owners.permits.available_permits(), MAX_READ_SCOPES);
        owners.close_all().await?;
        Ok(())
    }.await;
    env.finish(result).await
}

#[tokio::test]
async fn tool_read_eof_keeps_qualification_until_explicit_or_tool_close_and_never_rebinds()
-> Result<()> {
    let body = format!("{}汉界关键字工具正文跨调用保留", "x".repeat(32767));
    let env = support::Environment::new(
        vec![support::prompt_step(
            "tool-read-scopes",
            0,
            support::text_reply(&body, "tool-read-response"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(pl_protocol::ThreadWorkspaceMode::Local, "tool-read-scopes")
            .await?;
        let session = &thread.thread.id;
        support::completed_prompt(&env.runtime, session, "tool-read-scopes").await?;
        let owners = ReadOwners::default();
        let other = ReadOwners::default();
        let input =
            serde_json::json!({"sessionId":session,"demand":{"maxItems":100,"maxBytes":131072}});
        let output = read(&env.runtime, &owners, serde_json::from_value(input)?).await?;
        let page: serde_json::Value = serde_json::from_str(output.payload().content())?;
        assert!(
            page["chat"]["before"].is_null(),
            "fixture is not at the real history EOF"
        );
        let scope = page["readScope"].as_str().context("read scope")?;
        let reader = owners.get(scope, session, None).await?;
        assert_eq!(
            reason(&other.get(scope, session, None).await.unwrap_err()),
            Some("staleReadScope")
        );
        assert_eq!(
            reason(&owners.get(scope, "another-thread", None).await.unwrap_err()),
            Some("staleReadScope")
        );
        let batch: ChatBatch = serde_json::from_value(page["chat"].clone())?;
        let item = batch
            .entries
            .iter()
            .find_map(|entry| {
                let pl_protocol::ChatEntry::Atom(message) = entry else {
                    return None;
                };
                let Some(pl_protocol::PayloadData::Inline { bytes }) = &message.payload else {
                    return None;
                };
                let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
                (value["type"] == "text")
                    .then(|| message.completion_item_id.clone())
                    .flatten()
            })
            .context("public text item")?;
        let reference = text_reference(&reader, &item)
            .await?
            .context("public body")?;
        let output = read(
            &env.runtime,
            &owners,
            serde_json::from_value(serde_json::json!({"sessionId":session,"readScope":scope,
            "reference":reference,"range":{"offset":0,"maxBytes":128}}))?,
        )
        .await?;
        let window: serde_json::Value = serde_json::from_str(output.payload().content())?;
        assert!(
            !window["window"]["bytes"]
                .as_array()
                .context("body bytes")?
                .is_empty()
        );
        assert!(
            owners.get(scope, session, None).await.is_ok(),
            "history EOF revoked body reads"
        );
        read(
            &env.runtime,
            &owners,
            serde_json::from_value(
                serde_json::json!({"sessionId":session,"readScope":scope,"closeReadScope":true}),
            )?,
        )
        .await?;
        assert_eq!(
            reason(&owners.get(scope, session, None).await.unwrap_err()),
            Some("staleReadScope")
        );
        let search_owners = ReadOwners::default();
        let output = search(
            &env.runtime,
            &search_owners,
            serde_json::from_value(serde_json::json!({"sessionId":session,"query":"汉界关键字"}))?,
            &CancellationToken::new(),
        )
        .await?;
        let search: serde_json::Value = serde_json::from_str(output.payload().content())?;
        assert!(
            search["matches"]
                .as_array()
                .context("search matches")?
                .iter()
                .any(|entry| entry["snippet"]
                    .as_str()
                    .is_some_and(|snippet| snippet.contains("汉界关键字")))
        );
        assert_eq!(search["complete"], true);
        assert!(
            search_owners.readers.lock().await.is_empty(),
            "snippet-only search EOF leaked its read qualification"
        );
        search_owners.close_all().await?;
        let mut ids = Vec::new();
        for _ in 0..MAX_READ_SCOPES {
            let (reader, _) = owners
                .open(&env.runtime, session, demand(1)?, None, None)
                .await?;
            ids.push(reader.subscription_id().to_owned());
        }
        let error = owners
            .open(&env.runtime, session, demand(1)?, None, None)
            .await
            .err()
            .context("17th scope was admitted")?;
        assert!(matches!(
            error.downcast_ref::<pl_core::chat::ChatError>(),
            Some(pl_core::chat::ChatError::Overloaded(_))
        ));
        assert!(
            owners.get(&ids[0], session, None).await.is_ok(),
            "capacity pressure evicted an original scope"
        );
        owners.close_all().await?;
        assert!(owners.readers.lock().await.is_empty());
        assert_eq!(
            reason(&owners.get(&ids[0], session, None).await.unwrap_err()),
            Some("staleReadScope")
        );
        assert!(
            owners
                .open(&env.runtime, session, demand(1)?, None, None)
                .await
                .is_err(),
            "closed tool reopened an execution-qualified read"
        );
        other.close_all().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
