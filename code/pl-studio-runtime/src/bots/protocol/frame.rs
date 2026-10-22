//! pbbp2 Frame / Header。字段编号对照官方 `ws-client/proto-buf/pbbp2.js`：
//! Header.key=1, Header.value=2；Frame.SeqID=1, LogID=2, service=3, method=4,
//! headers=5, payloadEncoding=6, payloadType=7, payload=8, LogIDNew=9。

use prost::Message;

#[derive(Clone, PartialEq, Message)]
pub struct Pbbp2Header {
    #[prost(string, tag = "1")]
    pub key: String,
    #[prost(string, tag = "2")]
    pub value: String,
}

#[derive(Clone, PartialEq, Message)]
pub struct Pbbp2Frame {
    #[prost(uint64, tag = "1")]
    pub seq_id: u64,
    #[prost(uint64, tag = "2")]
    pub log_id: u64,
    #[prost(int32, tag = "3")]
    pub service: i32,
    #[prost(int32, tag = "4")]
    pub method: i32,
    #[prost(message, repeated, tag = "5")]
    pub headers: Vec<Pbbp2Header>,
    #[prost(string, optional, tag = "6")]
    pub payload_encoding: Option<String>,
    #[prost(string, optional, tag = "7")]
    pub payload_type: Option<String>,
    #[prost(bytes = "vec", optional, tag = "8")]
    pub payload: Option<Vec<u8>>,
    #[prost(string, optional, tag = "9")]
    pub log_id_new: Option<String>,
}

pub enum FrameType {
    Control = 0,
    Data = 1,
}

pub struct HeaderKey;

impl HeaderKey {
    pub const TYPE: &'static str = "type";
    pub const MESSAGE_ID: &'static str = "message_id";
    pub const SUM: &'static str = "sum";
    pub const SEQ: &'static str = "seq";
    pub const BIZ_RT: &'static str = "biz_rt";
    pub const HANDSHAKE_STATUS: &'static str = "handshake-status";
    pub const HANDSHAKE_MSG: &'static str = "handshake-msg";
    pub const HANDSHAKE_AUTHERRCODE: &'static str = "handshake-autherrcode";
}

pub struct MessageType;

impl MessageType {
    pub const EVENT: &'static str = "event";
    pub const PING: &'static str = "ping";
    pub const PONG: &'static str = "pong";
}

impl Pbbp2Frame {
    pub fn header(&self, key: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|header| header.key == key)
            .map(|header| header.value.as_str())
    }

    pub fn ping(service_id: i32) -> Self {
        Self {
            seq_id: 0,
            log_id: 0,
            service: service_id,
            method: FrameType::Control as i32,
            headers: vec![Pbbp2Header {
                key: HeaderKey::TYPE.to_string(),
                value: MessageType::PING.to_string(),
            }],
            payload_encoding: None,
            payload_type: None,
            payload: None,
            log_id_new: None,
        }
    }
}
