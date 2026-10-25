mod posts;
mod samples;

use super::super::{Session, replies};
use super::{requests, route, send_text, write_json};
use crate::http;
use anyhow::{Context, Result, ensure};
use pl_provider_fixture::{
    bots_observe as model,
    feishu::{
        ChatType, DIRECT_CHAT_ID, EventBody, PostElement, ReceivedPost, SenderKind,
        TRUSTED_USER_OPEN_ID,
        media::{ResourceKind, ResourceSummary, SyntheticResource},
        text_event,
    },
};
use serde::Serialize;
use std::{collections::BTreeSet, path::PathBuf};

/// Joins one peer message/key to the newly published reliable attachment. The
/// identity is captured after that input completes, before admitting the next;
/// equal names and equal sizes cannot silently select a different original.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReceivedOriginal {
    message_id: String,
    resource: ResourceSummary,
    original: requests::Original,
}

pub(super) async fn run(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    route(session, &bot_id, "fixture-vision", "media-route-vision").await?;
    let samples = samples::all(&session.output)?;
    let mut received = Vec::new();
    for (index, sample) in samples.iter().enumerate() {
        let key = format!("file-d2-{}", sample.id);
        let resource = session
            .control()?
            .register_resource(SyntheticResource {
                message_id: sample.id.into(),
                file_key: key.clone(),
                kind: sample.kind,
                file_name: sample.name.into(),
                mime_type: sample.mime.into(),
                bytes: sample.bytes.clone(),
            })
            .await?;
        let body = match sample.kind {
            ResourceKind::Image => EventBody::Image { image_key: key },
            ResourceKind::File => EventBody::File {
                file_key: key,
                file_name: sample.name.into(),
            },
            ResourceKind::Audio => EventBody::Audio {
                file_key: key,
                duration: 100,
            },
            ResourceKind::Media => EventBody::Raw {
                message_type: "media".into(),
                content: serde_json::json!({"file_key":key,"file_name":sample.name,"duration":200})
                    .to_string(),
            },
        };
        let mut event = text_event(
            sample.id,
            DIRECT_CHAT_ID,
            ChatType::P2p,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            "",
            vec![],
        );
        event.body = body;
        session.control()?.send_event(event).await?;
        session.wait_inbound_completed(&bot_id, sample.id).await?;
        requests::wait_executions(session, index + 1).await?;
        let thread_id =
            replies::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
        record_original(
            session,
            &thread_id,
            sample.id,
            resource,
            sample.display_name(),
            &mut received,
        )
        .await?;
        evidence.push(format!(
            "inbound message={} kind={:?} receiveName={:?} displayName={:?} len={} sha256={}",
            sample.id,
            sample.kind,
            sample.name,
            sample.display_name(),
            sample.bytes.len(),
            model::sha256(&sample.bytes)
        ));
    }
    let thread_id = replies::wait_thread_binding(&session.home, &bot_id, DIRECT_CHAT_ID).await?;
    let before = requests::execution_requests(session);
    let small_native = requests::native_images(&before[0])?;
    ensure!(
        small_native.len() == 1 && small_native[0] == samples[0].bytes,
        "vision request did not contain the actual first image bytes"
    );
    let large_native = requests::native_images(&before[7])?;
    ensure!(
        large_native.len() == 2,
        "large-image request must retain two native image blocks"
    );
    let derivative = large_native
        .iter()
        .find(|bytes| **bytes != samples[0].bytes)
        .context("large image derived wire block missing")?;
    ensure!(
        *derivative != samples[7].bytes,
        "large image was not adapted to the explicit 64x64 native limit"
    );
    let derivative_path = session.output.join("large-image-request-derived.png");
    std::fs::write(&derivative_path, derivative)?;
    samples::dimensions(&derivative_path, 64, 64)?;
    evidence.push(format!(
        "large image raw len={} hash={}; request derivative len={} hash={} (ffprobe <=64x64)",
        samples[7].bytes.len(),
        model::sha256(&samples[7].bytes),
        derivative.len(),
        model::sha256(derivative)
    ));
    evidence.push("native image/audio receive wire has no display filename; each resource's nonempty host-chosen display name is captured from its reliable attachment DTO and must remain identical in the cold text-model file description".into());

    // content_v2 deliberately differs from legacy content. Only the original
    // Markdown and actual image block prove this input was interpreted correctly.
    let post_bytes = samples::image(
        &session.output,
        "post-image.png",
        "color=c=blue:s=20x12",
        false,
    )?;
    let resource = session
        .control()?
        .register_resource(SyntheticResource {
            message_id: "om_media_post".into(),
            file_key: "img-d2-post".into(),
            kind: ResourceKind::Image,
            file_name: "富文本 图片.png".into(),
            mime_type: "image/png".into(),
            bytes: post_bytes.clone(),
        })
        .await?;
    let mut post = text_event(
        "om_media_post",
        DIRECT_CHAT_ID,
        ChatType::P2p,
        SenderKind::User,
        TRUSTED_USER_OPEN_ID,
        "",
        vec![],
    );
    post.body = EventBody::Post(ReceivedPost {
        title: "post original Markdown".into(),
        content: vec![vec![PostElement::Text {
            text: "LEGACY-CONTENT-NOT-RENDER-PROOF".into(),
        }]],
        content_v2: Some(vec![
            vec![PostElement::Markdown {
                text: "# Original Markdown\n\n`wire` | table".into(),
            }],
            vec![PostElement::Image {
                image_key: "img-d2-post".into(),
            }],
        ]),
    });
    session.control()?.send_event(post).await?;
    session
        .wait_inbound_completed(&bot_id, "om_media_post")
        .await?;
    requests::wait_executions(session, 9).await?;
    record_original(
        session,
        &thread_id,
        "om_media_post",
        resource,
        None,
        &mut received,
    )
    .await?;
    let post_request = requests::execution_requests(session)
        .pop()
        .context("post request missing")?;
    ensure!(
        requests::native_images(&post_request)?
            .iter()
            .any(|bytes| bytes == &post_bytes),
        "post image was not actually delivered natively"
    );
    let post_text = requests::user_texts(&post_request)?.join("\n");
    ensure!(
        post_text.contains("# Original Markdown\n\n`wire` | table")
            && !post_text.contains("LEGACY-CONTENT-NOT-RENDER-PROOF"),
        "received post did not prefer original content_v2 Markdown"
    );
    posts::run(session, &bot_id, &thread_id, &mut received, evidence).await?;

    for sample in &samples[1..7] {
        let pair = received
            .iter()
            .find(|pair| pair.message_id == sample.id)
            .context("resource message lost its reliable identity")?;
        let modality = if sample.kind == ResourceKind::Media {
            pl_protocol::AttachmentModality::Video
        } else {
            pl_protocol::AttachmentModality::File
        };
        ensure!(
            pair.original.modality == modality,
            "valid-track video must be video; noext/unknown/audio/corrupt must be generic file: {} -> {:?}",
            sample.name,
            pair.original.modality
        );
    }
    write_json(session, "resource-attachment-identities.json", &received)?;

    route(session, &bot_id, "fixture-model", "media-route-text").await?;
    let restart = session.restart_studio_server().await?;
    ensure!(
        restart.stopped_sigints == 1
            && restart.stopped_graceful
            && restart.stopped_exit_code == Some(0),
        "media restart did not prove a single graceful stop: {restart}"
    );
    evidence.push(restart.to_string());
    session.wait_connected(&bot_id).await?;
    send_text(session, "om_media_cold", model::MEDIA_FOLLOWUP).await?;
    session
        .wait_inbound_completed(&bot_id, "om_media_cold")
        .await?;
    requests::wait_executions(session, 12).await?;
    let fallback = requests::execution_requests(session)
        .pop()
        .context("cold text request missing")?;
    ensure!(
        requests::native_images(&fallback)?.is_empty(),
        "text route still received native image blocks"
    );
    let descriptions = requests::files(&fallback)?;
    ensure!(
        descriptions.len() == received.len(),
        "cold fallback lost, merged or invented reliable resource descriptions"
    );
    let workspace = PathBuf::from(session.bot(&bot_id).await?.workspace_path);
    ensure!(
        workspace == session.home.join("v2/bots").join(&bot_id).join("workspace"),
        "bot execution escaped its managed local workspace"
    );
    let root_fact = format!("Current execution workspace root: {}.", workspace.display());
    ensure!(
        requests::user_texts(&fallback)?
            .iter()
            .any(|text| text.contains(&root_fact)),
        "actual model request did not identify the public bot execution root"
    );
    let uploads = requests::thread_uploads(&workspace, &thread_id)?;
    let mut distinct_paths = BTreeSet::new();
    for pair in &received {
        let matches = descriptions
            .iter()
            .filter(|file| requests::verify_file(&uploads, file, &pair.original).is_ok())
            .collect::<Vec<_>>();
        ensure!(
            matches.len() == 1,
            "resource message={} key={} attachment={} did not have exactly one correct display-name/byte-identity descriptor",
            pair.message_id,
            pair.resource.file_key,
            pair.original.attachment_id
        );
        let description = matches[0];
        ensure!(
            distinct_paths.insert(description.path.as_str()),
            "different resource originals share one execution path"
        );
        // Preserve the original integrity error if the file changes after selection.
        requests::verify_file(&uploads, description, &pair.original)?;
        evidence.push(format!("cold resource message={} key={} attachment={} displayName={:?} execution={} len={} sha256={}", pair.message_id, pair.resource.file_key, pair.original.attachment_id, description.filename, description.path, pair.original.byte_len, pair.original.sha256));
    }
    let same_name = received
        .iter()
        .filter(|pair| pair.original.filename.as_deref() == Some("报告 共享名.txt"))
        .collect::<Vec<_>>();
    ensure!(
        same_name.len() == 2
            && same_name[0].original.sha256 != same_name[1].original.sha256
            && same_name[0].original.byte_len == same_name[1].original.byte_len,
        "same-name fixture must prove two distinct equal-length originals, not only unique ASCII names"
    );
    write_json(session, "cold-file-descriptions.json", &descriptions)?;
    let facts = session.control()?.snapshot_report().await;
    ensure!(
        facts.resource_downloads.len() == received.len(),
        "each inbound original must be downloaded exactly once before restore"
    );
    for pair in &received {
        let downloads = facts
            .resource_downloads
            .iter()
            .filter(|download| {
                download.message_id == pair.message_id
                    && download.file_key == pair.resource.file_key
            })
            .collect::<Vec<_>>();
        ensure!(
            downloads.len() == 1 && downloads[0].prepared_bytes == pair.original.byte_len,
            "inbound message/key download identity or original byte length changed"
        );
    }
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        Ok(session
            .model
            .as_ref()
            .is_some_and(|model| model.live_status().remaining_optional))
    })
    .await?;
    let final_facts = session.control()?.snapshot_report().await;
    posts::verify_raw_acks(&final_facts.acks)?;
    write_json(session, "post-final-acks.json", &final_facts.acks)?;
    Ok("image/file/noext/unknown/audio/video/corrupt/post resources preserved per-message/key attachment identity, Chinese/spaced names and distinct same-name originals; native blocks and large-image derivatives were checked separately; cold text fallback preserved every display name and original execution-file hash without path collisions".into())
}

async fn record_original(
    session: &Session,
    thread_id: &str,
    message_id: &str,
    resource: ResourceSummary,
    display_name: Option<&str>,
    received: &mut Vec<ReceivedOriginal>,
) -> Result<()> {
    let originals = requests::originals(session, thread_id).await?;
    let new = originals
        .into_iter()
        .filter(|original| {
            !received
                .iter()
                .any(|pair| pair.original.attachment_id == original.attachment_id)
        })
        .collect::<Vec<_>>();
    ensure!(
        new.len() == 1,
        "resource message={message_id} key={} published {} new reliable identities, expected one",
        resource.file_key,
        new.len()
    );
    let original = new
        .into_iter()
        .next()
        .context("new reliable original missing")?;
    ensure!(
        original
            .filename
            .as_deref()
            .is_some_and(|name| !name.trim().is_empty()
                && display_name.is_none_or(|expected| name == expected))
            && original.byte_len == resource.byte_len
            && original.sha256 == resource.sha256,
        "resource message={message_id} key={} reliable display name/bytes differ: expected name={display_name:?} len={} sha256={}; got {original:?}",
        resource.file_key,
        resource.byte_len,
        resource.sha256
    );
    received.push(ReceivedOriginal {
        message_id: message_id.into(),
        resource,
        original,
    });
    Ok(())
}
