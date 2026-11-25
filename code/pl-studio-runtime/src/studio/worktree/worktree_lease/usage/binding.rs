//! Binding publication waits for its exact write ACK, then rechecks admission.
use super::super::{WorktreeLease, WorktreeLeaseState};
use super::{
    UsagePurpose, UsageTarget, VerifiedBindingWrite, WorkspaceEndpoint, WorkspaceUsageLease,
    WorktreeLeaseOwner, lock_state,
};
use anyhow::{Context, Result, ensure};
use std::sync::{Arc, Weak};

impl WorktreeLeaseOwner {
    /// Confirms exactly the binding physically verified by the factory, while its real
    /// preparation use still protects it. Even an unchanged Active lease waits for its own ACK.
    pub(in crate::studio) fn prepare_verified_binding(
        &self,
        expected: &WorktreeLease,
        usage: &WorkspaceUsageLease,
    ) -> Result<VerifiedBindingWrite> {
        expected.validate_identity()?;
        ensure!(
            Weak::ptr_eq(&usage.0.state, &Arc::downgrade(&self.state)),
            "workspace use belongs to another runtime owner"
        );
        let (confirmed, ticket, identity) = {
            let mut state = lock_state(&self.state);
            let entry = state
                .workspace
                .active
                .get(&usage.0.serial)
                .context("workspace preparer is no longer registered")?;
            ensure!(
                entry.owner == expected.owner_thread_id && entry.purpose == UsagePurpose::Execution,
                "verified worktree does not belong to this execution use"
            );
            let UsageTarget::Assigned(identity) = &entry.target else {
                anyhow::bail!("verified worktree requires an assigned execution workspace");
            };
            ensure!(
                identity.matches_root(&expected.path)
                    && matches!(
                        (&identity.endpoint, &expected.ssh_alias),
                        (WorkspaceEndpoint::Local, None) | (WorkspaceEndpoint::Ssh { .. }, Some(_))
                    ),
                "verified worktree differs from the assigned workspace"
            );
            ensure!(
                !state.workspace.is_retiring(&expected.owner_thread_id)
                    && state.workspace.sealing_owners(identity).next().is_none(),
                "verified worktree is sealed for retirement or removal"
            );
            ensure!(
                state
                    .entries
                    .get(&expected.owner_thread_id)
                    .is_some_and(|entry| entry.lease == *expected),
                "verified worktree binding or revision changed"
            );
            ensure!(
                matches!(
                    expected.state,
                    WorktreeLeaseState::Prepared
                        | WorktreeLeaseState::Preserved
                        | WorktreeLeaseState::Active
                ),
                "cleaned or cleanup-requested worktree cannot be confirmed"
            );
            let mut confirmed = expected.clone();
            if confirmed.state != WorktreeLeaseState::Active {
                confirmed.revision = confirmed
                    .revision
                    .checked_add(1)
                    .context("worktree lease revision exhausted")?;
                confirmed.state = WorktreeLeaseState::Active;
            }
            let identity = identity.clone();
            let ticket = self.record_ticket_locked(&mut state, confirmed.clone())?;
            (confirmed, ticket, identity)
        };
        Ok(VerifiedBindingWrite {
            confirmed,
            ticket,
            identity,
        })
    }

    pub(in crate::studio) async fn confirm_prepared_binding(
        &self,
        write: VerifiedBindingWrite,
    ) -> Result<WorktreeLease> {
        let VerifiedBindingWrite {
            confirmed,
            ticket,
            identity,
        } = write;
        self.writer.flush_through(ticket).await?;
        // A real ACK cannot revoke retirement/removal or a newer binding admitted while
        // this waiter yielded. Do not return a usable proof of that stale generation.
        let state = lock_state(&self.state);
        ensure!(
            state
                .entries
                .get(&confirmed.owner_thread_id)
                .is_some_and(|entry| entry.lease == confirmed),
            "verified worktree binding or revision changed while awaiting durability"
        );
        ensure!(
            !state.workspace.is_retiring(&confirmed.owner_thread_id)
                && state.workspace.sealing_owners(&identity).next().is_none(),
            "verified worktree was sealed for retirement or removal while awaiting durability"
        );
        Ok(confirmed)
    }

    #[cfg(test)]
    pub(in crate::studio) async fn confirm_verified_binding(
        &self,
        expected: &WorktreeLease,
        usage: &WorkspaceUsageLease,
    ) -> Result<WorktreeLease> {
        let write = self.prepare_verified_binding(expected, usage)?;
        self.confirm_prepared_binding(write).await
    }
}
