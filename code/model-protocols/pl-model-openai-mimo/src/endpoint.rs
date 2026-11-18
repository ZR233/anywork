use pl_model_openai_wire::protocol::*;

pub const ID: ProtocolId = ProtocolId::from_static("mi_mo");

pub fn endpoint(name: impl Into<String>, base_url: impl Into<String>) -> ProtocolEndpoint {
    ProtocolEndpoint::new(ID, name, base_url)
}
