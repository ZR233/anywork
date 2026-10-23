//! The original immutable builtin AccountCatalog captured once by the runtime builder.
use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};

use pl_protocol::AccountCatalogSnapshot;
use pl_protocol::products::identity::{ProductCollectionRef, ProductEntityRef, ProductReadOrigin};
use pl_protocol::products::references::AccountTemplatesReadRef;
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::super::read_budget::count;

pub(super) struct TemplatesMaterial {
    pub(super) reference: AccountTemplatesReadRef,
    pub(super) collection: ProductCollectionRef,
    pub(super) entities: Vec<ProductEntityRef>,
    pub(super) value: AccountCatalogSnapshot,
}

pub(in crate::studio::runtime) struct TemplatesSource {
    origin: ProductReadOrigin,
    sealed: AtomicBool,
    stop: tokio_util::sync::CancellationToken,
    current: Mutex<Option<Arc<TemplatesMaterial>>>,
}

impl TemplatesSource {
    pub(in crate::studio::runtime) fn new(origin: ProductReadOrigin, value: AccountCatalogSnapshot) -> Result<Arc<Self>, StudioError> {
        let mut entities = Vec::with_capacity(value.templates.len());
        for index in 0..value.templates.len() {
            let entry = count(index)?.checked_add(3).ok_or_else(|| StudioError::new(
                StudioErrorCode::Overloaded, "Account template identity space is exhausted", false))?;
            entities.push(ProductEntityRef { entry, revision: 1 });
        }
        let material = TemplatesMaterial { reference: AccountTemplatesReadRef { entry: 1, revision: 1 },
            collection: ProductCollectionRef { entry: 2, revision: 1, total: count(entities.len())? },
            entities, value };
        Ok(Arc::new(Self { origin, sealed: AtomicBool::new(false),
            stop: tokio_util::sync::CancellationToken::new(), current: Mutex::new(Some(Arc::new(material))) }))
    }

    pub(super) fn origin(&self) -> &ProductReadOrigin { &self.origin }

    /// The immutable baseline and its retained close notification are captured together. A token
    /// remembers an earlier cancellation; a later seal reaches this registered child as well.
    pub(super) fn observe(&self) -> Result<(Arc<TemplatesMaterial>, tokio_util::sync::CancellationToken), StudioError> {
        self.ensure_open()?;
        let material = self.current.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        let stop = self.stop.child_token();
        self.ensure_open()?;
        Ok((material.as_ref().ok_or_else(cancelled)?.clone(), stop))
    }

    pub(super) fn pin(&self, origin: &ProductReadOrigin, reference: AccountTemplatesReadRef)
        -> Result<Arc<TemplatesMaterial>, StudioError> {
        self.ensure_open()?;
        if origin != &self.origin { return Err(cancelled()); }
        let material = self.current.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        let material = material.as_ref().ok_or_else(cancelled)?;
        if material.reference != reference {
            return Err(StudioError::new(StudioErrorCode::Unavailable,
                "The requested AccountTemplates value was not published by this source", false));
        }
        Ok(material.clone())
    }

    pub(in crate::studio::runtime) fn seal(&self) {
        self.sealed.store(true, Ordering::Release);
        self.stop.cancel();
    }

    pub(in crate::studio::runtime) fn finish_close(&self) {
        self.seal();
        let material = self.current.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
        drop(material);
    }

    fn ensure_open(&self) -> Result<(), StudioError> {
        if self.sealed.load(Ordering::Acquire) { Err(cancelled()) } else { Ok(()) }
    }
}

fn cancelled() -> StudioError {
    StudioError::new(StudioErrorCode::Cancelled, "The AccountTemplates source is closing or replaced", false)
}
