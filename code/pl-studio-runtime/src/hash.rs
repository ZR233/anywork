pub(crate) fn merge_costs(
    target: &mut Vec<pl_protocol::RuntimeCostAmount>,
    incoming: &[pl_protocol::RuntimeCostAmount],
) {
    for cost in incoming {
        if let Some(current) = target
            .iter_mut()
            .find(|current| current.currency == cost.currency)
        {
            current.amount += cost.amount;
        } else {
            target.push(cost.clone());
        }
    }
    target.sort_by(|left, right| left.currency.cmp(&right.currency));
}
