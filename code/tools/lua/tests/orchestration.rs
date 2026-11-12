use pl_tool_lua::{Binding, ExecInput, ToolHost, execute};
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Default)]
struct Host {
    active: Arc<AtomicUsize>,
    peak: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
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
    async fn call(&self, name: String, value: Value) -> Result<Value, pl_tool_lua::CallFailure> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let active = self.active.fetch_add(1, Ordering::SeqCst) + 1;
        self.peak.fetch_max(active, Ordering::SeqCst);
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        self.active.fetch_sub(1, Ordering::SeqCst);
        if value == json!("fail") {
            return Err(pl_tool_lua::CallFailure {
                message: "deliberate tool failure".into(),
                output: Some(json!({"hidden":"PRIVATE_FAILURE_RESULT"})),
            });
        }
        Ok(json!({"name":name,"value":value,"unselected":"PRIVATE_INTERMEDIATE"}))
    }
}

#[tokio::test]
async fn nested_parallel_keeps_the_program_wide_limit() {
    let host = Host::default();
    let result = execute(input("local jobs={}; for i=1,4 do jobs[i]=function() return parallel({function() return tools.read(1) end,function() return tools.read(2) end,function() return tools.read(3) end,function() return tools.read(4) end}) end end; return parallel(jobs)"), host.clone(), CancellationToken::new()).await.unwrap();
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
        print({selected=r.value.empty}); return json.decode(json.encode(r.value))
    "#;
    let result = execute(input(code), Host::default(), CancellationToken::new())
        .await
        .unwrap();
    assert_eq!(result.error, None);
    assert!(result.output.starts_with("{\"selected\":[]}\n"));
    assert_eq!(
        serde_json::from_str::<Value>(result.output.lines().last().unwrap()).unwrap(),
        json!({"empty":[],"null":null,"nested":[true,"雪"]})
    );
    assert!(!result.output.contains("PRIVATE_INTERMEDIATE"));
}

#[tokio::test]
async fn overlaps_reads_but_serializes_mutations_and_keeps_result_order() {
    for (name, expected_peak) in [("read", 4), ("write", 1)] {
        let host = Host::default();
        let code = format!(
            r#"return parallel({{function() return tools.{name}(1).value end,function() return tools.{name}(2).value end,function() return tools.{name}(3).value end,function() return tools.{name}(4).value end,function() return tools.{name}(5).value end}})"#
        );
        let result = execute(input(&code), host.clone(), CancellationToken::new())
            .await
            .unwrap();
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
    let run = execute(
        input("while true do pcall(function() while true do end end) end"),
        Host::default(),
        token.clone(),
    );
    let cancel = async {
        tokio::time::sleep(std::time::Duration::from_millis(25)).await;
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
        ("tools.missing({})", "frozen SDK"),
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
