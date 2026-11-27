use pl_model_openai_wire::build_request;
use pl_model_wire::{
    completion::{
        AttachmentModality, AttachmentRepresentation, CompletionRequest, ContentPart, Message,
        MessageContent, MessageRole, ModelContextItem, ResolvedAttachment, ToolCallCaller,
        ToolCallKind, ToolCallRecord, ToolFormat, ToolResultRecord, ToolSpec,
    },
    model::{
        MediaRepresentation, MediaWireFormat, ModelDefinition, ModelMediaInputProfile,
        ModelModality, ModelTransportProfile,
    },
    protocol::{InstructionWireRole, WireApi},
};
use serde_json::{Value, json};

fn message(role: MessageRole, content: MessageContent) -> Message {
    Message {
        role,
        content,
        presentation: Default::default(),
        reasoning_content: None,
        tool_calls: None,
        tool_result: None,
        metadata: Default::default(),
    }
}

#[test]
fn responses_custom_output_keeps_ordered_text_image_and_file_parts() {
    let mut model = ModelDefinition::compatible("responses-custom-fixture");
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.extra.binding.request.media = [
        (ModelModality::Image, MediaWireFormat::ResponsesInputImage),
        (ModelModality::File, MediaWireFormat::ResponsesInputFile),
    ]
    .into_iter()
    .map(|(modality, wire)| ModelMediaInputProfile {
        modality,
        wire,
        first_send: vec![MediaRepresentation::DataUrl],
        replay: vec![MediaRepresentation::DataUrl],
    })
    .collect();
    let name = "annotate";
    let tool = ToolSpec::Custom {
        name: name.into(),
        description: "Annotate an example".into(),
        format: ToolFormat::Text,
        allowed_callers: Vec::new(),
        output_schema: None,
    };
    let mut assistant = message(MessageRole::Assistant, MessageContent::default());
    let program = ToolCallCaller::Program {
        caller_id: "program-1".into(),
    };
    assistant.tool_calls = Some(
        [("direct", None), ("program", Some(program))]
            .into_iter()
            .map(|(id, caller)| ToolCallRecord {
                item_id: format!("item-{id}"),
                call_id: id.into(),
                name: name.into(),
                kind: ToolCallKind::Custom,
                arguments: Value::String("example".into()),
                caller,
            })
            .collect(),
    );

    let image = ContentPart::Attachment {
        attachment_id: "image".into(),
        modality: AttachmentModality::Image,
        media_type: "image/png".into(),
        filename: None,
    };
    let file = ContentPart::Attachment {
        attachment_id: "file".into(),
        modality: AttachmentModality::File,
        media_type: "text/plain".into(),
        filename: Some("手记.txt".into()),
    };
    let direct = MessageContent::new(vec![
        ContentPart::Text {
            text: "  前言\n".into(),
        },
        image.clone(),
        ContentPart::Text {
            text: "\n后记  ".into(),
        },
        file,
    ]);
    let result = |id: &str, content, checked| Message {
        tool_result: Some(ToolResultRecord {
            item_id: format!("item-{id}"),
            call_id: id.into(),
            name: name.into(),
            kind: ToolCallKind::Custom,
            data: Some(json!({"checked":checked})),
        }),
        ..message(MessageRole::Tool, content)
    };
    let mut request = CompletionRequest::builder()
        .messages(vec![
            assistant,
            result("direct", direct, false),
            result(
                "program",
                MessageContent::text("program-only preview"),
                true,
            ),
        ])
        .tools(vec![tool])
        .build();
    let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAAD0lEQVR4AQEEAPv/AAAAAAAEAAFlScNgAAAAAElFTkSuQmCC";
    request.prepared_content = [
        ("image", AttachmentModality::Image, "image/png", png),
        ("file", AttachmentModality::File, "text/plain", "bm90ZQ=="),
    ]
    .into_iter()
    .map(|(id, modality, media_type, base64)| ResolvedAttachment {
        attachment_id: id.into(),
        modality,
        media_type: media_type.into(),
        filename: None,
        sources: vec![AttachmentRepresentation::DataUrl {
            base64: base64.into(),
        }],
    })
    .collect();
    let encode = |request: &CompletionRequest| {
        build_request(
            WireApi::Responses,
            InstructionWireRole::Developer,
            request,
            &model,
            None,
            false,
        )
    };
    let body = serde_json::to_value(encode(&request).unwrap()).unwrap();
    let input = body["input"].as_array().unwrap();
    assert_eq!(input.len(), 4);
    assert_eq!(
        input[2],
        json!({
            "type":"custom_tool_call_output", "call_id":"direct", "output":[
                {"type":"input_text", "text":"  前言\n"},
                {"type":"input_image", "detail":"auto", "image_url":format!("data:image/png;base64,{png}")},
                {"type":"input_text", "text":"\n后记  "},
                {"type":"input_file", "filename":"手记.txt", "file_data":"data:text/plain;base64,bm90ZQ=="}
            ]
        })
    );
    assert_eq!(
        input[3],
        json!({
            "type":"custom_tool_call_output", "call_id":"program",
            "caller":{"type":"program", "caller_id":"program-1"},
            "output":"{\"data\":{\"checked\":true}}"
        })
    );

    let Some(ModelContextItem::Message { message }) = request.input.last_mut() else {
        panic!("expected program tool result");
    };
    message.content.parts.push(image);
    let error = encode(&request).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("requires separate tool media context"),
        "{error}"
    );
}
