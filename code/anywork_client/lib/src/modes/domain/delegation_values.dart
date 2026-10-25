/// Root creation freezes these independently of Thread Mode and workspace mode.
/// A child keeps its dispatched values; Profile edits cannot change that route.
enum DelegationMode { profile, automatic }

enum DelegationPreference { economy, balanced, fast }
