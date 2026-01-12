use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use super::protocol::WsMessage;

/// WebSocket hub handle (shared across application)
pub type HubHandle = Arc<Hub>;

/// WebSocket connection hub
///
/// Manages active WebSocket connections for realtime message delivery.
/// This is a simplified implementation - production would use more sophisticated
/// connection management (tokio channels, connection pooling, etc.)
pub struct Hub {
    /// Active connections: user_id → connection_id
    connections: Arc<RwLock<HashMap<Uuid, String>>>,
}

impl Hub {
    /// Create new hub
    pub fn new() -> HubHandle {
        Arc::new(Self {
            connections: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    /// Register new connection
    pub async fn register(&self, user_id: Uuid, connection_id: String) {
        self.connections.write().await.insert(user_id, connection_id.clone());
        tracing::info!("WebSocket connection registered: user={}, conn={}", user_id, connection_id);
    }

    /// Unregister connection
    pub async fn unregister(&self, user_id: &Uuid) {
        if let Some(connection_id) = self.connections.write().await.remove(user_id) {
            tracing::info!("WebSocket connection unregistered: user={}, conn={}", user_id, connection_id);
        }
    }

    /// Check if user is connected
    pub async fn is_connected(&self, user_id: &Uuid) -> bool {
        self.connections.read().await.contains_key(user_id)
    }

    /// Get connection count
    pub async fn connection_count(&self) -> usize {
        self.connections.read().await.len()
    }

    /// Send message to user (if online)
    ///
    /// In a real implementation, this would:
    /// 1. Look up the WebSocket connection for the user
    /// 2. Send the message over the WebSocket
    /// 3. Return success/failure
    ///
    /// For now, this is a stub that logs the action.
    pub async fn send_to_user(&self, user_id: &Uuid, message: WsMessage) -> Result<(), HubError> {
        if let Some(connection_id) = self.connections.read().await.get(user_id) {
            tracing::debug!(
                "Would send message to user {} (conn: {}): {:?}",
                user_id,
                connection_id,
                message
            );
            // TODO: Actually send message over WebSocket
            Ok(())
        } else {
            Err(HubError::UserOffline(*user_id))
        }
    }

    /// Broadcast message to all connected users
    pub async fn broadcast(&self, message: WsMessage) {
        let count = self.connections.read().await.len();
        tracing::debug!("Would broadcast message to {} users: {:?}", count, message);
        // TODO: Actually broadcast message
    }

    /// Get list of online users
    pub async fn online_users(&self) -> Vec<Uuid> {
        self.connections.read().await.keys().copied().collect()
    }
}

impl Default for Hub {
    fn default() -> Self {
        Self {
            connections: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

/// Hub errors
#[derive(Debug, thiserror::Error)]
pub enum HubError {
    #[error("User {0} is offline")]
    UserOffline(Uuid),

    #[error("Connection {0} not found")]
    ConnectionNotFound(String),

    #[error("Failed to send message: {0}")]
    SendError(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_register_and_unregister() {
        let hub = Hub::new();
        let user_id = Uuid::new_v4();
        let connection_id = "conn_123".to_string();

        // Register
        hub.register(user_id, connection_id.clone()).await;
        assert!(hub.is_connected(&user_id).await);
        assert_eq!(hub.connection_count().await, 1);

        // Unregister
        hub.unregister(&user_id).await;
        assert!(!hub.is_connected(&user_id).await);
        assert_eq!(hub.connection_count().await, 0);
    }

    #[tokio::test]
    async fn test_multiple_connections() {
        let hub = Hub::new();
        let user1 = Uuid::new_v4();
        let user2 = Uuid::new_v4();

        hub.register(user1, "conn_1".to_string()).await;
        hub.register(user2, "conn_2".to_string()).await;

        assert_eq!(hub.connection_count().await, 2);
        assert!(hub.is_connected(&user1).await);
        assert!(hub.is_connected(&user2).await);

        let online = hub.online_users().await;
        assert_eq!(online.len(), 2);
        assert!(online.contains(&user1));
        assert!(online.contains(&user2));
    }

    #[tokio::test]
    async fn test_send_to_offline_user() {
        let hub = Hub::new();
        let user_id = Uuid::new_v4();
        let message = WsMessage::hello();

        let result = hub.send_to_user(&user_id, message).await;
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), HubError::UserOffline(_)));
    }
}
