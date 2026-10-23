//! Explicit public-tool observation, outside the automated test gate.
//! Run with an owned scratch directory: cargo run -p pl-tool --example skill_discovery_observe -- SCRATCH
use anyhow::{Context, ensure};
use pl_core::{
    context::OpaquePayload,
    tool::opaque::{CallContext, Tool},
};
use pl_tool::skill::{
    FileSystemSkillProvider, SkillDirectorySource, SkillProviderRegistration, SkillProviderRequest,
    SkillRegistry, SkillSourceKind, SkillsConfig, ThreadSkillKind, ThreadSkillManageTool,
    ThreadSkillTool,
};
use pl_tool::workspace::{AgentWorkspace, ToolWorkspace};
use serde_json::{Value, json};
use std::{fs, path::Path, sync::Arc};
use tokio_util::sync::CancellationToken;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let scratch = std::env::args_os()
        .nth(1)
        .context("pass an owned scratch directory")?;
    if std::env::args_os()
        .nth(2)
        .is_some_and(|argument| argument == "--configured-child")
    {
        return observe_configured_provider(Path::new(&scratch)).await;
    }
    let directory = tempfile::Builder::new()
        .prefix("skill-observe-")
        .tempdir_in(fs::canonicalize(scratch)?)?;
    let root = directory.path();
    let skills = root.join("skills");
    for name in ["deleted", "invalidated", "stable"] {
        write_skill(&skills, name)?;
    }
    // Isolate discovery from the checkout's ignore rules for its owned session scratch.
    fs::write(skills.join(".ignore"), "!**\n")?;
    let registry = SkillRegistry::new();
    let _registration = registry.register(Arc::new(FileSystemSkillProvider::from_directories(
        "observation",
        vec![SkillDirectorySource::new(&skills, SkillSourceKind::Project)],
    )?))?;
    let catalog = Arc::new(
        registry
            .discover(SkillProviderRequest {
                workspace_root: root.to_path_buf(),
                config: SkillsConfig::default(),
                system_dir: None,
                cancellation: CancellationToken::new(),
            })
            .await?,
    );
    println!(
        "{}",
        json!({"step": "preparation", "catalog": catalog.snapshot()})
    );
    let list = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::List);
    let view = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::View);
    let before = invoke(&list, "before", json!({})).await?;
    ensure!(
        before["count"] == 3,
        "observation setup did not discover the three initial skills: {before}"
    );
    fs::remove_dir_all(skills.join("deleted"))?;
    fs::write(
        skills.join("invalidated/SKILL.md"),
        "---\nname: invalidated\n---\ninvalid\n",
    )?;
    write_skill(&skills, "added")?;
    let after = invoke(&list, "after-mutation", json!({})).await?;
    let names = after["skills"]
        .as_array()
        .context("list skills")?
        .iter()
        .map(|row| row["name"].as_str().unwrap_or_default())
        .collect::<Vec<_>>();
    let added_view = invoke(&view, "view-added", json!({"name": "added"})).await;
    ensure!(
        names == ["added", "stable"] && added_view.is_ok(),
        "dynamic discovery failed: expected [added, stable] and readable added skill; got {names:?}, added view: {added_view:?}"
    );
    let refreshed = catalog
        .discovery_sources()
        .discover(CancellationToken::new())
        .await?;
    ensure!(
        refreshed.snapshot().complete && !refreshed.snapshot().warnings.is_empty(),
        "invalid document warning was not retained"
    );
    ensure!(
        catalog.find("deleted").is_some() && catalog.find("added").is_none(),
        "tool refresh rewrote the preparation catalog"
    );
    observe_fixed_sources(&root.join("fixed-sources")).await?;
    observe_policy_and_paths(&root.join("policy-and-paths")).await?;
    observe_management(&root.join("management")).await?;
    let configured_root = root.join("configured-provider");
    fs::create_dir_all(&configured_root)?;
    // Isolate home-derived roots in a child environment without mutating this process's HOME.
    let status = tokio::process::Command::new(std::env::current_exe()?)
        .kill_on_drop(true)
        .arg(&configured_root)
        .arg("--configured-child")
        .env("HOME", configured_root.join("home"))
        .env("USERPROFILE", configured_root.join("home"))
        .status()
        .await?;
    ensure!(
        status.success(),
        "configured filesystem Provider observation failed: {status}"
    );
    println!("SKILL_DISCOVERY_OBSERVATION=PASS");
    Ok(())
}

async fn observe_configured_provider(root: &Path) -> anyhow::Result<()> {
    let project = root.join(".agents/skills");
    let user = root.join("user");
    let system = root.join("system");
    for source in [&project, &user, &system] {
        prepare_source(source)?;
    }
    write_skill(&project, "configured")?;
    fs::create_dir_all(project.join("configured/references"))?;
    fs::write(
        project.join("configured/references/guide.md"),
        "configured support",
    )?;
    let registry = SkillRegistry::new();
    let _registration = registry.register(Arc::new(FileSystemSkillProvider::new()))?;
    let mut config = SkillsConfig {
        user_dir: user.to_string_lossy().into_owned(),
        ..SkillsConfig::default()
    };
    let catalog = registry
        .discover(SkillProviderRequest {
            config: config.clone(),
            system_dir: Some(system.clone()),
            ..request(root)
        })
        .await?;
    let list = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::List);
    let view = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::View);
    write_skill(&user, "new-user")?;
    write_skill(&system, "new-system")?;
    config.user_dir = root.join("other-user").to_string_lossy().into_owned();
    write_skill(&root.join("other-user"), "not-in-fixed-config")?;
    let listed = invoke(&list, "configured-paths-stay-fixed", json!({})).await?;
    ensure!(skill_names(&listed)? == ["configured", "new-system", "new-user"]);
    invoke(
        &view,
        "configured-main-record",
        json!({"name": "configured"}),
    )
    .await?;
    let usage: Value =
        serde_json::from_str(&fs::read_to_string(project.join("configured/.usage.json"))?)?;
    ensure!(usage["views"] == 1);
    invoke(
        &view,
        "configured-support-record",
        json!({"name": "configured", "filePath": "references/guide.md"}),
    )
    .await?;
    let usage: Value =
        serde_json::from_str(&fs::read_to_string(project.join("configured/.usage.json"))?)?;
    ensure!(usage["views"] == 2);
    #[cfg(unix)]
    {
        use pl_tool::skill::SkillLoadInvocation;
        use std::os::unix::fs::symlink;
        let original = root.join("original-agents");
        let outside = root.join("outside-agents");
        write_skill(&outside.join("skills"), "configured")?;
        fs::rename(root.join(".agents"), &original)?;
        symlink(&outside, root.join(".agents"))?;
        ensure!(
            catalog
                .load(
                    "configured",
                    SkillLoadInvocation::Model,
                    CancellationToken::new()
                )
                .await
                .is_err(),
            "frozen user-gesture catalog followed a replaced ancestor"
        );
        reject(
            &view,
            "configured-ancestor-symlink-denied",
            json!({"name": "configured"}),
            "symbolic link",
        )
        .await?;
        ensure!(!outside.join("skills/configured/.usage.json").exists());
        fs::remove_file(root.join(".agents"))?;
        fs::rename(original, root.join(".agents"))?;
        invoke(
            &view,
            "configured-ancestor-restored",
            json!({"name": "configured"}),
        )
        .await?;
    }
    Ok(())
}

async fn observe_fixed_sources(root: &Path) -> anyhow::Result<()> {
    let primary = root.join("primary");
    let fallback = root.join("fallback");
    let empty_container = root.join("empty-container");
    let empty = empty_container.join("skills");
    for source in [&primary, &fallback, &empty] {
        prepare_source(source)?;
    }
    write_document(&primary, "shared", "", "primary body")?;
    write_document(&fallback, "shared", "", "fallback body")?;
    for (source, content) in [
        (&primary, "primary resource"),
        (&fallback, "fallback resource"),
    ] {
        fs::create_dir_all(source.join("shared/references"))?;
        fs::write(source.join("shared/references/guide.md"), content)?;
    }
    let registry = SkillRegistry::new();
    let registrations = vec![
        register(&registry, "primary", &primary, SkillSourceKind::Project)?,
        register(&registry, "fallback", &fallback, SkillSourceKind::User)?,
        register(
            &registry,
            "initially-empty",
            &empty,
            SkillSourceKind::Project,
        )?,
    ];
    let preparation_cancellation = CancellationToken::new();
    let mut config = SkillsConfig::default();
    let catalog = registry
        .discover(SkillProviderRequest {
            workspace_root: root.to_path_buf(),
            config: config.clone(),
            system_dir: None,
            cancellation: preparation_cancellation.clone(),
        })
        .await?;
    let list = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::List);
    let view = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::View);
    let late = root.join("later-provider");
    prepare_source(&late)?;
    write_skill(&late, "not-authorized")?;
    let late_registration = register(&registry, "later-provider", &late, SkillSourceKind::Project)?;
    config.disabled.push("shared".into());
    preparation_cancellation.cancel();
    // Releasing a temporary registry's guards must not drop zero-candidate source capabilities.
    drop(registrations);
    drop(registry);
    write_skill(&empty, "appeared")?;
    let names = invoke(&list, "fixed-sources-after-registry-drop", json!({})).await?;
    ensure!(
        skill_names(&names)? == ["appeared", "shared"],
        "source/config scope expanded or empty Provider was lost: {names}"
    );
    drop(late_registration);
    let main = invoke(&view, "winner-primary", json!({"name": "shared"})).await?;
    ensure!(
        main["content"]
            .as_str()
            .is_some_and(|content| content.contains("primary body"))
            && main["skill"]["providerId"] == "primary"
    );
    let resource = invoke(
        &view,
        "winner-primary-resource",
        json!({"name": "shared", "filePath": "references/guide.md"}),
    )
    .await?;
    ensure!(
        resource["content"] == "primary resource" && resource["skill"]["providerId"] == "primary"
    );
    ensure!(
        !primary.join("shared/.usage.json").exists(),
        "explicit Project source received a usage write"
    );
    fs::remove_dir_all(primary.join("shared"))?;
    let resource = invoke(
        &view,
        "winner-fallback-resource",
        json!({"name": "shared", "filePath": "references/guide.md"}),
    )
    .await?;
    ensure!(
        resource["content"] == "fallback resource" && resource["skill"]["providerId"] == "fallback"
    );

    // A real filesystem inspection failure makes a Provider observation incomplete.
    fs::remove_dir_all(&empty_container)?;
    fs::write(&empty_container, "not a directory")?;
    reject(&list, "incomplete-list", json!({}), "incomplete").await?;
    reject(
        &view,
        "incomplete-view-no-fallback",
        json!({"name": "shared"}),
        "incomplete",
    )
    .await?;
    fs::remove_file(&empty_container)?;
    prepare_source(&empty)?;
    let recovered = invoke(&list, "inspection-recovered", json!({})).await?;
    ensure!(skill_names(&recovered)? == ["shared"]);

    // A document read failure exercises the actual filesystem Provider's Err path, not a fake.
    fs::write(fallback.join("shared/SKILL.md"), [0xff, 0xfe])?;
    reject(&list, "provider-io-list", json!({}), "incomplete").await?;
    reject(
        &view,
        "provider-io-view",
        json!({"name": "shared"}),
        "incomplete",
    )
    .await?;
    write_document(&fallback, "shared", "", "recovered body")?;
    let recovered = invoke(&view, "provider-io-recovered", json!({"name": "shared"})).await?;
    ensure!(
        recovered["content"]
            .as_str()
            .is_some_and(|content| content.contains("recovered body"))
    );
    let cancelled = CancellationToken::new();
    cancelled.cancel();
    ensure!(
        invoke_with_cancellation(&list, "cancelled-call", json!({}), cancelled)
            .await
            .is_err()
    );
    invoke(&list, "next-call-not-cancelled", json!({})).await?;

    fs::remove_dir_all(&fallback)?;
    fs::remove_dir_all(&primary)?;
    fs::remove_dir_all(&empty)?;
    let empty_result = invoke(&list, "complete-empty-clears-all", json!({})).await?;
    ensure!(skill_names(&empty_result)?.is_empty());
    reject(
        &view,
        "deleted-winner-is-not-readable",
        json!({"name": "shared"}),
        "not found",
    )
    .await?;
    Ok(())
}

async fn observe_policy_and_paths(root: &Path) -> anyhow::Result<()> {
    let skills = root.join("skills");
    prepare_source(&skills)?;
    write_skill(&skills, "policy")?;
    let registry = SkillRegistry::new();
    let _registration = register(&registry, "policies", &skills, SkillSourceKind::Project)?;
    let catalog = registry.discover(request(root)).await?;
    let list = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::List);
    let view = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::View);
    write_document(
        &skills,
        "policy",
        "disable-model-invocation: true\n",
        "user only",
    )?;
    let disabled = invoke(&list, "model-disabled-list", json!({})).await?;
    ensure!(skill_names(&disabled)?.is_empty());
    reject(
        &view,
        "model-disabled-view",
        json!({"name": "policy"}),
        "not invocable",
    )
    .await?;
    let other_platform = if cfg!(target_os = "windows") {
        "linux"
    } else {
        "windows"
    };
    write_document(
        &skills,
        "policy",
        &format!("platforms: [{other_platform}]\n"),
        "wrong platform",
    )?;
    let inapplicable = invoke(&list, "platform-changed", json!({})).await?;
    ensure!(skill_names(&inapplicable)?.is_empty());
    reject(
        &view,
        "platform-view-denied",
        json!({"name": "policy"}),
        "not found",
    )
    .await?;
    write_document(
        &skills,
        "policy",
        "disable-model-invocation: [invalid]\n",
        "invalid policy",
    )?;
    let invalid = invoke(&list, "invalid-policy-skipped", json!({})).await?;
    ensure!(skill_names(&invalid)?.is_empty());
    write_skill(&skills, "policy")?;
    fs::create_dir_all(skills.join("policy/references"))?;
    fs::write(
        skills.join("policy/references/guide.md"),
        "allowed support content",
    )?;
    let resource = invoke(
        &view,
        "support-file",
        json!({"name": "policy", "filePath": "references/guide.md"}),
    )
    .await?;
    ensure!(resource["content"] == "allowed support content");
    reject(
        &view,
        "support-traversal-denied",
        json!({"name": "policy", "filePath": "../outside.md"}),
        "path",
    )
    .await?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::symlink;
        let secret = root.join("outside.md");
        fs::write(&secret, "must not leak")?;
        symlink(&secret, skills.join("policy/references/linked.md"))?;
        reject(
            &view,
            "support-symlink-denied",
            json!({"name": "policy", "filePath": "references/linked.md"}),
            "symbolic link",
        )
        .await?;
        fs::rename(skills.join("policy/SKILL.md"), root.join("actual-skill.md"))?;
        symlink(root.join("actual-skill.md"), skills.join("policy/SKILL.md"))?;
        let linked = invoke(&list, "linked-main-removed-from-list", json!({})).await?;
        ensure!(skill_names(&linked)?.is_empty());
        reject(
            &view,
            "linked-main-denied",
            json!({"name": "policy"}),
            "not found",
        )
        .await?;
    }
    Ok(())
}

async fn observe_management(root: &Path) -> anyhow::Result<()> {
    let skills = root.join(".agents/skills");
    prepare_source(&skills)?;
    write_skill(&skills, "owned")?;
    let registry = SkillRegistry::new();
    let _registration = register(
        &registry,
        "manage-project",
        &skills,
        SkillSourceKind::Project,
    )?;
    let catalog = Arc::new(registry.discover(request(root)).await?);
    let list = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::List);
    let view = ThreadSkillTool::new(catalog.discovery_sources(), ThreadSkillKind::View);
    let workspace = ToolWorkspace::new(AgentWorkspace::local(root));
    let manage = ThreadSkillManageTool::new(catalog.clone(), workspace);
    invoke(&manage, "manage-create", json!({"action": "create", "name": "created", "content": document("created", "", "created through skill_manage")})).await?;
    let created = invoke(
        &view,
        "manage-created-immediately-viewable",
        json!({"name": "created"}),
    )
    .await?;
    ensure!(
        created["content"]
            .as_str()
            .is_some_and(|content| content.contains("created through skill_manage"))
    );
    ensure!(
        skill_names(&invoke(&list, "manage-created-immediately-listed", json!({})).await?)?
            == ["created", "owned"]
    );
    // Refreshing read tools does not expand the prepared management target catalog.
    reject(&manage, "manage-target-remains-prepared", json!({"action": "edit", "name": "created", "content": document("created", "", "unexpected edit")}), "not found").await?;
    invoke(
        &manage,
        "manage-delete-prepared",
        json!({"action": "delete", "name": "owned"}),
    )
    .await?;
    ensure!(
        skill_names(&invoke(&list, "manage-delete-immediately-listed", json!({})).await?)?
            == ["created"]
    );
    let readonly = AgentWorkspace::directory(root, Some(Vec::new()));
    let readonly_manage = ThreadSkillManageTool::new(catalog, ToolWorkspace::new(readonly));
    reject(&readonly_manage, "manage-write-boundary", json!({"action": "create", "name": "denied", "content": document("denied", "", "must not be written")}), "writable").await?;
    ensure!(!skills.join("denied").exists());
    Ok(())
}

fn request(root: &Path) -> SkillProviderRequest {
    SkillProviderRequest {
        workspace_root: root.to_owned(),
        config: SkillsConfig::default(),
        system_dir: None,
        cancellation: CancellationToken::new(),
    }
}

fn register(
    registry: &SkillRegistry,
    id: &str,
    root: &Path,
    source: SkillSourceKind,
) -> anyhow::Result<SkillProviderRegistration> {
    Ok(
        registry.register(Arc::new(FileSystemSkillProvider::from_directories(
            id,
            vec![SkillDirectorySource::new(root, source)],
        )?))?,
    )
}

fn prepare_source(root: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(root)?;
    fs::write(root.join(".ignore"), "!**\n")?;
    Ok(())
}

fn write_skill(root: &Path, name: &str) -> anyhow::Result<()> {
    write_document(root, name, "", &format!("# {name}"))
}

fn document(name: &str, extra: &str, body: &str) -> String {
    format!("---\nname: {name}\ndescription: Observation skill.\n{extra}---\n\n{body}\n")
}

fn write_document(root: &Path, name: &str, extra: &str, body: &str) -> anyhow::Result<()> {
    fs::create_dir_all(root.join(name))?;
    fs::write(
        root.join(name).join("SKILL.md"),
        document(name, extra, body),
    )?;
    Ok(())
}

fn skill_names(value: &Value) -> anyhow::Result<Vec<&str>> {
    value["skills"]
        .as_array()
        .context("list skills")?
        .iter()
        .map(|row| row["name"].as_str().context("skill name"))
        .collect()
}

async fn reject(tool: &impl Tool, label: &str, input: Value, expected: &str) -> anyhow::Result<()> {
    let error = invoke(tool, label, input)
        .await
        .err()
        .context("operation unexpectedly succeeded")?;
    ensure!(
        error.to_string().contains(expected),
        "unexpected failure for {label}: {error:#}"
    );
    Ok(())
}

async fn invoke(tool: &impl Tool, label: &str, input: Value) -> anyhow::Result<Value> {
    invoke_with_cancellation(tool, label, input, CancellationToken::new()).await
}

async fn invoke_with_cancellation(
    tool: &impl Tool,
    label: &str,
    input: Value,
    cancellation: CancellationToken,
) -> anyhow::Result<Value> {
    let context = CallContext {
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
        thread_id: "skill-observation".into(),
        turn_id: "same-turn".into(),
        call_id: label.into(),
        cancellation,
        extensions: Default::default(),
        catalog: Arc::from(Vec::new()),
        extension_sequence: 0,
    };
    let result = tool
        .execute(
            OpaquePayload::new("application/json", 1, input.to_string())?,
            context,
        )
        .await;
    match result {
        Ok(output) => {
            let value: Value = serde_json::from_str(output.payload().content())?;
            println!("{}", json!({"step": label, "result": value}));
            Ok(value)
        }
        Err(error) => {
            println!("{}", json!({"step": label, "error": error.to_string()}));
            Err(error.into())
        }
    }
}
