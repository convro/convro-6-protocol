use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::Response,
};

use crate::{models::Claims, utils::jwt};

/// JWT authentication middleware
///
/// Extracts and validates Bearer token from Authorization header.
/// Inserts Claims into request extensions for downstream handlers.
pub async fn require_auth(mut req: Request, next: Next) -> Result<Response, StatusCode> {
    // Extract Authorization header
    let auth_header = req
        .headers()
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // Parse "Bearer {token}"
    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // Decode and validate JWT
    let claims = jwt::decode_token(token).map_err(|e| {
        tracing::warn!("JWT validation failed: {}", e);
        StatusCode::UNAUTHORIZED
    })?;

    // Verify token type (must be access token)
    if claims.token_type != "access" {
        tracing::warn!("Invalid token type: expected 'access', got '{}'", claims.token_type);
        return Err(StatusCode::UNAUTHORIZED);
    }

    // Insert claims into request extensions
    req.extensions_mut().insert(claims.clone());

    tracing::debug!("Authenticated user: {} ({})", claims.username, claims.convro_number);

    Ok(next.run(req).await)
}

/// Axum extractor for Claims
///
/// Extracts Claims from request extensions (injected by require_auth middleware).
#[axum::async_trait]
impl<S> axum::extract::FromRequestParts<S> for Claims
where
    S: Send + Sync,
{
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        _state: &S,
    ) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<Claims>()
            .cloned()
            .ok_or(StatusCode::UNAUTHORIZED)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, http::Request};
    use tower::ServiceExt;

    #[tokio::test]
    async fn test_require_auth_missing_header() {
        let req = Request::builder().body(Body::empty()).unwrap();

        let result = require_auth(req, |_| async { Ok(Response::new(Body::empty())) }).await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_require_auth_invalid_format() {
        let req = Request::builder()
            .header("Authorization", "InvalidFormat token")
            .body(Body::empty())
            .unwrap();

        let result = require_auth(req, |_| async { Ok(Response::new(Body::empty())) }).await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), StatusCode::UNAUTHORIZED);
    }
}
