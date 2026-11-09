//! Also compiled by an isolated downstream manifest: no host/core/model dependencies.
use pl_agent_tool::{Tool, typed::prepare_json};
use std::{
    collections::BTreeMap,
    io,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Default)]
struct WebService(Arc<Mutex<Vec<pl_tool_search::tools::web_search::Request>>>);
impl pl_tool_search::tools::web_search::SearchService for WebService {
    type Error = io::Error;
    async fn search(
        &self,
        request: pl_tool_search::tools::web_search::Request,
    ) -> Result<pl_tool_search::tools::web_search::Response, io::Error> {
        self.0.lock().unwrap().push(request);
        Ok(pl_tool_search::tools::web_search::Response {
            output: "界".repeat(6_000),
            encrypted_output: Some("opaque-provider-state".into()),
            results: None,
        })
    }
}
#[tokio::test]
async fn web_search_executes_commands_and_bounds_only_the_preview() {
    let service = WebService::default();
    let requests = service.0.clone();
    let tool = prepare_json()
        .unwrap()
        .attach(pl_tool_search::tools::web_search::WebSearch::new(service));
    let output = tool.execute(r#"{"search_query":[{"q":"rust","domains":["rust-lang.org"]}],"time":[{"utc_offset":"+08:00"}]}"#.into(),
        pl_tool_search::tools::web_search::Context { request_id: "turn:call".into(), input: Some(vec![serde_json::json!({"role":"user","content":"question"})]), cancellation: CancellationToken::new() }).await.unwrap();
    assert_eq!(output.response.output.len(), 18_000);
    assert!(output.preview.contains("preview omitted"));
    assert_eq!(
        output.response.encrypted_output.as_deref(),
        Some("opaque-provider-state")
    );
    let request = requests.lock().unwrap();
    assert_eq!(request[0].id, "turn:call");
    assert_eq!(
        request[0].commands.search_query.as_ref().unwrap()[0].q,
        "rust"
    );
    assert_eq!(
        request[0].commands.time.as_ref().unwrap()[0].utc_offset,
        "+08:00"
    );
}

#[derive(Clone, Default)]
struct DeepService(Arc<Mutex<Vec<String>>>);
impl pl_tool_search::support::SearchService for DeepService {
    type Error = io::Error;
    fn source_limit(&self) -> usize {
        2
    }
    async fn search(
        &self,
        query: String,
        _: CancellationToken,
    ) -> Result<
        pl_tool_search::support::SearchResponse,
        pl_tool_search::support::ServiceFailure<io::Error, pl_tool_search::support::SearchResponse>,
    > {
        self.0.lock().unwrap().push(query.clone());
        if query == "first" {
            tokio::task::yield_now().await;
        }
        let response = pl_tool_search::support::SearchResponse {
            sources: vec![
                pl_tool_search::support::SearchSource {
                    url: format!("https://example.org/{query}"),
                    title: Some(query.clone()),
                    snippet: Some("snippet".into()),
                    published_at: Some("2026-01-01".into()),
                },
                pl_tool_search::support::SearchSource {
                    url: "https://common.test/".into(),
                    title: None,
                    snippet: None,
                    published_at: None,
                },
            ],
            raw_response: serde_json::json!({"query":query}),
        };
        if query == "failure" {
            return Err(pl_tool_search::support::ServiceFailure {
                source: io::Error::other("provider rejected"),
                observed: Some(response),
                cancelled: false,
            });
        }
        Ok(response)
    }
}
#[tokio::test]
async fn deepseek_search_deduplicates_fanout_and_preserves_query_order() {
    let service = DeepService::default();
    let calls = service.0.clone();
    let tool = prepare_json()
        .unwrap()
        .attach(pl_tool_search::tools::deepseek_web_search::DeepSeekWebSearch::new(service));
    let output = tool
        .execute(
            r#"{"queries":["first","second","first"]}"#.into(),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(calls.lock().unwrap().len(), 2);
    assert_eq!(output.results.queries, ["first", "second"]);
    assert_eq!(output.results.responses[0].raw_response["query"], "first");
    assert!(output.preview.find("[first]").unwrap() < output.preview.find("[second]").unwrap());
    assert!(output.preview.contains("Showing the first 2 sources"));
    let error = tool
        .execute(
            r#"{"queries":["failure"]}"#.into(),
            CancellationToken::new(),
        )
        .await
        .unwrap_err();
    let pl_agent_tool::typed::InvocationError::Tool(
        pl_tool_search::tools::deepseek_web_search::SearchError::Service { source, output },
    ) = error
    else {
        panic!("lost provider failure")
    };
    assert_eq!(source.to_string(), "provider rejected");
    assert_eq!(
        output.unwrap().results.responses[0].raw_response["query"],
        "failure"
    );
    let count = calls.lock().unwrap().len();
    assert!(
        tool.execute(r#"{"queries":[" "]}"#.into(), CancellationToken::new())
            .await
            .is_err()
    );
    assert_eq!(calls.lock().unwrap().len(), count);
}

#[derive(Clone, Default)]
struct FetchService(Arc<AtomicUsize>);
impl pl_tool_search::support::FetchService for FetchService {
    type Error = io::Error;
    async fn fetch(
        &self,
        url: String,
        _: CancellationToken,
    ) -> Result<
        pl_tool_search::support::FetchResponse,
        pl_tool_search::support::ServiceFailure<io::Error, pl_tool_search::support::FetchResponse>,
    > {
        self.0.fetch_add(1, Ordering::SeqCst);
        let response = pl_tool_search::support::FetchResponse {
            status: 200,
            title: None,
            content: "内容".repeat(4_000),
            raw_response: serde_json::json!({"url":url}),
        };
        if url.ends_with("/failure") {
            Err(pl_tool_search::support::ServiceFailure {
                source: io::Error::other("malformed response"),
                observed: Some(response),
                cancelled: false,
            })
        } else {
            Ok(response)
        }
    }
}
#[tokio::test]
async fn deepseek_fetch_retains_full_content_and_failure_observation() {
    let service = FetchService::default();
    let calls = service.0.clone();
    let tool = prepare_json()
        .unwrap()
        .attach(pl_tool_search::tools::deepseek_web_fetch::DeepSeekWebFetch::new(service));
    let output = tool
        .execute(
            r#"{"url":"https://example.org/"}"#.into(),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(output.response.content.len(), 24_000);
    assert!(output.preview.contains("Content truncated"));
    assert!(
        tool.execute(
            r#"{"url":"file:///etc/passwd"}"#.into(),
            CancellationToken::new()
        )
        .await
        .is_err()
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let error = tool
        .execute(
            r#"{"url":"https://example.org/failure"}"#.into(),
            CancellationToken::new(),
        )
        .await
        .unwrap_err();
    let pl_agent_tool::typed::InvocationError::Tool(
        pl_tool_search::tools::deepseek_web_fetch::FetchError::Service { output, .. },
    ) = error
    else {
        panic!("lost response")
    };
    assert_eq!(output.unwrap().response.content.len(), 24_000);
}

#[tokio::test]
async fn skills_list_selects_visible_names_without_loading_bodies() {
    let listing = |name: &str, description: &str, visible| pl_tool_skill::support::Listing {
        name: name.into(),
        description: description.into(),
        category: Some("rust".into()),
        model_invocable: visible,
    };
    let tool = prepare_json()
        .unwrap()
        .attach(pl_tool_skill::tools::skills_list::SkillsList::new(vec![
            listing("rust-api", "public interfaces", true),
            listing("rust-tests", "tests", true),
            listing("hidden", "rust-api", false),
        ]));
    let output = tool
        .execute(r#"{"query":"rust-api","limit":1}"#.into(), ())
        .await
        .unwrap();
    assert_eq!(output.count, 1);
    assert_eq!(output.skills[0].name, "rust-api");
    let output = tool.execute("{}".into(), ()).await.unwrap();
    assert_eq!(
        output
            .skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>(),
        ["rust-api", "rust-tests"]
    );
    assert!(
        tool.execute(r#"{"query":"rust","limit":0}"#.into(), ())
            .await
            .is_err()
    );
}

#[derive(Clone, Default)]
struct SkillReader(Arc<Mutex<Vec<String>>>);
impl pl_tool_skill::support::SkillReader for SkillReader {
    type Error = io::Error;
    type Summary = String;
    type ResourceBase = String;
    async fn load(
        &self,
        name: &str,
        _: CancellationToken,
    ) -> Result<pl_tool_skill::support::Document<String, String>, io::Error> {
        Ok(pl_tool_skill::support::Document {
            name: name.into(),
            summary: name.into(),
            resource_base: "provider-owned".into(),
            content: "main document".into(),
        })
    }
    async fn read_resource(
        &self,
        _: &str,
        path: &str,
        _: CancellationToken,
    ) -> Result<String, io::Error> {
        self.0.lock().unwrap().push(path.into());
        Ok("reference body".into())
    }
    async fn record_view(&self, name: &str, _: CancellationToken) -> Result<(), io::Error> {
        if name == "usage-failure" {
            return Err(io::Error::other("usage unavailable"));
        }
        self.0.lock().unwrap().push("record-view".into());
        Ok(())
    }
}
#[tokio::test]
async fn skill_view_owns_resource_selection_and_retains_reads_on_usage_failure() {
    let reader = SkillReader::default();
    let events = reader.0.clone();
    let tool = prepare_json()
        .unwrap()
        .attach(pl_tool_skill::tools::skill_view::SkillView::new(reader));
    let output = tool
        .execute(
            r#"{"name":"example","filePath":"references/detail.md"}"#.into(),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(output.viewed.content, "reference body");
    assert_eq!(
        events.lock().unwrap().as_slice(),
        ["references/detail.md", "record-view"]
    );
    assert!(
        tool.execute(
            r#"{"name":"example","filePath":"../private"}"#.into(),
            CancellationToken::new()
        )
        .await
        .is_err()
    );
    let error = tool
        .execute(
            r#"{"name":"usage-failure"}"#.into(),
            CancellationToken::new(),
        )
        .await
        .unwrap_err();
    let pl_agent_tool::typed::InvocationError::Tool(
        pl_tool_skill::tools::skill_view::ViewError::Record { output, .. },
    ) = error
    else {
        panic!("lost successful read")
    };
    assert_eq!(output.viewed.content, "main document");
}

#[derive(Clone, Default)]
struct SkillFiles(Arc<Mutex<BTreeMap<PathBuf, String>>>, bool);
impl pl_tool_skill::tools::skill_manage::ProjectFiles for SkillFiles {
    type Error = io::Error;
    async fn exists(&self, path: &Path) -> Result<bool, io::Error> {
        Ok(self.0.lock().unwrap().contains_key(path))
    }
    async fn read(&self, path: &Path) -> Result<String, io::Error> {
        self.0
            .lock()
            .unwrap()
            .get(path)
            .cloned()
            .ok_or_else(|| io::Error::other("missing file"))
    }
    async fn write(
        &self,
        path: &Path,
        text: String,
        mode: pl_tool_skill::tools::skill_manage::WriteMode,
    ) -> Result<(), io::Error> {
        let mut files = self.0.lock().unwrap();
        match (mode, files.contains_key(path)) {
            (pl_tool_skill::tools::skill_manage::WriteMode::Existing, false)
            | (pl_tool_skill::tools::skill_manage::WriteMode::Create, true) => {
                return Err(io::Error::other("write mode rejected"));
            }
            _ => {}
        }
        files.insert(path.into(), text);
        Ok(())
    }
    async fn remove_file(&self, path: &Path) -> Result<(), io::Error> {
        self.0.lock().unwrap().remove(path);
        Ok(())
    }
    async fn remove_tree(&self, path: &Path) -> Result<(), io::Error> {
        self.0
            .lock()
            .unwrap()
            .retain(|file, _| !file.starts_with(path));
        Ok(())
    }
    async fn record_created(&self, _: &Path) -> Result<(), io::Error> {
        if self.1 {
            return Err(io::Error::other("usage write failed"));
        }
        Ok(())
    }
    async fn record_patch(&self, _: &Path) -> Result<(), io::Error> {
        if self.1 {
            return Err(io::Error::other("usage write failed"));
        }
        Ok(())
    }
}
#[tokio::test]
async fn skill_manage_retains_applied_mutation_when_usage_recording_fails() {
    let files = SkillFiles(Arc::default(), true);
    let state = files.0.clone();
    let tool =
        prepare_json()
            .unwrap()
            .attach(pl_tool_skill::tools::skill_manage::SkillManage::new(
                files,
                PathBuf::from("/project/skills"),
                vec![],
            ));
    let document = "---\nname: example\ndescription: useful workflow\n---\nbody";
    let error = tool
        .execute(
            serde_json::json!({"action":"create","name":"example","content":document}).to_string(),
            (),
        )
        .await
        .unwrap_err();
    let pl_agent_tool::typed::InvocationError::Tool(
        pl_tool_skill::tools::skill_manage::ManageError::Record { source, output },
    ) = error
    else {
        panic!("lost mutation observation")
    };
    assert_eq!(source.to_string(), "usage write failed");
    assert_eq!(output.action, "create");
    assert_eq!(
        state.lock().unwrap()[&PathBuf::from("/project/skills/example/SKILL.md")],
        document
    );
}
#[tokio::test]
async fn skill_manage_performs_all_mutations_and_rejects_ambiguous_patch_and_readonly_source() {
    let files = SkillFiles::default();
    let state = files.0.clone();
    let root = PathBuf::from("/project/skills");
    let document = "---\nname: example\ndescription: useful workflow\n---\nold old";
    let tool =
        prepare_json()
            .unwrap()
            .attach(pl_tool_skill::tools::skill_manage::SkillManage::new(
                files.clone(),
                root.clone(),
                vec![],
            ));
    let output = tool
        .execute(
            serde_json::json!({"action":"create","name":"example","content":document}).to_string(),
            (),
        )
        .await
        .unwrap();
    assert_eq!(output.path, Some(root.join("example")));
    assert_eq!(
        state.lock().unwrap()[&root.join("example/SKILL.md")],
        document
    );
    let candidates = vec![
        pl_tool_skill::tools::skill_manage::Candidate {
            name: "example".into(),
            path: root.join("example"),
            read_only_source: None,
        },
        pl_tool_skill::tools::skill_manage::Candidate {
            name: "system".into(),
            path: PathBuf::from("/readonly/system"),
            read_only_source: Some("system".into()),
        },
    ];
    let tool =
        prepare_json()
            .unwrap()
            .attach(pl_tool_skill::tools::skill_manage::SkillManage::new(
                files,
                root.clone(),
                candidates,
            ));
    assert!(
        tool.execute(
            r#"{"action":"patch","name":"example","oldString":"old","newString":"new"}"#.into(),
            ()
        )
        .await
        .is_err()
    );
    let output = tool.execute(r#"{"action":"patch","name":"example","oldString":"old","newString":"new","replaceMode":"all"}"#.into(), ()).await.unwrap();
    assert_eq!(output.replacements, Some(2));
    assert!(state.lock().unwrap()[&root.join("example/SKILL.md")].ends_with("new new"));
    tool.execute(
        serde_json::json!({"action":"edit","name":"example","content":document}).to_string(),
        (),
    )
    .await
    .unwrap();
    tool.execute(r#"{"action":"writeFile","name":"example","filePath":"references/a.md","fileContent":"details"}"#.into(), ()).await.unwrap();
    assert_eq!(
        state.lock().unwrap()[&root.join("example/references/a.md")],
        "details"
    );
    tool.execute(
        r#"{"action":"removeFile","name":"example","filePath":"references/a.md"}"#.into(),
        (),
    )
    .await
    .unwrap();
    assert!(
        !state
            .lock()
            .unwrap()
            .contains_key(&root.join("example/references/a.md"))
    );
    assert!(
        tool.execute(r#"{"action":"delete","name":"system"}"#.into(), ())
            .await
            .is_err()
    );
    tool.execute(r#"{"action":"delete","name":"example"}"#.into(), ())
        .await
        .unwrap();
    assert!(state.lock().unwrap().is_empty());
}

#[derive(Debug, Default)]
struct Bots(AtomicUsize);
impl pl_tool_bots::support::BotSessionHost for Bots {
    type Error = io::Error;
    type Connection = String;
    type Conversation = String;
    type Message = serde_json::Value;
    type Segment = String;
    type Receipt = String;
    async fn list_bots(
        &self,
        scope: &str,
    ) -> Result<Vec<pl_tool_bots::support::Bot<String>>, io::Error> {
        assert_eq!(scope, "project");
        Ok(vec![pl_tool_bots::support::Bot {
            id: "bot".into(),
            name: "helper".into(),
            connection: "connected".into(),
            tools_enabled: true,
        }])
    }
    async fn list_conversations(
        &self,
        scope: &str,
        bot_id: String,
        cursor: Option<String>,
        limit: Option<u32>,
    ) -> Result<pl_tool_bots::support::Page<String>, io::Error> {
        assert_eq!(
            (scope, bot_id.as_str(), cursor.as_deref(), limit),
            ("project", "bot", Some("cursor"), Some(7))
        );
        Ok(pl_tool_bots::support::Page {
            items: vec!["chat".into()],
            next_cursor: Some("next".into()),
        })
    }
    async fn read_messages(
        &self,
        scope: &str,
        request: pl_tool_bots::support::ReadMessages,
    ) -> Result<pl_tool_bots::support::Page<serde_json::Value>, io::Error> {
        assert_eq!(
            (
                scope,
                request.bot_id.as_str(),
                request.chat_id.as_str(),
                request.start_time,
                request.end_time
            ),
            ("project", "bot", "chat", Some(1), Some(2))
        );
        Ok(pl_tool_bots::support::Page {
            items: vec![
                serde_json::json!({"kind":"unsupported","msgType":"image","notice":"unsupported"}),
            ],
            next_cursor: None,
        })
    }
    async fn send_message(
        &self,
        scope: &str,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
    ) -> Result<pl_tool_bots::support::Sent<String, String>, io::Error> {
        assert_eq!(
            (
                scope,
                operation_id.as_str(),
                bot_id.as_str(),
                chat_id.as_str(),
                text.as_str()
            ),
            ("project", "frozen-call", "bot", "chat", "hello")
        );
        self.0.fetch_add(1, Ordering::SeqCst);
        Ok(pl_tool_bots::support::Sent {
            status: pl_tool_bots::support::SendStatus::Unknown,
            segments: vec!["observed".into()],
            receipt: "receipt".into(),
        })
    }
}
#[tokio::test]
async fn list_bots_projects_authorized_facts() {
    let tool = prepare_json()
        .unwrap()
        .attach(pl_tool_bots::tools::list_bots::ListBots::new(
            Arc::new(Bots::default()),
            "project".into(),
        ));
    let result = tool.execute("{}".into(), ()).await.unwrap();
    assert_eq!(
        serde_json::to_value(result).unwrap(),
        serde_json::json!([{"id":"bot","name":"helper","connection":"connected","toolsEnabled":true}])
    );
}
#[tokio::test]
async fn list_bot_conversations_preserves_cursor_and_scope() {
    let tool = prepare_json().unwrap().attach(
        pl_tool_bots::tools::list_bot_conversations::ListBotConversations::new(
            Arc::new(Bots::default()),
            "project".into(),
        ),
    );
    let result = tool
        .execute(r#"{"botId":"bot","cursor":"cursor","limit":7}"#.into(), ())
        .await
        .unwrap();
    assert_eq!(result.bot_id, "bot");
    assert_eq!(result.conversations, ["chat"]);
    assert_eq!(result.next_cursor.as_deref(), Some("next"));
}
#[tokio::test]
async fn read_bot_messages_preserves_time_filter_and_unsupported_media() {
    let tool = prepare_json().unwrap().attach(
        pl_tool_bots::tools::read_bot_messages::ReadBotMessages::new(
            Arc::new(Bots::default()),
            "project".into(),
        ),
    );
    let result = tool
        .execute(
            r#"{"botId":"bot","chatId":"chat","startTime":1,"endTime":2}"#.into(),
            (),
        )
        .await
        .unwrap();
    assert_eq!(result.messages[0]["kind"], "unsupported");
    assert_eq!(result.chat_id, "chat");
}
#[tokio::test]
async fn send_bot_message_uses_frozen_operation_and_does_not_retry_unknown_status() {
    let host = Arc::new(Bots::default());
    let tool =
        prepare_json()
            .unwrap()
            .attach(pl_tool_bots::tools::send_bot_message::SendBotMessage::new(
                host.clone(),
                "project".into(),
            ));
    let result = tool
        .execute(
            r#"{"botId":"bot","chatId":"chat","text":"hello"}"#.into(),
            "frozen-call".into(),
        )
        .await
        .unwrap();
    assert_eq!(result.operation_id, "frozen-call");
    assert!(matches!(
        result.status,
        pl_tool_bots::support::SendStatus::Unknown
    ));
    assert_eq!(result.segments, ["observed"]);
    assert_eq!(host.0.load(Ordering::SeqCst), 1);
}
