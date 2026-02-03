use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::Response,
    routing::get,
    Router,
};
use futures::{sink::SinkExt, stream::StreamExt};
use uuid::Uuid;

use crate::{
    utils::jwt,
    websocket::{HubHandle, WsMessage, WsMessageType},
};

/// Application state for WebSocket endpoints
#[derive(Clone)]
pub struct AppState {
    pub hub: HubHandle,
}

/// Create WebSocket router
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/stream", get(ws_handler))
        .with_state(state)
}

/// WebSocket upgrade handler
///
/// Handles the WebSocket upgrade and manages the connection lifecycle
async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> Response {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

/// Handle WebSocket connection
async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();

    // Send hello message
    let hello = WsMessage::hello();
    if let Ok(json) = hello.to_json() {
        if sender.send(Message::Text(json)).await.is_err() {
            tracing::error!("Failed to send hello message");
            return;
        }
    }

    let mut user_id: Option<Uuid> = None;
    let mut _connection_id: Option<String> = None;

    // Message handling loop
    while let Some(msg) = receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                // Parse WebSocket message
                let ws_msg = match WsMessage::from_json(&text) {
                    Ok(msg) => msg,
                    Err(e) => {
                        tracing::warn!("Failed to parse WebSocket message: {}", e);
                        let error = WsMessage::error(
                            "INVALID_MESSAGE".to_string(),
                            format!("Failed to parse message: {}", e),
                        );
                        if let Ok(json) = error.to_json() {
                            let _ = sender.send(Message::Text(json)).await;
                        }
                        continue;
                    }
                };

                // Handle message based on type
                match ws_msg.message_type {
                    WsMessageType::Authenticate { access_token } => {
                        // Decode JWT
                        match jwt::decode_token(&access_token) {
                            Ok(claims) => {
                                user_id = Some(claims.sub);
                                let conn_id = Uuid::new_v4().to_string();
                                _connection_id = Some(conn_id.clone());

                                // Register connection
                                state.hub.register(claims.sub, conn_id.clone()).await;

                                // Send authenticated response
                                let auth_msg = WsMessage::authenticated(
                                    claims.sub,
                                    claims.convro_number.clone(),
                                    conn_id,
                                );
                                if let Ok(json) = auth_msg.to_json() {
                                    if sender.send(Message::Text(json)).await.is_err() {
                                        tracing::error!("Failed to send authenticated message");
                                        break;
                                    }
                                }

                                tracing::info!(
                                    "WebSocket authenticated: user={} ({})",
                                    claims.sub,
                                    claims.convro_number
                                );
                            }
                            Err(e) => {
                                tracing::warn!("WebSocket authentication failed: {}", e);
                                let error = WsMessage::error(
                                    "AUTH_FAILED".to_string(),
                                    "Invalid or expired token".to_string(),
                                );
                                if let Ok(json) = error.to_json() {
                                    let _ = sender.send(Message::Text(json)).await;
                                }
                                break;
                            }
                        }
                    }
                    WsMessageType::Ping { .. } => {
                        // Respond with pong
                        let pong = WsMessage::pong();
                        if let Ok(json) = pong.to_json() {
                            if sender.send(Message::Text(json)).await.is_err() {
                                tracing::error!("Failed to send pong");
                                break;
                            }
                        }
                    }
                    WsMessageType::Ack { message_id } => {
                        tracing::debug!("Message acknowledged: {}", message_id);
                        // TODO: Mark message as delivered in database
                    }
                    WsMessageType::Disconnect { reason } => {
                        tracing::info!("Client disconnect: {}", reason);
                        let goodbye = WsMessage::goodbye("Goodbye".to_string());
                        if let Ok(json) = goodbye.to_json() {
                            let _ = sender.send(Message::Text(json)).await;
                        }
                        break;
                    }
                    _ => {
                        tracing::warn!("Unsupported WebSocket message type: {:?}", ws_msg);
                    }
                }
            }
            Ok(Message::Close(_)) => {
                tracing::info!("WebSocket closed by client");
                break;
            }
            Ok(Message::Ping(_)) | Ok(Message::Pong(_)) => {
                // WebSocket-level ping/pong handled by axum
            }
            Ok(Message::Binary(_)) => {
                tracing::warn!("Received binary message (not supported)");
            }
            Err(e) => {
                tracing::error!("WebSocket error: {}", e);
                break;
            }
        }
    }

    // Cleanup on disconnect
    if let Some(uid) = user_id {
        state.hub.unregister(&uid).await;
        tracing::info!("WebSocket connection closed: user={}", uid);
    }
}
