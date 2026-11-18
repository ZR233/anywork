pub fn valid_discovery_transport(
    profile: &crate::model::ModelTransportProfile,
    expected: &crate::model::ModelTransportProfile,
) -> bool {
    profile.protocol == expected.protocol
        && profile.default_connection_mode == expected.default_connection_mode
        && profile
            .supported_connection_modes
            .contains(&profile.default_connection_mode)
        && profile
            .supported_connection_modes
            .iter()
            .enumerate()
            .all(|(index, mode)| {
                expected.supported_connection_modes.contains(mode)
                    && !profile.supported_connection_modes[..index].contains(mode)
            })
}
