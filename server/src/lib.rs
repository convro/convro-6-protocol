pub mod api;
pub mod config;
pub mod db;
pub mod errors;
pub mod middleware;
pub mod models;
pub mod repositories;
pub mod services;
pub mod utils;

// Re-exports for convenience
pub use config::Settings;
pub use errors::{AppError, AppResult};
