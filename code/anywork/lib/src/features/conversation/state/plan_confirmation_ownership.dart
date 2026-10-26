/// The producing tool owns plan semantics. A legacy ordinary question may
/// contain the reserved question ID; neither its ID nor its text makes a plan.
const String planSubmitToolName = 'plan_submit';

bool ownsPlanConfirmation(String? toolName) => toolName == planSubmitToolName;
