use std::sync::Arc;

use clap::{Parser, Subcommand, ValueEnum};
use pl_model_gemini::{adapter::ADAPTER, bundled_definition, endpoint};
use pl_model_runtime::runtime::{CancellationToken, ModelInvocationContext, ModelRuntime};
use pl_model_wire::completion::{
    AttachmentInput, AttachmentModality, AttachmentSource, CompletionRequest, ContentPart, Message,
    MessageContent, MessageRole, ModelContextItem, ReasoningConfig, SystemPrompt, ToolResultRecord,
    ToolSpec, completion_response_message_text,
};
use pl_model_wire::model::ModelDefinition;
use serde_json::json;

#[derive(Clone, Copy, ValueEnum)]
enum TargetFlavor {
    Vertex,
    GeminiApi,
}

#[derive(Parser)]
struct Args {
    #[arg(long, value_enum, default_value_t = TargetFlavor::Vertex)]
    flavor: TargetFlavor,
    #[arg(long)]
    base_url: Option<String>,
    #[arg(long, default_value = pl_model_gemini::models::RECOMMENDED_MODEL)]
    model: String,
    #[arg(long)]
    effort: Option<String>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Chat {
        #[arg(long)]
        prompt: String,
    },
    ToolRoundtrip,
    Multimodal,
}

fn read_api_key(flavor: TargetFlavor) -> Result<String, Box<dyn std::error::Error>> {
    let vars: &[&str] = match flavor {
        TargetFlavor::Vertex => &["GCP_API_KEY", "MODEL_API_KEY"],
        TargetFlavor::GeminiApi => &["GEMINI_API_KEY", "MODEL_API_KEY", "GCP_API_KEY"],
    };
    for name in vars {
        if let Ok(value) = std::env::var(name)
            && !value.trim().is_empty()
        {
            return Ok(value);
        }
    }
    Err(format!("set one of {vars:?} before running gemini-live").into())
}

fn resolve_model(model_id: &str) -> Result<ModelDefinition, Box<dyn std::error::Error>> {
    let bundled = bundled_definition()?;
    Ok(bundled
        .models
        .into_iter()
        .find(|m| m.base.slug == model_id)
        .unwrap_or_else(|| {
            let mut m = bundled_definition()
                .unwrap()
                .models
                .into_iter()
                .next()
                .unwrap();
            m.base.slug = model_id.to_owned();
            m.base.display_name = model_id.to_owned();
            m
        }))
}

// 1x1 red PNG
const MINIMAL_PNG: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82,
];

const MINIMAL_PDF: &[u8] = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 18 Tf 20 100 Td (CODE_7391) Tj ET\nendstream\nendobj\n5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\nxref\n0 6\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000241 00000 n \n0000000335 00000 n \ntrailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n403\n%%EOF\n";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let key = read_api_key(args.flavor)?;
    let mut endpoint = match args.flavor {
        TargetFlavor::Vertex => endpoint::vertex_endpoint(args.base_url),
        TargetFlavor::GeminiApi => endpoint::gemini_api_endpoint(args.base_url),
    };
    endpoint.bearer_token = Some(key);
    let model = resolve_model(&args.model)?;
    let runtime = ModelRuntime::bind("gemini-live", endpoint, model, ADAPTER.codec, None)?;
    let context =
        || ModelInvocationContext::default().with_cancellation(Some(CancellationToken::new()));

    match args.command {
        Command::Chat { prompt } => {
            let req = CompletionRequest::builder()
                .messages(vec![Message {
                    role: MessageRole::User,
                    content: MessageContent::text(prompt),
                    presentation: Default::default(),
                    reasoning_content: None,
                    tool_calls: None,
                    tool_result: None,
                    metadata: Default::default(),
                }])
                .reasoning(args.effort.map(|e| ReasoningConfig {
                    effort: Some(e),
                    summary: None,
                }))
                .build();
            let resp = runtime.complete(req, context()).await?;
            println!("text: {}", completion_response_message_text(&resp));
            if let Some(reasoning) = &resp.reasoning_content {
                println!("reasoning_len: {}", reasoning.len());
            }
            println!("usage: {}", serde_json::to_string(&resp.accounting.usage)?);
            println!(
                "pricing: {}",
                serde_json::to_string(&resp.accounting.pricing)?
            );
        }
        Command::ToolRoundtrip => {
            let tools = vec![ToolSpec::Function {
                name: "lookup_secret_code".into(),
                description: "Returns a verification code for a given key.".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": { "key": { "type": "string" } },
                    "required": ["key"],
                    "additionalProperties": false
                }),
                allowed_callers: Vec::new(),
                output_schema: None,
            }];
            let mut req1 = CompletionRequest::builder()
                .system_prompt(SystemPrompt::new(
                    "Always call lookup_secret_code with key='alpha' before answering.",
                ))
                .messages(vec![Message {
                    role: MessageRole::User,
                    content: MessageContent::text("What is the verification code for alpha?"),
                    presentation: Default::default(),
                    reasoning_content: None,
                    tool_calls: None,
                    tool_result: None,
                    metadata: Default::default(),
                }])
                .tools(tools.clone())
                .reasoning(Some(ReasoningConfig {
                    effort: Some(args.effort.unwrap_or_else(|| "low".into())),
                    summary: None,
                }))
                .build();
            let resp1 = runtime.complete(req1.clone(), context()).await?;
            println!("turn1 tool_calls={}", resp1.tool_calls.len());
            println!(
                "turn1 usage: {}",
                serde_json::to_string(&resp1.accounting.usage)?
            );
            println!(
                "turn1 pricing: {}",
                serde_json::to_string(&resp1.accounting.pricing)?
            );
            assert!(
                !resp1.tool_calls.is_empty(),
                "expected at least one tool call"
            );
            req1.append_response(&resp1)?;
            for call in &resp1.tool_calls {
                req1.input.push(ModelContextItem::ToolResult {
                    message: Message {
                        role: MessageRole::Tool,
                        content: MessageContent::text(r#"{"code":"ALPHA-4291"}"#),
                        presentation: Default::default(),
                        reasoning_content: None,
                        tool_calls: None,
                        tool_result: Some(ToolResultRecord {
                            item_id: call.id.clone(),
                            call_id: call.call_id.clone(),
                            name: call.name.clone(),
                            kind: call.kind(),
                        }),
                        metadata: Default::default(),
                    },
                    receipt: pl_model_wire::completion::ToolResultReceipt {
                        call_id: call.call_id.clone(),
                        tool_name: call.name.clone(),
                        arguments_hash: "h1".into(),
                        result_hash: "h2".into(),
                        total_bytes: 21,
                        visible_bytes: 21,
                        truncated: false,
                        artifacts: Vec::new(),
                        continuation: None,
                        reused_from_call_id: None,
                    },
                });
            }
            let resp2 = runtime.complete(req1, context()).await?;
            println!("turn2 text: {}", completion_response_message_text(&resp2));
            println!(
                "turn2 usage: {}",
                serde_json::to_string(&resp2.accounting.usage)?
            );
            println!(
                "turn2 pricing: {}",
                serde_json::to_string(&resp2.accounting.pricing)?
            );
        }
        Command::Multimodal => {
            let req = CompletionRequest::builder()
                .input(vec![ModelContextItem::Message {
                    message: Message {
                        role: MessageRole::User,
                        content: MessageContent::new(vec![
                            ContentPart::Text {
                                text: "What color is the 1x1 image and what code text is inside the PDF? Answer concisely.".into(),
                            },
                            ContentPart::Attachment {
                                attachment_id: "img1".into(),
                                modality: AttachmentModality::Image,
                                media_type: "image/png".into(),
                                filename: Some("dot.png".into()),
                            },
                            ContentPart::Attachment {
                                attachment_id: "pdf1".into(),
                                modality: AttachmentModality::File,
                                media_type: "application/pdf".into(),
                                filename: Some("note.pdf".into()),
                            },
                        ]),
                        presentation: Default::default(),
                        reasoning_content: None,
                        tool_calls: None,
                        tool_result: None,
                        metadata: Default::default(),
                    },
                }])
                .attachments(vec![
                    AttachmentInput {
                        attachment_id: "img1".into(),
                        modality: AttachmentModality::Image,
                        media_type: "image/png".into(),
                        filename: Some("dot.png".into()),
                        source: AttachmentSource::Bytes {
                            bytes: Arc::from(MINIMAL_PNG),
                        },
                    },
                    AttachmentInput {
                        attachment_id: "pdf1".into(),
                        modality: AttachmentModality::File,
                        media_type: "application/pdf".into(),
                        filename: Some("note.pdf".into()),
                        source: AttachmentSource::Bytes {
                            bytes: Arc::from(MINIMAL_PDF),
                        },
                    },
                ])
                .build();
            let resp = runtime.complete(req, context()).await?;
            println!(
                "multimodal text: {}",
                completion_response_message_text(&resp)
            );
            println!(
                "multimodal usage: {}",
                serde_json::to_string(&resp.accounting.usage)?
            );
            println!(
                "multimodal pricing: {}",
                serde_json::to_string(&resp.accounting.pricing)?
            );
        }
    }
    Ok(())
}
