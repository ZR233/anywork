use super::super::wire::Request;
use super::*;

const PREFIX: &str = "dg-1";
const COMMAND: &str = "printf delegated";

fn call_and_output(
    input: &mut Vec<Value>,
    label: &str,
    tool: &str,
    arguments: Value,
    output: String,
) {
    let call_id = format!("{PREFIX}-{label}");
    input.push(json!({
        "type":"function_call", "call_id":call_id, "name":tool,
        "arguments":arguments.to_string()
    }));
    input.push(json!({"type":"function_call_output", "call_id":call_id, "output":output}));
}

fn payload(content: &str, version: u32, next_cursor: Option<usize>, total: usize) -> Value {
    json!({"format":"pl.tool.exec", "version":version, "content":content,
        "nextCursor":next_cursor, "totalBytes":total})
}

fn task_result(task_id: &str, page: Value) -> String {
    json!({
        "task":{"taskId":task_id,"toolId":"exec","status":"succeeded","cancelRequested":false},
        "result":page
    })
    .to_string()
}

fn request(input: Vec<Value>) -> Request {
    serde_json::from_value(json!({
        "model":"fixture", "input":input,
        "tools":[{"name":"exec"},{"name":"wait"},{"name":"get_tool_task"}]
    }))
    .expect("fixture Request")
}

fn read(request: &Request, label: &str) -> Progress<String> {
    let environment = super::super::Environment::new(None);
    let flow = Flow::new(request, &environment).expect("authored delegation prompt");
    read_stdout(&flow, label, COMMAND.to_owned())
}

fn take_output(result: Progress<String>) -> String {
    match result {
        Ok(output) => output,
        Err(Stop::Failed(error)) => panic!("read_stdout failed: {error:#}"),
        Err(Stop::Call(_)) => panic!("read_stdout unexpectedly requested another tool call"),
    }
}

fn assert_failed(result: Progress<String>) {
    match result {
        Err(Stop::Failed(error)) => {
            assert!(!error.to_string().is_empty(), "preserve actual failure")
        }
        Err(Stop::Call(_)) => panic!("read_stdout unexpectedly requested another tool call"),
        Ok(output) => panic!("expected rejection, consumed output: {output}"),
    }
}

fn record(stdout: &str) -> String {
    json!({
        "state":{"kind":"final","data":{"result":{"kind":"succeeded","data":{"exit_code":0}}}},
        "processStarted":true, "exitCode":0,
        "stdout":{"content":stdout,"originalBytes":stdout.len(),"displayedBytes":stdout.len(),"omittedBytes":0,"textLossy":false,"wasTruncated":false},
        "stderr":{"content":"","originalBytes":0,"displayedBytes":0,"omittedBytes":0,"textLossy":false,"wasTruncated":false},
        "stdoutConfirmedBytes":stdout.len(), "stderrConfirmedBytes":0, "captureStatus":"complete"
    }).to_string()
}

#[test]
fn synchronous_read_stdout_consumes_record_with_resource_tail_and_rejects_preview() {
    let arguments = json!({"command":COMMAND,"cwd":".","timeoutSeconds":60,"maxOutputChars":12000});
    let mut input = vec![json!({"type":"message","role":"user","content":"[[delegation:test]]"})];
    call_and_output(
        &mut input,
        "sync",
        "exec",
        arguments.clone(),
        format!("{} Resource reference: {{}}", record("héllo")),
    );
    assert_eq!(take_output(read(&request(input), "sync")), "héllo");

    let legacy = json!({
        "state":{"kind":"final","data":{"result":{"kind":"succeeded","data":{"exit_code":0}}}},
        "stdout":"legacy", "stderr":"", "archived":true
    })
    .to_string();
    let mut input = vec![json!({"type":"message","role":"user","content":"[[delegation:test]]"})];
    call_and_output(&mut input, "sync", "exec", arguments, legacy);
    assert_failed(read(&request(input), "sync"));
}

fn background_history(version: u32, result_task_id: &str, cursor: usize) -> Request {
    let task_id = format!("task:{PREFIX}-async");
    let body = record("héllo");
    let split = body.char_indices().nth(body.chars().count() / 2).unwrap().0;
    let arguments = json!({"command":COMMAND,"cwd":".","timeoutSeconds":60,"maxOutputChars":12000});
    let mut input = vec![json!({"type":"message","role":"user","content":"[[delegation:test]]"})];
    call_and_output(
        &mut input,
        "async",
        "exec",
        arguments,
        format!("Task {task_id} is running. Its result will be delivered when execution finishes."),
    );
    call_and_output(
        &mut input,
        "async-wait-0",
        "wait",
        json!({"taskIds":[task_id],"timeoutMs":300000}),
        "wake".to_owned(),
    );
    call_and_output(
        &mut input,
        "async-result-0",
        "get_tool_task",
        json!({"taskId":task_id,"resultCursor":0}),
        task_result(
            result_task_id,
            payload(&body[..split], version, Some(cursor), body.len()),
        ),
    );
    call_and_output(
        &mut input,
        "async-result-0-page-1",
        "get_tool_task",
        json!({"taskId":task_id,"resultCursor":split}),
        task_result(&task_id, payload(&body[split..], 2, None, body.len())),
    );
    request(input)
}

#[test]
fn background_read_stdout_waits_and_joins_two_current_v2_pages() {
    let body = record("héllo");
    let split = body.char_indices().nth(body.chars().count() / 2).unwrap().0;
    let task_id = format!("task:{PREFIX}-async");
    assert_eq!(
        take_output(read(&background_history(2, &task_id, split), "async")),
        "héllo"
    );
}

#[test]
fn background_read_stdout_rejects_v1_wrong_task_identity_and_discontinuous_cursor() {
    let body = record("héllo");
    let split = body.char_indices().nth(body.chars().count() / 2).unwrap().0;
    let task_id = format!("task:{PREFIX}-async");
    for (version, identity, cursor) in [
        (1, task_id.as_str(), split),
        (2, "task:foreign", split),
        (2, task_id.as_str(), split + 1),
    ] {
        assert_failed(read(
            &background_history(version, identity, cursor),
            "async",
        ));
    }
}
