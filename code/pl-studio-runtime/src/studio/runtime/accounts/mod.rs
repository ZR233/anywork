//! Transport-neutral account reads, commands and bounded observations over the original owners.

mod observation;
mod projection;

pub use observation::AccountObservation;
pub use pl_protocol::studio::{
    AccountDomainFrame, AccountIdentity, AccountObservationTarget, CreateAccountRequest,
    PatchAccountRequest, SetAccountModelAutoCompactRequest, SetAccountModelConnectionRequest,
    SyncAccountModelsReply, SyncAccountModelsRequest,
};

use super::StudioRuntime;
use anyhow::Result;

impl StudioRuntime {
    /// Opens one independent display demand. Registration precedes every possible baseline read.
    /// No query, read, open or resynchronization contacts a provider or mutates settings.
    pub fn open_account_observation(
        &self,
        target: AccountObservationTarget,
    ) -> Result<AccountObservation> {
        observation::open(self.clone(), target)
    }

    /// Reads precisely one domain/target. A stamp can only satisfy that domain's observation barrier.
    pub fn read_account_domain(
        &self,
        target: &AccountObservationTarget,
    ) -> Result<AccountDomainFrame> {
        projection::read(self, target)
    }
}
