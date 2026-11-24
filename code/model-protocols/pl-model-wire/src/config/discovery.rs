/// 目录声明的在线探测能力；未声明时该 catalog 保持静态或显式语义。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelCatalogDiscovery {
    pub transport: crate::model::ModelTransportProfile,
}
