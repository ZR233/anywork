//! Update acquisition and the verified installer's process lifecycle.

use futures::future::BoxFuture;
use pl_studio_update::{
    PreparedStudioUpdate, STUDIO_VERSION, StudioUpdate, StudioUpdateCancellation,
    StudioUpdateCheck, StudioUpdateError, StudioUpdateEvent, StudioUpdater,
};
use tokio::sync::mpsc::UnboundedSender;

pub(super) trait UpdateIo: Send + Sync {
    fn check(&self) -> BoxFuture<'_, Result<StudioUpdateCheck, StudioUpdateError>>;

    fn download(
        &self,
        update: StudioUpdate,
        events: UnboundedSender<StudioUpdateEvent>,
        cancellation: StudioUpdateCancellation,
    ) -> BoxFuture<'_, Result<InstallerLease, StudioUpdateError>>;
}

pub(super) type InstallerLease = Box<dyn UpdateInstaller>;

pub(super) trait UpdateInstaller: Send {
    fn launch(&mut self) -> BoxFuture<'_, Result<(), StudioUpdateError>>;

    fn abort_install(&mut self) -> BoxFuture<'_, Result<(), StudioUpdateError>>;

    fn prepare_install<'a>(
        &'a mut self,
        cancellation: &'a StudioUpdateCancellation,
    ) -> BoxFuture<'a, Result<(), StudioUpdateError>>;
}

impl UpdateIo for StudioUpdater {
    fn check(&self) -> BoxFuture<'_, Result<StudioUpdateCheck, StudioUpdateError>> {
        Box::pin(self.check(STUDIO_VERSION.trim()))
    }

    fn download(
        &self,
        update: StudioUpdate,
        events: UnboundedSender<StudioUpdateEvent>,
        cancellation: StudioUpdateCancellation,
    ) -> BoxFuture<'_, Result<InstallerLease, StudioUpdateError>> {
        Box::pin(async move {
            let prepared = self.download(update, events, cancellation).await?;
            Ok(Box::new(prepared) as InstallerLease)
        })
    }
}

impl UpdateInstaller for PreparedStudioUpdate {
    fn launch(&mut self) -> BoxFuture<'_, Result<(), StudioUpdateError>> {
        Box::pin(self.launch())
    }

    fn abort_install(&mut self) -> BoxFuture<'_, Result<(), StudioUpdateError>> {
        Box::pin(self.abort_install())
    }

    fn prepare_install<'a>(
        &'a mut self,
        cancellation: &'a StudioUpdateCancellation,
    ) -> BoxFuture<'a, Result<(), StudioUpdateError>> {
        Box::pin(self.prepare_install(cancellation))
    }
}
