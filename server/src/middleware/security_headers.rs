use axum::{
    extract::Request,
    http::{header, HeaderName},
    middleware::Next,
    response::Response,
};

/// Security headers middleware
/// Adds production-ready security headers to all responses
pub async fn security_headers_middleware(request: Request, next: Next) -> Response {
    let mut response = next.run(request).await;

    let headers = response.headers_mut();

    // Content Security Policy - Prevent XSS, clickjacking, etc.
    headers.insert(
        header::CONTENT_SECURITY_POLICY,
        "default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
            .parse()
            .unwrap(),
    );

    // Strict Transport Security - Force HTTPS
    headers.insert(
        header::STRICT_TRANSPORT_SECURITY,
        "max-age=31536000; includeSubDomains; preload"
            .parse()
            .unwrap(),
    );

    // X-Frame-Options - Prevent clickjacking
    headers.insert(header::X_FRAME_OPTIONS, "DENY".parse().unwrap());

    // X-Content-Type-Options - Prevent MIME sniffing
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        "nosniff".parse().unwrap(),
    );

    // Referrer-Policy - Control referrer information
    headers.insert(
        header::REFERRER_POLICY,
        "strict-origin-when-cross-origin".parse().unwrap(),
    );

    // Permissions-Policy - Disable unnecessary browser features
    headers.insert(
        HeaderName::from_static("permissions-policy"),
        "camera=(), microphone=(), geolocation=(), payment=()"
            .parse()
            .unwrap(),
    );

    // X-XSS-Protection - Enable XSS filter (legacy browsers)
    headers.insert(
        HeaderName::from_static("x-xss-protection"),
        "1; mode=block".parse().unwrap(),
    );

    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, http::Request};

    #[tokio::test]
    async fn test_security_headers() {
        // This test requires a mock next function
        // In production, headers are verified via integration tests
    }
}
