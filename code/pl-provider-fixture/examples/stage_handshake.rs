//! Explicit observation of the [`ReplyStage`] handshake and its lifecycle.
//!
//! It proves, without production code and without sleeping on a guess, that a
//! gated reply cannot complete before the observer releases it, and that every
//! lifecycle edge ends: the released path finishes, a release before the wait is
//! sticky, dropping the client does not leave a detached stream, and shutting the
//! fixture down while a stage is held joins its task.
//!
//! Run with `cargo run -p pl-provider-fixture --example stage_handshake`.
//! This is an environment probe: it never stands in for a production pass.

use anyhow::{Context, Result, bail, ensure};
use futures::StreamExt;
use pl_provider_fixture::{
    FixtureServer, Protocol, ReplyStage, Step, responses_reasoning_text_staged,
};
use std::time::Duration;

const PROMPT: &str = "stage handshake sample";
const BUDGET: Duration = Duration::from_secs(10);

#[tokio::main]
async fn main() -> Result<()> {
    let held = held_until_release().await?;
    let sticky = release_before_wait().await?;
    let dropped = client_drop_while_gated().await?;
    let shutdown = shutdown_while_gated().await?;
    let markdown = gui_markdown_sample().await?;
    let staged = staged_four_segments().await?;
    println!(
        "stage_handshake: held prefix_frames={} prefix_bytes={} suffix_bytes={}; \
         sticky_release_prefix_bytes={}; client_drop_completed={}; shutdown_completed={}; \
         gui_markdown_bytes={markdown}; staged_{}; verdict=all-lifecycle-edges",
        held.prefix_frames, held.prefix_bytes, held.suffix_bytes, sticky, dropped, shutdown, staged
    );
    Ok(())
}

struct HeldFacts {
    prefix_frames: usize,
    prefix_bytes: usize,
    suffix_bytes: usize,
}

fn script(stage: &ReplyStage) -> Vec<Step> {
    let (before, after) = responses_reasoning_text_staged(
        &["stage reasoning line"],
        "# staged head\n\n",
        "staged tail\n",
        "stage-observation",
        "fixture-model",
    );
    vec![Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT,
        0,
        stage.gated(before, after),
    )]
}

fn client() -> Result<reqwest::Client> {
    reqwest::Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(30))
        .build()
        .context("client")
}

fn request(client: &reqwest::Client, base: &str) -> reqwest::RequestBuilder {
    client
        .post(format!("{base}/responses"))
        .json(&serde_json::json!({
            "model": "fixture-model",
            "input": [{ "role": "user", "content": PROMPT }],
            "stream": true
        }))
}

fn request_named(client: &reqwest::Client, base: &str, prompt: &str) -> reqwest::RequestBuilder {
    client
        .post(format!("{base}/responses"))
        .json(&serde_json::json!({
            "model": "fixture-model",
            "input": [{ "role": "user", "content": prompt }],
            "stream": true
        }))
}

/// The prefix is written, the reply is held, and only the release completes it.
async fn held_until_release() -> Result<HeldFacts> {
    let stage = ReplyStage::new();
    let fixture = FixtureServer::start(script(&stage))
        .await
        .context("fixture start")?;
    let client = client()?;
    let mut request = Box::pin(request(&client, &fixture.base_url()).send());
    tokio::select! {
        () = stage.wait_reached() => {}
        response = request.as_mut() => {
            let response = response.context("request")?;
            bail!(
                "the gated reply completed before the stage was reached (status {})",
                response.status()
            );
        }
    }
    ensure!(!stage.is_released(), "release must still be pending");
    let response = request.await.context("request")?;
    ensure!(
        response.status().is_success(),
        "status {}",
        response.status()
    );
    let mut stream = response.bytes_stream();
    let mut prefix = String::new();
    let mut prefix_frames = 0usize;
    while let Ok(Some(chunk)) =
        tokio::time::timeout(Duration::from_millis(500), stream.next()).await
    {
        let text = String::from_utf8_lossy(&chunk.context("chunk")?).to_string();
        ensure!(
            !text.contains("staged tail")
                && !text.contains("[DONE]")
                && !text.contains("response.completed"),
            "the gated reply must not finish before the release"
        );
        prefix.push_str(&text);
        prefix_frames += 1;
    }
    ensure!(
        prefix_frames > 0 && prefix.contains("staged head"),
        "the prefix frames must carry the head text"
    );
    stage.release();
    let mut suffix = String::new();
    while let Some(chunk) = stream.next().await {
        suffix.push_str(&String::from_utf8_lossy(&chunk.context("chunk")?));
    }
    ensure!(
        suffix.contains("staged tail") && suffix.contains("[DONE]"),
        "the released reply must finish with the suffix and [DONE]"
    );
    let requests = fixture.finish().await.context("fixture finish")?;
    ensure!(
        requests.len() == 1 && requests[0].accepted,
        "one accepted request"
    );
    Ok(HeldFacts {
        prefix_frames,
        prefix_bytes: prefix.len(),
        suffix_bytes: suffix.len(),
    })
}

/// A release before any wait is sticky: the reply finishes immediately.
async fn release_before_wait() -> Result<usize> {
    let stage = ReplyStage::new();
    let fixture = FixtureServer::start(script(&stage))
        .await
        .context("fixture start")?;
    let client = client()?;
    stage.release();
    let response = tokio::time::timeout(BUDGET, request(&client, &fixture.base_url()).send())
        .await
        .context("an early release must not hold the reply")?
        .context("request")?;
    ensure!(
        response.status().is_success(),
        "status {}",
        response.status()
    );
    let body = tokio::time::timeout(BUDGET, response.text())
        .await
        .context("an early release must finish the body")?
        .context("body")?;
    ensure!(
        body.contains("staged head") && body.contains("staged tail") && body.contains("[DONE]"),
        "the sticky release must deliver both stages"
    );
    let requests = fixture.finish().await.context("fixture finish")?;
    ensure!(requests.len() == 1, "one request");
    Ok(body.len())
}

/// Dropping the client while the stage is held must not leave a detached stream.
async fn client_drop_while_gated() -> Result<&'static str> {
    let stage = ReplyStage::new();
    let fixture = FixtureServer::start(script(&stage))
        .await
        .context("fixture start")?;
    let client = client()?;
    let mut request = Box::pin(request(&client, &fixture.base_url()).send());
    tokio::select! {
        () = stage.wait_reached() => {}
        response = request.as_mut() => {
            let response = response.context("request")?;
            bail!("the reply completed before the stage (status {})", response.status());
        }
    }
    let response = request.await.context("request")?;
    let stream = response.bytes_stream();
    drop(stream);
    stage.release();
    // The fixture still joins its listener and serves no leftover task.
    fixture.shutdown().await.context("fixture shutdown")?;
    Ok("joined")
}

/// Shutting the fixture down while a stage is held must join the open stream.
async fn shutdown_while_gated() -> Result<&'static str> {
    let stage = ReplyStage::new();
    let fixture = FixtureServer::start(script(&stage))
        .await
        .context("fixture start")?;
    let client = client()?;
    let base = fixture.base_url();
    // Keep the client handle: the shutdown claim below is only honest when its
    // own in-flight request really ended, not merely when it was dropped.
    let client_task = tokio::spawn(async move {
        let _ = request(&client, &base).send().await;
    });
    tokio::time::timeout(BUDGET, stage.wait_reached())
        .await
        .context("the prefix never reached the stage signal")?;
    tokio::time::timeout(BUDGET, fixture.shutdown())
        .await
        .context("shutdown must join a gated reply")?
        .context("fixture shutdown")?;
    let client_end = tokio::time::timeout(BUDGET, client_task)
        .await
        .context("the gated client request never terminated after shutdown")?;
    ensure!(
        client_end.is_ok(),
        "the gated client request must end normally after shutdown, got {client_end:?}"
    );
    Ok("joined")
}

/// The fixed GUI Markdown sample really streams its whole answer through the
/// shared `gui_script()` steps (no production runtime involved).
async fn gui_markdown_sample() -> Result<usize> {
    use pl_provider_fixture::{GUI_MARKDOWN_PROMPT, GUI_PROMPT, gui_markdown_answer, gui_script};

    let fixture = FixtureServer::start(gui_script())
        .await
        .context("fixture start")?;
    let client = client()?;
    let mut answer = String::new();
    for prompt in [GUI_PROMPT, GUI_MARKDOWN_PROMPT] {
        let response = tokio::time::timeout(
            BUDGET,
            request_named(&client, &fixture.base_url(), prompt).send(),
        )
        .await
        .context("the GUI scripted reply did not start")?
        .context("request")?;
        ensure!(
            response.status().is_success(),
            "status {}",
            response.status()
        );
        let body = tokio::time::timeout(Duration::from_secs(40), response.text())
            .await
            .context("the GUI scripted reply did not finish")?
            .context("body")?;
        ensure!(body.contains("[DONE]"), "the GUI reply must complete");
        if prompt == GUI_MARKDOWN_PROMPT {
            answer = body
                .lines()
                .filter_map(|line| line.strip_prefix("data: "))
                .filter_map(|data| serde_json::from_str::<serde_json::Value>(data).ok())
                .filter(|event| {
                    event.get("type").and_then(|kind| kind.as_str())
                        == Some("response.output_text.delta")
                })
                .filter_map(|event| event.get("delta")?.as_str().map(str::to_owned))
                .collect();
        }
    }
    ensure!(
        answer == gui_markdown_answer(),
        "the streamed Markdown answer must equal the fixed sample exactly"
    );
    let requests = fixture.finish().await.context("fixture finish")?;
    ensure!(requests.len() == 2, "two scripted requests");
    Ok(answer.len())
}

/// Exercises the four ordered segments with three gates and prints, for every
/// segment, the event types that were really written before the gate was
/// released. This is the executable proof that the item completion and the
/// response completion are separate stages.
async fn staged_four_segments() -> Result<String> {
    use pl_provider_fixture::{ReplyStage, responses_reasoning_commentary_text_segments};

    const EXPECTED_LAST: [&str; 4] = [
        "response.output_text.delta",
        "response.output_text.delta",
        "response.output_item.done",
        "response.completed",
    ];
    let segments = responses_reasoning_commentary_text_segments(
        &["staged reasoning"],
        &["STAGED_COMMENTARY"],
        "# staged head\n\n",
        "staged tail\n",
        "staged-four",
        "fixture-model",
    );
    ensure!(
        segments.len() == 4,
        "the helper must produce four segments, got {}",
        segments.len()
    );
    // Frame counts per segment are known locally, so the probe attributes every
    // received event to its real segment instead of guessing by event type.
    let segment_events: Vec<usize> = segments.iter().map(Vec::len).collect();
    let gates: Vec<ReplyStage> = (0..3).map(|_| ReplyStage::new()).collect();
    let gate_refs: Vec<&ReplyStage> = gates.iter().collect();
    let reply = ReplyStage::staged(segments, &gate_refs);
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "staged four segments",
        0,
        reply,
    )])
    .await
    .context("fixture start")?;
    let client = client()?;
    let response = request_named(&client, &fixture.base_url(), "staged four segments")
        .send()
        .await
        .context("request")?;
    ensure!(
        response.status().is_success(),
        "status {}",
        response.status()
    );
    let mut stream = response.bytes_stream();
    let mut pending = String::new();
    let mut printed = Vec::new();
    for (index, gate) in gates.iter().enumerate() {
        tokio::time::timeout(BUDGET, gate.wait_reached())
            .await
            .with_context(|| format!("gate {index} was never reached"))?;
        ensure!(
            !gate.is_released(),
            "gate {index} must still be held when it is reached"
        );
        // Drain exactly the frames this segment owns, never more.
        let mut types = Vec::new();
        while types.len() < segment_events[index] {
            let chunk = tokio::time::timeout(BUDGET, stream.next())
                .await
                .with_context(|| format!("segment {index} frame timeout"))?
                .context("stream ended early")?
                .context("chunk")?;
            pending.push_str(&String::from_utf8_lossy(&chunk));
            while let Some(position) = pending.find('\n') {
                let line = pending[..position].to_owned();
                pending.drain(..=position);
                if let Some(data) = line.strip_prefix("data: ") {
                    if data == "[DONE]" {
                        continue;
                    }
                    if let Ok(event) = serde_json::from_str::<serde_json::Value>(data)
                        && let Some(kind) = event.get("type").and_then(|kind| kind.as_str())
                    {
                        types.push(kind.to_owned());
                    }
                }
                if types.len() == segment_events[index] {
                    break;
                }
            }
        }
        ensure!(
            types.len() == segment_events[index],
            "segment {index} delivered {} of {} frames",
            types.len(),
            segment_events[index]
        );
        ensure!(
            types.last().map(String::as_str) == Some(EXPECTED_LAST[index]),
            "segment {index} must end with {}, got {:?}",
            EXPECTED_LAST[index],
            types.last()
        );
        printed.push(format!(
            "segment#{index}=[{}] gate=reached-held",
            types.join(",")
        ));
        gate.release();
    }
    let mut tail = String::new();
    while let Some(chunk) = stream.next().await {
        tail.push_str(&String::from_utf8_lossy(&chunk.context("chunk")?));
    }
    ensure!(
        tail.contains("response.completed") && tail.contains("[DONE]"),
        "the response completion and [DONE] must follow the last gate"
    );
    let requests = fixture.finish().await.context("fixture finish")?;
    ensure!(requests.len() == 1, "one request");
    Ok(printed.join(" "))
}
