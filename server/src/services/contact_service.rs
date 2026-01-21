use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::contact::{AddContactRequest, Contact, ContactResponse, ContactsResponse},
    repositories::{contact_repo::ContactRepository, device_repo::DeviceRepository, user_repo::UserRepository},
};

/// Contact service for contact management operations
#[derive(Clone)]
pub struct ContactService {
    contact_repo: ContactRepository,
    user_repo: UserRepository,
    device_repo: DeviceRepository,
}

impl ContactService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            contact_repo: ContactRepository::new(pool.clone()),
            user_repo: UserRepository::new(pool.clone()),
            device_repo: DeviceRepository::new(pool),
        }
    }

    /// Get all contacts for a user
    pub async fn list_contacts(&self, user_id: Uuid) -> AppResult<ContactsResponse> {
        let contacts = self.contact_repo.list_by_user(user_id).await?;

        // Convert to response with device identity info
        let mut contact_responses = Vec::new();
        for contact in contacts {
            if let Some(response) = self.contact_to_response(contact).await? {
                contact_responses.push(response);
            }
        }

        Ok(ContactsResponse {
            contacts: contact_responses,
        })
    }

    /// Add new contact
    pub async fn add_contact(
        &self,
        user_id: Uuid,
        request: AddContactRequest,
    ) -> AppResult<ContactResponse> {
        // Check if contact user exists
        let contact_user = self
            .user_repo
            .find_by_convro_number(&request.convro_number)
            .await?
            .ok_or_else(|| {
                AppError::NotFound(format!(
                    "User with Convro Number {} not found",
                    request.convro_number
                ))
            })?;

        // Create contact
        let contact = self
            .contact_repo
            .create(
                user_id,
                request.convro_number.clone(),
                Some(contact_user.user_id),
                request.display_name,
            )
            .await?;

        // Convert to response
        self.contact_to_response(contact)
            .await?
            .ok_or_else(|| AppError::NotFound("Contact device not found".to_string()))
    }

    /// Delete contact
    pub async fn delete_contact(&self, contact_id: Uuid, user_id: Uuid) -> AppResult<()> {
        self.contact_repo.delete(contact_id, user_id).await
    }

    /// Verify contact
    pub async fn verify_contact(
        &self,
        contact_id: Uuid,
        user_id: Uuid,
        verified: bool,
    ) -> AppResult<ContactResponse> {
        let contact = self
            .contact_repo
            .update_verification(contact_id, user_id, verified)
            .await?;

        self.contact_to_response(contact)
            .await?
            .ok_or_else(|| AppError::NotFound("Contact device not found".to_string()))
    }

    /// Helper: Convert Contact to ContactResponse with device identity
    async fn contact_to_response(&self, contact: Contact) -> AppResult<Option<ContactResponse>> {
        // Get contact's user
        let contact_user_id = match contact.contact_user_id {
            Some(id) => id,
            None => return Ok(None), // Contact user not found (deleted?)
        };

        // Get contact's primary device to get identity key
        let devices = self.device_repo.list_by_user(contact_user_id).await?;
        let primary_device = devices.first();

        if let Some(device) = primary_device {
            // Convert device_id (Ed25519 public key) to base64 string
            let identity_pub_ed25519 = base64::Engine::encode(
                &base64::engine::general_purpose::STANDARD,
                &device.device_id,
            );
            let fingerprint = identity_pub_ed25519.clone();

            Ok(Some(ContactResponse {
                contact_id: contact.contact_id,
                convro_number: contact.contact_convro_number,
                display_name: contact.display_name,
                identity_pub_ed25519,
                fingerprint,
                verified: contact.is_verified,
                created_at: contact.added_at,
            }))
        } else {
            // Contact has no devices registered
            Ok(None)
        }
    }
}
