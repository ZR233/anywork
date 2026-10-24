//! Agent/Mode instruction sources, unified assembly, and model-context projection.
//!
//! Agent definitions and Mode instructions are recorded as separate sources inside one frozen
//! snapshot. Current readers only accept the current structure; `migration` is the single boundary
//! that interprets obsolete payloads during recovery.

mod assembler;
mod migration;
mod snapshot;
mod structure;
mod types;

pub use assembler::InstructionAssembler;
pub(crate) use migration::{migrate_saved_representation, saved_mode_instruction};
pub(crate) use snapshot::{decode_snapshot, encode_snapshot};
pub(crate) use types::current_instruction_context;
pub use types::{
    InstructionAssemblyRequest, InstructionBlock, InstructionSnapshot, InstructionSource,
    InstructionSourceKind, ModeInstructionProfile,
};
pub(crate) use types::{SNAPSHOT_FORMAT, SNAPSHOT_VERSION};
