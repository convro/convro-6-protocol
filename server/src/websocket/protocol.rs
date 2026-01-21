use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// WebSocket message types (matches API spec)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WsMessageType {
    /// Server hello on connection
    Hello {
        server_version: String,
    },

    /// Client authentication
    Authenticate {
        access_token: String,
    },

    /// Server authentication response
    Authenticated {
        user_id: Uuid,
        convro_number: String,
        connection_id: String,
    },

    /// Heartbeat ping (client → server)
    Ping {
        timestamp: chrono::DateTime<chrono::Utc>,
    },

    /// Heartbeat pong (server → client)
    Pong {
        timestamp: chrono::DateTime<chrono::Utc>,
    },

    /// New message delivery (server → client)
    Message {
        message_id: Uuid,
        from_convro_number: String,
        to_convro_number: String,
        message_type: String,
        session_id: Option<String>,
        encrypted_blob: String,
        created_at: chrono::DateTime<chrono::Utc>,
    },

    /// Message acknowledgment (client → server)
    Ack {
        message_id: Uuid,
    },

    /// Typing indicator (bidirectional)
    Typing {
        from_convro_number: Option<String>, // Set by server
        to_convro_number: String,
        session_id: String,
        is_typing: bool,
    },

    /// Presence update (server → client)
    Presence {
        convro_number: String,
        status: String, // "online", "offline", "away"
        timestamp: chrono::DateTime<chrono::Utc>,
    },

    /// Error (server → client)
    Error {
        error_code: String,
        message: String,
        timestamp: chrono::DateTime<chrono::Utc>,
    },

    /// Disconnect (bidirectional)
    Disconnect {
        reason: String,
    },

    /// Goodbye (server → client)
    Goodbye {
        message: String,
    },
}

/// WebSocket message wrapper
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsMessage {
    #[serde(flatten)]
    pub message_type: WsMessageType,
}

impl WsMessage {
    pub fn hello() -> Self {
        Self {
            message_type: WsMessageType::Hello {
                server_version: "1.0.0".to_string(),
            },
        }
    }

    pub fn authenticated(user_id: Uuid, convro_number: String, connection_id: String) -> Self {
        Self {
            message_type: WsMessageType::Authenticated {
                user_id,
                convro_number,
                connection_id,
            },
        }
    }

    pub fn pong() -> Self {
        Self {
            message_type: WsMessageType::Pong {
                timestamp: chrono::Utc::now(),
            },
        }
    }

    pub fn error(error_code: String, message: String) -> Self {
        Self {
            message_type: WsMessageType::Error {
                error_code,
                message,
                timestamp: chrono::Utc::now(),
            },
        }
    }

    pub fn goodbye(message: String) -> Self {
        Self {
            message_type: WsMessageType::Goodbye { message },
        }
    }

    /// Convert to JSON string
    pub fn to_json(&self) -> serde_json::Result<String> {
        serde_json::to_string(&self)
    }

    /// Parse from JSON string
    pub fn from_json(json: &str) -> serde_json::Result<Self> {
        serde_json::from_str(json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_serialize_hello() {
        let msg = WsMessage::hello();
        let json = msg.to_json().unwrap();
        assert!(json.contains("\"type\":\"hello\""));
        assert!(json.contains("\"server_version\":\"1.0.0\""));
    }

    #[test]
    fn test_deserialize_ping() {
        let json = r#"{"type":"ping","timestamp":"2026-01-12T12:00:00Z"}"#;
        let msg = WsMessage::from_json(json).unwrap();
        matches!(msg.message_type, WsMessageType::Ping { .. });
    }

    #[test]
    fn test_deserialize_authenticate() {
        let json = r#"{"type":"authenticate","access_token":"test_token"}"#;
        let msg = WsMessage::from_json(json).unwrap();
        if let WsMessageType::Authenticate { access_token } = msg.message_type {
            assert_eq!(access_token, "test_token");
        } else {
            panic!("Wrong message type");
        }
    }
}
