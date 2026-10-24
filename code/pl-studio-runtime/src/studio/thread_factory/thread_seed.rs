//! Creation-only instruction capture using the already selected physical workspace services.
use super::{errors::resource_error, thread_tools::PreparedThreadTools};
use crate::{
    agent::definition::ResolvedAgentDefinition,
    instruction::{InstructionAssembler, InstructionAssemblyRequest, ModeInstructionProfile},
    thread_assembler::ThreadAssemblyError,
};
use pl_core::context::{ContextRecord, OpaquePayload};
use std::path::Path;

/// One Thread's resolved identity plus its optional Mode execution instructions.
///
/// The seed never selects a role: root callers pass the built-in definition or the frozen child
/// Profile definition, and the Mode profile is a separate input that later Mode updates own.
pub(super) struct ThreadInstructionSeed<'a> {
    pub thread_id: &'a str,
    pub config: &'a crate::config::StudioConfig,
    pub model: &'a pl_model::model::ModelInfo,
    pub root: &'a Path,
    pub agent: &'a ResolvedAgentDefinition,
    pub mode: Option<ModeInstructionProfile<'a>>,
    pub delegation: Option<pl_protocol::DelegationSettings>,
    pub resources: &'a PreparedThreadTools,
}

pub(super) async fn capture(
    seed: ThreadInstructionSeed<'_>,
) -> Result<(Vec<ContextRecord>, OpaquePayload), ThreadAssemblyError> {
    let config = seed.config.instructions.clone();
    let root = seed.root.to_owned();
    let documents = match &seed.resources.remote {
        Some(host) => {
            pl_tool::remote::load_remote_workspace_instructions(
                &host.files,
                config.project_doc_max_bytes,
                &config.project_doc_fallback_filenames,
            )
            .await?
        }
        None => {
            let config = config.clone();
            let root = root.clone();
            tokio::task::spawn_blocking(move || {
                pl_tool::workspace::load_workspace_instruction_documents(
                    &root,
                    &root,
                    config.project_doc_max_bytes,
                    &config.project_doc_fallback_filenames,
                )
            })
            .await?
            .map_err(|error| resource_error("read workspace instruction documents", error))?
        }
    };
    let model = seed.model.clone();
    let agent = seed.agent.clone();
    let mode = seed
        .mode
        .map(|mode| (mode.label.to_owned(), mode.instructions.to_owned()));
    let environment = seed.resources.environment.clone();
    let catalog = seed.resources.catalog.clone();
    let skills = seed.config.skills.clone();
    let snapshot = tokio::task::spawn_blocking(move || {
        let mode = mode
            .as_ref()
            .map(|(label, instructions)| ModeInstructionProfile {
                label,
                instructions,
            });
        InstructionAssembler::assemble(InstructionAssemblyRequest {
            instructions: Some(&config),
            skills: catalog.as_ref().map(|_| &skills),
            skill_catalog: catalog.as_ref().map(|catalog| catalog.snapshot()),
            agent: &agent,
            mode,
            model: &model,
            workspace_root: &root,
            current_dir: &root,
            workspace_documents: Some(&documents),
            workspace_instructions: None,
            subagent_constraint: None,
            skill_suggestions: None,
            execution_environment: Some(&environment),
            delegation_preference: seed
                .delegation
                .and_then(crate::studio::delegation::preference_prompt),
        })
    })
    .await??;
    let payload = crate::instruction::encode_snapshot(&snapshot)
        .map_err(|error| resource_error("freeze instruction sources", error))?;
    let records = snapshot.context_records(seed.thread_id);
    Ok((records, payload))
}
