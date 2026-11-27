use pl_tool_lua::{Binding, ExecInput, ToolHost, execute};
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use tokio::sync::{Notify, mpsc, oneshot};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Default)]
struct Host {
    active: Arc<AtomicUsize>,
    peak: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
    started: Arc<Notify>,
    gate: Option<mpsc::UnboundedSender<oneshot::Sender<()>>>,
}

impl Host {
    fn gated() -> (Self, mpsc::UnboundedReceiver<oneshot::Sender<()>>) {
        let (gate, calls) = mpsc::unbounded_channel();
        (
            Self {
                gate: Some(gate),
                ..Self::default()
            },
            calls,
        )
    }
}

async fn release_batches(
    mut calls: mpsc::UnboundedReceiver<oneshot::Sender<()>>,
    count: usize,
    width: usize,
) {
    for offset in (0..count).step_by(width) {
        let mut batch = Vec::new();
        for _ in 0..width.min(count - offset) {
            batch.push(calls.recv().await.expect("the next call is admitted"));
        }
        assert!(
            calls.try_recv().is_err(),
            "another call bypassed the concurrency limit"
        );
        // Complete in reverse order; the caller must still return results in input order.
        for release in batch.into_iter().rev() {
            release.send(()).expect("admitted call is still waiting");
        }
    }
}
impl ToolHost for Host {
    fn bindings(&self) -> Vec<Binding> {
        vec![
            Binding {
                name: "read".into(),
                parallel: true,
            },
            Binding {
                name: "write".into(),
                parallel: false,
            },
        ]
    }
    async fn call(
        &self,
        name: String,
        value: Value,
    ) -> Result<Option<Value>, pl_tool_lua::CallFailure> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let active = self.active.fetch_add(1, Ordering::SeqCst) + 1;
        self.peak.fetch_max(active, Ordering::SeqCst);
        self.started.notify_one();
        if let Some(gate) = &self.gate {
            let (release, wait) = oneshot::channel();
            gate.send(release)
                .expect("the test observes every admitted call");
            wait.await.expect("the test releases the admitted call");
        }
        self.active.fetch_sub(1, Ordering::SeqCst);
        if value == json!("fail") {
            return Err(pl_tool_lua::CallFailure {
                message: "deliberate tool failure".into(),
                output: Some(json!({"hidden":"PRIVATE_FAILURE_RESULT"})),
            });
        }
        if value == json!("absent") {
            return Ok(None);
        }
        Ok(Some(
            json!({"name":name,"value":value,"unselected":"PRIVATE_INTERMEDIATE"}),
        ))
    }
}

#[tokio::test]
async fn nested_parallel_keeps_the_program_wide_limit() {
    let (host, calls) = Host::gated();
    let run = execute(
        input(
            "local jobs={}; for i=1,4 do jobs[i]=function() return parallel({function() return tools.read(1) end,function() return tools.read(2) end,function() return tools.read(3) end,function() return tools.read(4) end}) end end; return parallel(jobs)",
        ),
        host.clone(),
        CancellationToken::new(),
    );
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(3), async {
        tokio::join!(run, release_batches(calls, 16, 4))
    })
    .await
    .expect("nested calls must make progress");
    let result = result.unwrap();
    assert_eq!(result.error, None);
    assert_eq!(host.peak.load(Ordering::SeqCst), 4);
    assert_eq!(host.calls.load(Ordering::SeqCst), 16);
}

#[tokio::test]
async fn parallel_failure_stops_queued_side_effects_before_explicit_recovery() {
    let host = Host::default();
    let result = execute(input("local jobs={function() error('stop this batch') end}; for i=2,8 do jobs[i]=function() tools.write('must not start') end end; local ok=pcall(function() parallel(jobs) end); assert(not ok); return tools.write('explicit recovery').value"), host.clone(), CancellationToken::new()).await.unwrap();
    assert_eq!(result.error, None);
    assert_eq!(result.output, "explicit recovery");
    assert_eq!(host.calls.load(Ordering::SeqCst), 1);
    assert_eq!(host.active.load(Ordering::SeqCst), 0);
}
fn input(code: &str) -> ExecInput {
    ExecInput {
        code: code.into(),
        args: Default::default(),
        timeout_ms: None,
        max_output_bytes: None,
    }
}

#[tokio::test]
async fn selects_results_preserves_json_and_handles_tool_failure() {
    let code = r#"
        local r = tools.read({empty=json.array({}), null=json.null, nested={true, "雪"}})
        local ok, err = pcall(function() tools.read("fail") end)
        assert(not ok and tostring(err):find("deliberate tool failure",1,true)); assert(err.output.hidden=="PRIVATE_FAILURE_RESULT" and not tostring(err):find("PRIVATE_FAILURE_RESULT",1,true))
        local absent = tools.read("absent")
        assert(absent == nil and r.value.null == json.null)
        local values = parallel({function() return absent end, function() return r.value.empty end})
        assert(json.encode(values) == "[null,[]]")
        r.value.nested[1] = false
        print({selected=r.value.empty}); return json.decode(json.encode(r.value))
    "#;
    let result = execute(input(code), Host::default(), CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(result.error, None);
    assert!(result.output.starts_with("{\"selected\":[]}\n"));
    assert_eq!(
        serde_json::from_str::<Value>(result.output.lines().last().unwrap()).unwrap(),
        json!({"empty":[],"null":null,"nested":[false,"雪"]})
    );
    assert!(!result.output.contains("PRIVATE_INTERMEDIATE"));
}

#[tokio::test]
async fn overlaps_reads_but_serializes_mutations_and_keeps_result_order() {
    for (name, expected_peak) in [("read", 4), ("write", 1)] {
        let (host, calls) = Host::gated();
        let code = format!(
            r#"return parallel({{function() return tools.{name}(1).value end,function() return tools.{name}(2).value end,function() return tools.{name}(3).value end,function() return tools.{name}(4).value end,function() return tools.{name}(5).value end}})"#
        );
        let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(3), async {
            tokio::join!(
                execute(input(&code), host.clone(), CancellationToken::new()),
                release_batches(calls, 5, expected_peak)
            )
        })
        .await
        .expect("admitted calls must settle");
        let result = result.unwrap();
        assert_eq!(result.error, None);
        assert_eq!(result.output, "[1,2,3,4,5]");
        assert_eq!(host.peak.load(Ordering::SeqCst), expected_peak);
        assert_eq!(host.active.load(Ordering::SeqCst), 0);
    }
}

#[tokio::test]
async fn bounds_cpu_memory_and_capture_and_keeps_prior_output() {
    for code in [
        "print('retained'); while true do end",
        "print('retained'); return string.rep('x',128*1024*1024)",
        "print('retained'); print(string.rep('x',17*1024*1024))",
    ] {
        let mut args = input(code);
        args.timeout_ms = Some(100);
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(3),
            execute(args, Host::default(), CancellationToken::new()),
        )
        .await
        .expect("worker must stop")
        .unwrap();
        assert!(result.error.is_some(), "{code}");
        assert!(result.output.starts_with("retained\n"));
    }
}

#[tokio::test]
async fn cancellation_stops_a_catch_loop_and_fresh_calls_cannot_access_os_or_old_state() {
    let token = CancellationToken::new();
    let host = Host::default();
    let started = host.started.clone();
    let run = execute(
        input("while true do pcall(function() tools.read('entered'); while true do end end) end"),
        host,
        token.clone(),
    );
    let cancel = async {
        started.notified().await;
        token.cancel();
    };
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(3), async {
        tokio::join!(run, cancel)
    })
    .await
    .unwrap();
    assert!(result.unwrap().error.unwrap().contains("cancelled"));
    execute(
        input("secret=42"),
        Host::default(),
        CancellationToken::new(),
    )
    .await
    .unwrap();
    let result = execute(input("assert(secret==nil and os==nil and io==nil and package==nil and debug==nil and require==nil and dofile==nil); return 'clean'"),Host::default(),CancellationToken::new()).await.unwrap();
    assert_eq!(result.error, None);
    assert_eq!(result.output, "clean");
}

#[tokio::test]
async fn caller_can_extend_deadline_and_model_output_without_extra_ceiling() {
    let mut args = input("collectgarbage(); return string.rep('x', 70000)");
    args.timeout_ms = Some(900000);
    args.max_output_bytes = Some(70000);
    let result = execute(args, Host::default(), CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(result.error, None);
    assert_eq!(result.output.len(), 70000);
    assert_eq!(result.model_output_bytes, 70000);
}

#[tokio::test]
async fn syntax_and_unknown_binding_diagnostics_do_not_admit_calls_or_dump_results() {
    for (code, hint) in [
        ("pwd; rg --files", "before any tool started"),
        (
            r#"tools.read({command="grep 'alpha\|beta' sample.txt"})"#,
            "invalid escape",
        ),
        ("tools.read([=[text])", "unfinished long string"),
        ("tools.missing({})", "frozen SDK"),
        (
            "parallel(function() return tools.read(1) end, function() return tools.read(2) end)",
            "expected table",
        ),
        ("tools.read('fail')", "deliberate tool failure"),
    ] {
        let host = Host::default();
        let result = execute(input(code), host.clone(), CancellationToken::new())
            .await
            .unwrap();
        let error = result.error.expect("program should fail");
        assert!(error.contains(hint), "{error}");
        assert!(!error.contains("PRIVATE_FAILURE_RESULT"));
        assert_eq!(
            host.calls.load(Ordering::SeqCst),
            usize::from(code == "tools.read('fail')")
        );
    }
}

#[tokio::test]
async fn json_arguments_reach_tools_without_lua_string_interpolation() {
    let arguments = json!({
        "command": "grep -n 'alpha\\|beta' sample.txt",
        "patch": "*** Begin Patch\n*** Add File: fixture.txt\n+[[plain]]\n+[=[level-one]=]\n*** End Patch\n",
        "quoted": "it's \"ready\"; C:\\work\\new",
        "items": [null, true, 7, "雪"],
        "empty": [],
    });
    let definition = pl_tool_lua::definition("tools.read(args)");
    let pl_agent_tool::InputFormat::JsonSchema(schema) = definition.input() else {
        panic!("exec must publish a JSON input schema");
    };
    assert_eq!(schema["properties"]["args"]["type"], "object");
    // A JSON-encoded string is not the named argument object advertised to the model.
    assert!(
        serde_json::from_value::<ExecInput>(json!({
            "code": "return tools.read(args)",
            "args": "{\"command\":\"pwd\"}",
        }))
        .is_err()
    );
    let host = Host::default();
    for arguments in [arguments, json!("tools.write('must not run'); ]=]\n雪\\n")] {
        let request: ExecInput = serde_json::from_value(json!({
            "code": "return tools.read(args.value).value",
            "args": {"value": arguments},
        }))
        .unwrap();
        let result = execute(request, host.clone(), CancellationToken::new())
            .await
            .unwrap();
        assert_eq!(result.error, None);
        match &arguments {
            Value::String(text) => assert_eq!(&result.output, text),
            _ => assert_eq!(
                serde_json::from_str::<Value>(&result.output).unwrap(),
                arguments
            ),
        }
    }
    assert_eq!(host.calls.load(Ordering::SeqCst), 2);
    let omitted: ExecInput = serde_json::from_value(json!({
        "code": "assert(next(args) == nil); return 'fresh'",
    }))
    .unwrap();
    let next = execute(omitted, host, CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(next.error, None);
    assert_eq!(next.output, "fresh");
}

#[tokio::test]
async fn receipt_syntax_error_locates_the_source_and_correction_runs_original_calls_once() {
    // Reduced from the end-of-program result tables in issue #487's real trace.
    let cases = [
        "local r = tools.read(args).value; print({exitCode=r.exitCode, stdout=r.stdout, stderr:r.stderr})",
        "local r = tools.read(args).value\nreturn {payload={exitCode=r.exitCode, stdout=r.stdout, stderr:r.stderr}}",
        "tools.write(args)\nlocal r = tools.read(args).value\nprint({exitCode=r.exitCode, stdout=r.stdout, stderr:r.stderr})",
    ];
    for code in cases {
        let host = Host::default();
        let request: ExecInput = serde_json::from_value(json!({
            "code": code, "args": {"exitCode":0,"stdout":"unchanged:雪","stderr":""},
        }))
        .unwrap();
        let result = execute(request.clone(), host.clone(), CancellationToken::new())
            .await
            .unwrap();
        let error = result
            .error
            .expect("the malformed table must fail at parsing");
        assert!(
            error.contains("function arguments expected near '.'"),
            "{error}"
        );
        assert!(error.contains("before any tool started"), "{error}");
        assert!(
            error.contains("stderr:r.stderr"),
            "the reported source is missing: {error}"
        );
        assert!(
            error.contains("key=value") && error.contains("stderr=r.stderr"),
            "{error}"
        );
        assert!(result.output.is_empty());
        assert_eq!(host.calls.load(Ordering::SeqCst), 0);

        let fixed = ExecInput {
            code: code.replace("stderr:r.stderr", "stderr=r.stderr"),
            ..request
        };
        let result = execute(fixed, host.clone(), CancellationToken::new())
            .await
            .unwrap();
        assert_eq!(result.error, None);
        let expected = json!({"exitCode":0,"stdout":"unchanged:雪","stderr":""});
        assert_eq!(
            serde_json::from_str::<Value>(&result.output).unwrap(),
            if code.contains("payload=") {
                json!({"payload":expected})
            } else {
                expected
            }
        );
        assert_eq!(
            host.calls.load(Ordering::SeqCst),
            if code.starts_with("tools.write") {
                2
            } else {
                1
            }
        );
    }
}

#[tokio::test]
async fn source_context_is_bounded_and_does_not_relabel_methods_strings_or_runtime_failure() {
    let host = Host::default();
    let args =
        json!({"command":"printf 'https://example.invalid/a:b'", "patch":"+stderr:r.stderr"});
    let request: ExecInput = serde_json::from_value(json!({
        "code": "local obj={value=args, method=function(self) return self.value end}; return tools.write(obj:method()).value",
        "args":args,
    })).unwrap();
    let result = execute(request, host.clone(), CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(result.error, None);
    assert_eq!(serde_json::from_str::<Value>(&result.output).unwrap(), args);
    assert_eq!(host.calls.load(Ordering::SeqCst), 1);

    let partial = execute(
        input("tools.write('once'); print('retained'); tools.read('fail')"),
        host.clone(),
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(partial.output, "retained\n");
    let error = partial.error.unwrap();
    assert!(error.contains("deliberate tool failure"), "{error}");
    assert!(
        !error.contains("before any tool started") && !error.contains("Source excerpt"),
        "{error}"
    );
    assert_eq!(host.calls.load(Ordering::SeqCst), 3);

    // A real method call followed by another syntax error is not a field-colon diagnosis.
    let valid_method = "local obj={method=function() return 1 end}; obj:method(); return {";
    let error = execute(input(valid_method), host.clone(), CancellationToken::new())
        .await
        .unwrap()
        .error
        .unwrap();
    assert!(error.contains("before any tool started"), "{error}");
    assert!(!error.contains("If this is a result table"), "{error}");
    assert_eq!(host.calls.load(Ordering::SeqCst), 3);

    let code = format!(
        "-- UNRELATED_SOURCE\n-- {}\nlocal r = tools.read(1)\nprint({{padding='{}',stderr:r.name}})\n-- AFTER_ERROR",
        "x".repeat(10000),
        "雪".repeat(10000)
    );
    let result = execute(input(&code), host.clone(), CancellationToken::new())
        .await
        .unwrap();
    let error = result.error.unwrap();
    assert!(error.contains("[string \"exec\"]:4:"), "{error}");
    assert!(
        error.contains("4 |") && error.contains("stderr:r.name"),
        "{error}"
    );
    assert!(
        !error.contains("UNRELATED_SOURCE"),
        "must not dump unrelated code"
    );
    assert!(
        error.len() < 6000,
        "source excerpt must be bounded: {} bytes",
        error.len()
    );
    assert_eq!(host.calls.load(Ordering::SeqCst), 3);
}
