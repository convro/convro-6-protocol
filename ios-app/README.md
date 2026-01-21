# Convro iOS App

**Version:** 1.0.0
**Target:** iOS 15.0+
**Architecture:** SwiftUI + MVVM + Coordinator
**Language:** Swift 5.9+

## Project Structure

This is a complete production-ready iOS application for Convro messaging.

### Features
- ✅ End-to-end encryption (C6P)
- ✅ Sealed sender (privacy-first)
- ✅ Real-time messaging (WebSocket)
- ✅ Contact management
- ✅ Biometric authentication
- ✅ Push notifications

### Build Instructions
1. Open `ConvroApp.xcodeproj` in Xcode 15+
2. Select target device/simulator
3. Build & Run (⌘R)

### Dependencies
- C6PProtocol (Swift Package Manager)
- SwiftUI (iOS 15.0+)
- Combine
- CoreData

### Architecture
- **App Layer:** Entry point, lifecycle
- **Core Layer:** Managers, Models, Networking, Security
- **Features Layer:** MVVM modules (Auth, Chat, Contacts, Settings)

See `docs/ios/IOS_PROJECT_ARCHITECTURE.md` for detailed architecture.
