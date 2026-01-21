use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
};
use governor::{
    clock::DefaultClock,
    state::{InMemoryState, NotKeyed},
    Quota, RateLimiter,
};
use std::{num::NonZeroU32, sync::Arc};

/// Rate limiter state shared across all requests
pub struct RateLimitState {
    limiter: Arc<RateLimiter<NotKeyed, InMemoryState, DefaultClock>>,
}

impl RateLimitState {
    /// Create new rate limiter with requests per minute
    pub fn new(requests_per_minute: u32) -> Self {
        let quota = Quota::per_minute(NonZeroU32::new(requests_per_minute).unwrap());
        let limiter = Arc::new(RateLimiter::direct(quota));

        Self { limiter }
    }
}

/// Rate limiting middleware
/// Limits requests globally across all endpoints
pub async fn rate_limit_middleware(
    state: axum::extract::State<Arc<RateLimitState>>,
    request: Request,
    next: Next,
) -> Response {
    // Check rate limit
    match state.limiter.check() {
        Ok(_) => {
            // Request allowed, proceed
            next.run(request).await
        }
        Err(_) => {
            // Rate limit exceeded
            tracing::warn!("Rate limit exceeded for request");

            (
                StatusCode::TOO_MANY_REQUESTS,
                "Rate limit exceeded. Please try again later.",
            )
                .into_response()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limiter_creation() {
        let state = RateLimitState::new(60);
        assert!(state.limiter.check().is_ok());
    }
}
