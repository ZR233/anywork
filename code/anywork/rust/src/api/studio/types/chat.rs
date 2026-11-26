//! Typed Plan head used by Thread snapshots.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentPlanHead {
    pub revision: u64,
    pub phase: super::BridgePlanPhase,
    pub document: Option<super::BridgeCurrentContentRef>,
}
