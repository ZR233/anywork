use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, KeyInit, Mac};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use sha2::Sha256;

use super::{
    HistoryBusinessRowScope, HistoryCut, HistoryError, HistoryEventsQuery, Result,
};

const MAX_TOKEN_BYTES: usize = 64 * 1024;
const TOKEN_VERSION: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) enum Query {
    Events(HistoryEventsQuery),
    BusinessRows(HistoryBusinessRowScope),
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Claims<T> {
    version: u32,
    database: String,
    reader: String,
    pub value: T,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) enum Token {
    Cut {
        through: u64,
    },
    TimelinePage {
        cut: HistoryCut,
        upper_seq: u64,
        upper_divider_seq: Option<u64>,
    },
    WorkRangePage {
        cut: HistoryCut,
        after_seq: Option<u64>,
        before_seq: Option<u64>,
        after: u64,
    },
    Page {
        cut: HistoryCut,
        query: Query,
        before: u64,
    },
    Bodies {
        event_id: String,
        after: u64,
    },
}

pub(super) struct Codec {
    database: String,
    reader: String,
    secret: [u8; 32],
}

impl Codec {
    pub fn new(database: &str) -> Self {
        let mut secret = [0; 32];
        secret[..16].copy_from_slice(uuid::Uuid::new_v4().as_bytes());
        secret[16..].copy_from_slice(uuid::Uuid::new_v4().as_bytes());
        Self {
            database: database.into(),
            reader: uuid::Uuid::new_v4().to_string(),
            secret,
        }
    }

    fn mac(&self) -> Hmac<Sha256> {
        Hmac::<Sha256>::new_from_slice(&self.secret).expect("HMAC accepts a 32 byte key")
    }

    pub fn encode<T: Serialize>(&self, value: T) -> Result<String> {
        let data = serde_json::to_vec(&Claims {
            version: TOKEN_VERSION,
            database: self.database.clone(),
            reader: self.reader.clone(),
            value,
        })?;
        let mut mac = self.mac();
        mac.update(&data);
        let token = format!(
            "{}.{}",
            URL_SAFE_NO_PAD.encode(&data),
            URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes())
        );
        if token.len() > MAX_TOKEN_BYTES {
            return Err(HistoryError::InvalidDemand(
                "history cursor identity exceeds its bounded encoding".into(),
            ));
        }
        Ok(token)
    }

    pub fn decode<T: DeserializeOwned>(&self, token: &str) -> Result<T> {
        if token.len() > MAX_TOKEN_BYTES {
            return Err(HistoryError::InvalidCursor);
        }
        let (data, signature) = token.split_once('.').ok_or(HistoryError::InvalidCursor)?;
        let data = URL_SAFE_NO_PAD
            .decode(data)
            .map_err(|_| HistoryError::InvalidCursor)?;
        let signature = URL_SAFE_NO_PAD
            .decode(signature)
            .map_err(|_| HistoryError::InvalidCursor)?;
        let mut mac = self.mac();
        mac.update(&data);
        mac.verify_slice(&signature)
            .map_err(|_| HistoryError::InvalidCursor)?;
        let claims: Claims<T> =
            serde_json::from_slice(&data).map_err(|_| HistoryError::InvalidCursor)?;
        if claims.version != TOKEN_VERSION
            || claims.database != self.database
            || claims.reader != self.reader
        {
            return Err(HistoryError::InvalidCursor);
        }
        Ok(claims.value)
    }

    pub fn cut(&self, through: u64) -> Result<HistoryCut> {
        Ok(HistoryCut {
            token: self.encode(Token::Cut { through })?,
        })
    }

    pub fn through(&self, cut: &HistoryCut) -> Result<u64> {
        match self.decode(&cut.token)? {
            Token::Cut { through } => Ok(through),
            _ => Err(HistoryError::InvalidCursor),
        }
    }
}
