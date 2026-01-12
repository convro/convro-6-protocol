pub mod auth;
pub mod devices;
pub mod messages;
pub mod prekeys;

pub use auth::router as auth_router;
pub use devices::router as devices_router;
pub use messages::router as messages_router;
pub use prekeys::router as prekeys_router;
