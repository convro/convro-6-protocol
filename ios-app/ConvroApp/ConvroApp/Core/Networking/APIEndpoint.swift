import Foundation

// MARK: - API Endpoint
enum APIEndpoint {
    // Authentication
    case register
    case login
    case refresh
    case logout

    // Devices
    case registerDevice
    case listDevices
    case deactivateDevice(UUID)

    // Prekeys
    case uploadPrekeys
    case fetchPrekeyBundle(String)
    case prekeyHealth

    // Messages
    case sendMessage
    case fetchInbox
    case markDelivered(UUID)

    // Conversations
    case listConversations

    // Contacts
    case addContact
    case listContacts
    case verifyContact(UUID)
    case deleteContact(UUID)

    // MARK: - Path
    var path: String {
        switch self {
        case .register: return "/auth/register"
        case .login: return "/auth/login"
        case .refresh: return "/auth/refresh"
        case .logout: return "/auth/logout"

        case .registerDevice: return "/devices"
        case .listDevices: return "/devices"
        case .deactivateDevice(let id): return "/devices/\(id)"

        case .uploadPrekeys: return "/prekeys"
        case .fetchPrekeyBundle(let number): return "/prekeys/\(number)"
        case .prekeyHealth: return "/prekeys/health"

        case .sendMessage: return "/messages"
        case .fetchInbox: return "/messages/inbox"
        case .markDelivered(let id): return "/messages/\(id)/delivered"

        case .listConversations: return "/conversations"

        case .addContact: return "/contacts"
        case .listContacts: return "/contacts"
        case .verifyContact(let id): return "/contacts/\(id)/verify"
        case .deleteContact(let id): return "/contacts/\(id)"
        }
    }

    // MARK: - HTTP Method
    var method: HTTPMethod {
        switch self {
        case .register, .login, .refresh, .logout,
             .registerDevice, .uploadPrekeys, .sendMessage,
             .markDelivered, .addContact, .verifyContact:
            return .post

        case .listDevices, .fetchPrekeyBundle, .prekeyHealth,
             .fetchInbox, .listConversations, .listContacts:
            return .get

        case .deactivateDevice, .deleteContact:
            return .delete
        }
    }
}
