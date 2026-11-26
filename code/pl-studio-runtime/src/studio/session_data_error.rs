use pl_core::model::ModelError;

/// Session data failures retain their stage and original cause independently of workspace checks.
#[derive(Debug, thiserror::Error)]
pub(crate) enum SessionDataError {
    #[error("Could not load the saved conversation checkpoint")]
    Load(#[source] anyhow::Error),
    #[error("Could not prepare saved model data in the conversation checkpoint")]
    Model(#[source] anyhow::Error),
    #[error("Could not decode the saved model route in the conversation checkpoint")]
    ModelRoute(#[source] anyhow::Error),
    #[error(
        "Could not recover the saved prepared request (pl.model.prepared-request revision {revision})"
    )]
    PreparedRequest {
        revision: u32,
        #[source]
        source: ModelError,
    },
    #[error("Could not decode the saved plan (pl.studio.plan revision {revision})")]
    Plan {
        revision: u32,
        #[source]
        source: anyhow::Error,
    },
    #[error("Could not decode the saved workspace binding ({format} revision {revision})")]
    WorkspaceBinding {
        format: &'static str,
        revision: u32,
        #[source]
        source: anyhow::Error,
    },
    #[error("Could not load or save the conversation preparation record")]
    PreparationStorage(#[source] anyhow::Error),
    #[error("Could not load or save the frozen workspace identity")]
    WorkspaceIdentityStorage(#[source] anyhow::Error),
    #[error("Could not persist the saved worktree lease")]
    LeasePersistence(#[source] crate::PureError),
}

impl SessionDataError {
    /// The innermost saved-data phase identifies the operation that failed.
    pub(crate) fn find(error: &anyhow::Error) -> Option<&Self> {
        error
            .chain()
            .filter_map(|cause| cause.downcast_ref())
            .last()
    }

    pub(crate) fn retryable(&self) -> bool {
        match self {
            Self::LeasePersistence(_) => true,
            Self::Load(source) => source.is::<std::io::Error>(),
            Self::PreparationStorage(source) | Self::WorkspaceIdentityStorage(source) => {
                source.chain().any(|cause| cause.is::<sea_orm::DbErr>())
            }
            _ => false,
        }
    }
}
