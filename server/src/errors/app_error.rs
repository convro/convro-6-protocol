use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;

/// Application error type that maps to HTTP responses
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Payload too large: {0}")]
    PayloadTooLarge(String),

    #[error("Internal error: {0}")]
    InternalError(String),

    #[error("Rate limit exceeded")]
    RateLimitExceeded,

    #[error("Service unavailable: {0}")]
    ServiceUnavailable(String),

    #[error("JWT error: {0}")]
    JwtError(#[from] jsonwebtoken::errors::Error),
}

impl AppError {
    /// Get HTTP status code for this error
    fn status_code(&self) -> StatusCode {
        match self {
            AppError::DatabaseError(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::ValidationError(_) => StatusCode::BAD_REQUEST,
            AppError::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            AppError::NotFound(_) => StatusCode::NOT_FOUND,
            AppError::Conflict(_) => StatusCode::CONFLICT,
            AppError::PayloadTooLarge(_) => StatusCode::PAYLOAD_TOO_LARGE,
            AppError::InternalError(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::RateLimitExceeded => StatusCode::TOO_MANY_REQUESTS,
            AppError::ServiceUnavailable(_) => StatusCode::SERVICE_UNAVAILABLE,
            AppError::JwtError(_) => StatusCode::UNAUTHORIZED,
        }
    }

    /// Get application error code (matches API spec)
    fn error_code(&self) -> &'static str {
        match self {
            AppError::DatabaseError(_) => "INTERNAL_ERROR",
            AppError::ValidationError(_) => "VALIDATION_ERROR",
            AppError::Unauthorized(_) => "INVALID_CREDENTIALS",
            AppError::NotFound(_) => "NOT_FOUND",
            AppError::Conflict(_) => "CONFLICT",
            AppError::PayloadTooLarge(_) => "MESSAGE_TOO_LARGE",
            AppError::InternalError(_) => "INTERNAL_ERROR",
            AppError::RateLimitExceeded => "RATE_LIMIT_EXCEEDED",
            AppError::ServiceUnavailable(_) => "SERVICE_UNAVAILABLE",
            AppError::JwtError(_) => "TOKEN_INVALID",
        }
    }

    /// Get user-facing error message
    fn user_message(&self) -> String {
        match self {
            AppError::DatabaseError(_) => "A database error occurred".to_string(),
            AppError::ValidationError(msg) => msg.clone(),
            AppError::Unauthorized(msg) => msg.clone(),
            AppError::NotFound(msg) => msg.clone(),
            AppError::Conflict(msg) => msg.clone(),
            AppError::PayloadTooLarge(msg) => msg.clone(),
            AppError::InternalError(_) => "An internal error occurred".to_string(),
            AppError::RateLimitExceeded => "Too many requests. Please try again later.".to_string(),
            AppError::ServiceUnavailable(msg) => msg.clone(),
            AppError::JwtError(_) => "Invalid or expired token".to_string(),
        }
    }
}

/// Convert AppError to Axum HTTP response
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = self.status_code();
        let error_code = self.error_code();
        let message = self.user_message();

        // Log internal errors
        if matches!(
            self,
            AppError::DatabaseError(_) | AppError::InternalError(_)
        ) {
            tracing::error!("Internal error: {:?}", self);
        }

        let error_response = ErrorResponse {
            error: ErrorDetail {
                code: error_code.to_string(),
                message,
                timestamp: chrono::Utc::now(),
            },
        };

        (status, Json(error_response)).into_response()
    }
}

/// Error response structure (matches API spec)
#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: ErrorDetail,
}

#[derive(Debug, Serialize)]
struct ErrorDetail {
    code: String,
    message: String,
    timestamp: chrono::DateTime<chrono::Utc>,
}

/// Result type alias for convenience
pub type AppResult<T> = Result<T, AppError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_status_codes() {
        assert_eq!(
            AppError::ValidationError("test".to_string()).status_code(),
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            AppError::Unauthorized("test".to_string()).status_code(),
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            AppError::NotFound("test".to_string()).status_code(),
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            AppError::Conflict("test".to_string()).status_code(),
            StatusCode::CONFLICT
        );
        assert_eq!(
            AppError::RateLimitExceeded.status_code(),
            StatusCode::TOO_MANY_REQUESTS
        );
    }

    #[test]
    fn test_error_codes() {
        assert_eq!(
            AppError::ValidationError("test".to_string()).error_code(),
            "VALIDATION_ERROR"
        );
        assert_eq!(
            AppError::Unauthorized("test".to_string()).error_code(),
            "INVALID_CREDENTIALS"
        );
        assert_eq!(
            AppError::RateLimitExceeded.error_code(),
            "RATE_LIMIT_EXCEEDED"
        );
    }
}
