//! Resource errors retain their underlying source across the product boundary.
pub(super) fn resource_error(
    operation: &'static str,
    source: impl Into<anyhow::Error>,
) -> crate::thread_assembler::ThreadAssemblyError {
    crate::thread_assembler::ThreadAssemblyError::Resource {
        operation,
        // anyhow's allocation-preserving Into<Box<dyn Error>> hides the original root type.
        // Reallocate through its official conversion so typed boundary classification survives.
        source: source
            .into()
            .reallocate_into_boxed_dyn_error_without_backtrace(),
    }
}
