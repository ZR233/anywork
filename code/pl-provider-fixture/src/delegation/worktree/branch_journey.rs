//! One synthetic business branch proves that mutable checkout state is not ownership.
use super::*;

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
enum Action {
    Create,
    Rename,
    Detach,
    Attach,
}

#[derive(Serialize)]
struct Parameters<'a> {
    action: Action,
    expected: &'a Git,
    created: &'a str,
    renamed: &'a str,
}

const SCRIPT: &str = r#"
target = params['expected']['path']
assert target != root
assert snapshot(target, []) == params['expected'], 'business checkout changed before the explicit operation'
assert (Path(target) / 'fixture-base.txt').is_file()
assert (Path(target) / '.gitignore').read_text().strip() == '.anywork/'
if params['action'] == 'create':
    assert params['expected']['detached'] and params['expected']['branch'] is None
    git('switch','--quiet','-c',params['created'],cwd=target)
elif params['action'] == 'rename':
    assert params['expected']['branch'] == params['created']
    git('branch','-m',params['renamed'],cwd=target)
elif params['action'] == 'detach':
    assert params['expected']['branch'] == params['renamed']
    git('switch','--quiet','--detach',params['expected']['head'],cwd=target)
else:
    assert params['action'] == 'attach' and params['expected']['detached']
    git('switch','--quiet',params['renamed'],cwd=target)
print(json.dumps(snapshot(target, []), sort_keys=True))
"#;

fn names(child: &Child) -> (String, String) {
    let suffix: String = super::super::input_digest(&child.spawn.agent_id)
        .chars()
        .take(16)
        .collect();
    let created = format!("fixture-business-{suffix}");
    let renamed = format!("{created}-renamed");
    (created, renamed)
}

pub(super) fn create(flow: &Flow<'_>, child: &mut Child) -> Progress<()> {
    require(
        child.spawn.profile_id == "worktree_executor"
            && child.checkout_history.is_empty()
            && child.git.detached
            && child.git.branch.is_none(),
        "business branch journey must start at the actual newly detached owned child",
    )?;
    record(flow, "business-create", child, Action::Create)
}

pub(super) fn finish(flow: &Flow<'_>, child: &mut Child) -> Progress<()> {
    record(flow, "business-rename", child, Action::Rename)?;
    record(flow, "business-detach", child, Action::Detach)?;
    // Closing while attached to a renamed business branch must not be judged
    // against the originally detached creation state.
    record(flow, "business-attach-for-close", child, Action::Attach)
}

fn record(flow: &Flow<'_>, label: &str, child: &mut Child, action: Action) -> Progress<()> {
    let (created, renamed) = names(child);
    let before = child.checkout();
    let after: Git = git::python(
        flow,
        label,
        &Parameters {
            action,
            expected: before,
            created: &created,
            renamed: &renamed,
        },
        SCRIPT,
    )?;
    let mut refs = before.refs.clone();
    let expected_branch = match action {
        Action::Create => {
            require(
                refs.insert(format!("refs/heads/{created}"), before.head.clone())
                    .is_none(),
                "synthetic business branch unexpectedly existed",
            )?;
            Some(created)
        }
        Action::Rename => {
            require(
                refs.remove(&format!("refs/heads/{created}")) == Some(before.head.clone())
                    && refs
                        .insert(format!("refs/heads/{renamed}"), before.head.clone())
                        .is_none(),
                "business rename did not name the exact synthetic source/new branch",
            )?;
            Some(renamed)
        }
        Action::Detach => None,
        Action::Attach => Some(renamed),
    };
    require(
        git::same_identity(&child.git, &after)
            && after.head == before.head
            && after.status.is_empty()
            && before.status.is_empty()
            && after.files == before.files
            && after.commit_file == before.commit_file
            && after.primary_path == before.primary_path
            && after.primary_head == before.primary_head
            && after.branch == expected_branch
            && after.detached == expected_branch.is_none()
            && after.refs == refs,
        "explicit business branch operation changed stable identity/data/HEAD or unexpected refs",
    )?;
    git::registered(&after, &after)?;
    child.checkout_history.push(after);
    Ok(())
}
