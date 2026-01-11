# C6P Protocol - XCFramework Distribution Guide

Complete guide for building, distributing, and integrating the C6P Protocol iOS framework.

## Table of Contents

- [Overview](#overview)
- [Distribution Methods](#distribution-methods)
- [Building XCFramework](#building-xcframework)
- [Swift Package Manager Integration](#swift-package-manager-integration)
- [Manual Integration](#manual-integration)
- [Creating Releases](#creating-releases)
- [Version Management](#version-management)
- [Troubleshooting](#troubleshooting)

---

## Overview

The C6P Protocol is distributed as an **XCFramework** - Apple's standard format for distributing binary frameworks across multiple platforms and architectures.

### What's Included

- **C6PProtocol.xcframework** - Universal binary framework containing:
  - iOS Device (ARM64)
  - iOS Simulator (ARM64 + x86_64)
  - C headers and module maps

- **c6p_ios.swift** - UniFFI-generated Swift bindings
- **Package.swift** - Swift Package Manager manifest
- **Checksums** - SHA-256 verification for security

### Supported Platforms

| Platform | Architectures | Minimum Version |
|----------|--------------|-----------------|
| iOS Device | ARM64 | iOS 13.0+ |
| iOS Simulator | ARM64, x86_64 | iOS 13.0+ |
| macOS | (Future) | macOS 11.0+ |

---

## Distribution Methods

### 1. Swift Package Manager (Recommended) ⭐

**Pros:**
- Native Xcode integration
- Automatic dependency resolution
- Version management
- No manual setup

**Cons:**
- Requires GitHub release

**Best for:** Production apps, open source projects

### 2. Manual XCFramework

**Pros:**
- Full control over framework
- Works offline
- No external dependencies

**Cons:**
- Manual updates
- Manual integration steps

**Best for:** Internal tools, quick prototyping

### 3. CocoaPods (Future)

**Status:** Not yet implemented

---

## Building XCFramework

### Prerequisites

**System Requirements:**
- macOS 12.0+ (Monterey or later)
- Xcode 14.0+ with Command Line Tools
- Rust 1.85.0+

**Install Rust Targets:**
```bash
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios
```

**Verify Installation:**
```bash
xcode-select --print-path
rustc --version
cargo --version
```

### Build Process

#### Step 1: Build Rust Universal Libraries

```bash
cd /path/to/convro-6-protocol
./Scripts/build-rust-universal.sh release
```

**What this does:**
1. Compiles Rust code for all iOS architectures
2. Creates universal binaries with `lipo`
3. Generates UniFFI Swift bindings
4. Prepares staging directory

**Output:**
```
build/xcframework-staging/
├── ios-arm64/
│   ├── libc6p_ios.a
│   └── Headers/
├── ios-arm64_x86_64-simulator/
│   ├── libc6p_ios.a
│   └── Headers/
└── bindings/
    └── c6p_ios.swift
```

**Build time:** ~2-5 minutes (depending on hardware)

#### Step 2: Create XCFramework

```bash
./Scripts/build-xcframework.sh release 0.1.0
```

**Arguments:**
- `release` - Build mode (debug or release)
- `0.1.0` - Version number (semantic versioning)

**What this does:**
1. Creates framework bundles from static libraries
2. Generates Info.plist for each platform
3. Builds XCFramework with `xcodebuild`
4. Creates distribution ZIP
5. Generates checksums

**Output:**
```
build/xcframework/
├── C6PProtocol.xcframework/
├── C6PProtocol-0.1.0.xcframework.zip
├── c6p_ios.swift
└── checksums.txt
```

**Build time:** ~30-60 seconds

### Build Script Options

#### Debug vs Release

**Debug Build:**
```bash
./Scripts/build-rust-universal.sh debug
./Scripts/build-xcframework.sh debug 0.1.0-dev
```

- Faster compilation
- Includes debug symbols
- Larger binary size
- Better error messages

**Release Build:**
```bash
./Scripts/build-rust-universal.sh release
./Scripts/build-xcframework.sh release 0.1.0
```

- Optimized for performance
- Smaller binary size
- Production-ready
- Strip debug symbols

### Verify Build

```bash
# Check XCFramework structure
ls -la build/xcframework/C6PProtocol.xcframework/

# Verify architectures
find build/xcframework/C6PProtocol.xcframework -name "C6PProtocol" -type f -exec lipo -info {} \;

# Check file size
du -h build/xcframework/C6PProtocol-0.1.0.xcframework.zip

# Verify checksum
shasum -a 256 build/xcframework/C6PProtocol-0.1.0.xcframework.zip
```

---

## Swift Package Manager Integration

### For Package Consumers

#### Method 1: Xcode GUI

1. Open your Xcode project
2. **File → Add Package Dependencies**
3. Enter repository URL:
   ```
   https://github.com/convro/convro-6-protocol.git
   ```
4. Select version rule:
   - **Exact Version:** `0.1.0`
   - **Up to Next Major:** `0.1.0 < 1.0.0`
   - **Branch:** `main` (for development)
5. Click **Add Package**
6. Select `C6PProtocol` library

#### Method 2: Package.swift

For Swift packages:

```swift
// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v13)
    ],
    dependencies: [
        // Add C6P Protocol dependency
        .package(
            url: "https://github.com/convro/convro-6-protocol.git",
            from: "0.1.0"
        )
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "C6PProtocol", package: "convro-6-protocol")
            ]
        )
    ]
)
```

#### Method 3: Local Development

For testing local builds before release:

```swift
dependencies: [
    .package(path: "../convro-6-protocol")
]
```

### Usage in Swift Code

```swift
import C6PProtocol

// Generate device identity
let identity = try identity_generate_identity()
print("Device ID: \(utils_bytes_to_hex(data: identity.device_id))")

// Create handshake offer
let result = try handshake_create_offer(
    initiator_identity: identity,
    responder_bundle: responderBundle
)

// Access session keys
let sessionKeys = result.session_keys
```

---

## Manual Integration

### Step 1: Download XCFramework

Download from GitHub release:
```bash
curl -L -o C6PProtocol-0.1.0.xcframework.zip \
  https://github.com/convro/convro-6-protocol/releases/download/v0.1.0/C6PProtocol-0.1.0.xcframework.zip
```

### Step 2: Verify Checksum

```bash
shasum -a 256 C6PProtocol-0.1.0.xcframework.zip
# Compare with checksums.txt from release
```

### Step 3: Add to Xcode Project

1. Unzip: `unzip C6PProtocol-0.1.0.xcframework.zip`
2. Drag `C6PProtocol.xcframework` to Xcode project navigator
3. Select target → **General** tab
4. Verify framework appears in **Frameworks, Libraries, and Embedded Content**
5. Ensure **Embed & Sign** is selected

### Step 4: Import and Use

```swift
import C6PProtocol

// Use C6P Protocol APIs
```

---

## Creating Releases

### Automated Release (GitHub Actions)

#### Step 1: Tag Version

```bash
# Ensure you're on main branch with latest changes
git checkout main
git pull origin main

# Create and push version tag
git tag v0.1.0
git push origin v0.1.0
```

#### Step 2: Monitor Workflow

1. Go to GitHub → **Actions** tab
2. Watch "Build and Release XCFramework" workflow
3. Wait for completion (~10-15 minutes)

#### Step 3: Verify Release

1. Go to GitHub → **Releases**
2. Find release `v0.1.0`
3. Verify artifacts:
   - ✅ `C6PProtocol-0.1.0.xcframework.zip`
   - ✅ `checksums.txt`
   - ✅ `c6p_ios.swift`
   - ✅ `Package.swift.release`

#### Step 4: Update Package.swift

```bash
# Download updated Package.swift from release
curl -L -o Package.swift \
  https://github.com/convro/convro-6-protocol/releases/download/v0.1.0/Package.swift.release

# Commit updated Package.swift
git add Package.swift
git commit -m "Update Package.swift with v0.1.0 checksum"
git push origin main
```

### Manual Release

If GitHub Actions is unavailable:

```bash
# 1. Build XCFramework
./Scripts/build-rust-universal.sh release
./Scripts/build-xcframework.sh release 0.1.0

# 2. Create GitHub release manually
gh release create v0.1.0 \
  --title "C6P Protocol v0.1.0" \
  --notes "See RELEASE_NOTES.md for details" \
  build/xcframework/C6PProtocol-0.1.0.xcframework.zip \
  build/xcframework/checksums.txt \
  build/xcframework/c6p_ios.swift

# 3. Update Package.swift with checksum
CHECKSUM=$(shasum -a 256 build/xcframework/C6PProtocol-0.1.0.xcframework.zip | awk '{print $1}')
# Manually edit Package.swift with checksum and URL
```

---

## Version Management

### Semantic Versioning

C6P Protocol follows [Semantic Versioning 2.0.0](https://semver.org/):

**Format:** `MAJOR.MINOR.PATCH`

- **MAJOR:** Breaking API changes
- **MINOR:** New features, backward compatible
- **PATCH:** Bug fixes, backward compatible

**Examples:**
- `0.1.0` - Initial release
- `0.1.1` - Bug fix (patch)
- `0.2.0` - New feature (minor)
- `1.0.0` - Stable API (major)

### Version Bumping

```bash
# Patch release (0.1.0 → 0.1.1)
git tag v0.1.1
git push origin v0.1.1

# Minor release (0.1.1 → 0.2.0)
# Update rust/Cargo.toml version first
git tag v0.2.0
git push origin v0.2.0

# Major release (0.2.0 → 1.0.0)
# Update version in:
# - rust/Cargo.toml
# - Sources/C6PProtocol/Placeholder.swift
git tag v1.0.0
git push origin v1.0.0
```

### Pre-release Versions

For alpha/beta/RC:

```bash
# Alpha: 0.2.0-alpha.1
git tag v0.2.0-alpha.1

# Beta: 0.2.0-beta.1
git tag v0.2.0-beta.1

# Release Candidate: 0.2.0-rc.1
git tag v0.2.0-rc.1
```

SPM will only resolve to stable versions by default.

---

## Troubleshooting

### Build Issues

#### Error: "Target not installed"

```bash
# Install missing iOS targets
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios
```

#### Error: "lipo command not found"

```bash
# Install Xcode Command Line Tools
xcode-select --install
```

#### Error: "uniffi-bindgen not found"

UniFFI bindings are generated using the built-in tool:
```bash
cd rust/c6p-ios
cargo run --bin uniffi-bindgen -- --help
```

#### Error: "Framework bundle not found"

Check build output:
```bash
ls -la build/xcframework-staging/
```

If empty, rebuild Rust libraries:
```bash
./Scripts/build-rust-universal.sh release
```

### Integration Issues

#### Error: "Module 'C6PProtocol' not found"

**SPM:** Clean and rebuild
```bash
# Xcode: Product → Clean Build Folder
# Or command line:
rm -rf .build/
swift package clean
swift build
```

**Manual:** Verify framework is embedded
1. Target → General
2. Check **Frameworks, Libraries, and Embedded Content**
3. Ensure **Embed & Sign** is selected

#### Error: "Symbol not found"

Missing architecture in XCFramework:
```bash
# Verify architectures
lipo -info build/xcframework/C6PProtocol.xcframework/ios-arm64/C6PProtocol
lipo -info build/xcframework/C6PProtocol.xcframework/ios-arm64_x86_64-simulator/C6PProtocol
```

Rebuild if architectures are missing.

#### Error: "Checksum mismatch"

Package.swift checksum doesn't match:
```bash
# Recalculate checksum
shasum -a 256 C6PProtocol-0.1.0.xcframework.zip

# Update Package.swift with new checksum
```

### Runtime Issues

#### Crash: "Library not loaded"

Framework not properly embedded:
1. Clean derived data: `Shift+Cmd+K`
2. Rebuild project
3. Verify framework in app bundle:
   ```bash
   unzip -l MyApp.app | grep C6PProtocol
   ```

#### Error: "Invalid device_id"

Check Swift bindings version matches framework:
```bash
# In framework release, both should have same version
grep "version" build/xcframework/c6p_ios.swift
xcodebuild -checkBuildSettings -xcframework build/xcframework/C6PProtocol.xcframework
```

---

## Best Practices

### For Maintainers

1. **Always run tests before release**
   ```bash
   cd rust && cargo test --all
   ```

2. **Use release builds for distribution**
   ```bash
   ./Scripts/build-rust-universal.sh release
   ```

3. **Verify checksums match between build and release**

4. **Tag releases consistently**
   ```bash
   git tag -a v0.1.0 -m "Release version 0.1.0"
   ```

5. **Update CHANGELOG.md with each release**

### For Consumers

1. **Pin to specific versions in production**
   ```swift
   .package(url: "...", exact: "0.1.0")
   ```

2. **Verify checksums when downloading manually**

3. **Test with iOS Simulator before deploying to device**

4. **Keep dependencies updated**
   ```bash
   swift package update
   ```

---

## File Size Reference

| Component | Approximate Size |
|-----------|-----------------|
| Static library (release, per arch) | 1-2 MB |
| XCFramework (uncompressed) | 3-5 MB |
| XCFramework ZIP | 1-2 MB |
| Swift bindings | 100-200 KB |

---

## Security

### Checksum Verification

Always verify checksums when distributing or consuming XCFrameworks:

```bash
# Generate checksum
shasum -a 256 C6PProtocol-0.1.0.xcframework.zip

# Verify against published checksum
diff <(cat checksums.txt | grep SHA-256 | awk '{print $1}') \
     <(shasum -a 256 C6PProtocol-0.1.0.xcframework.zip | awk '{print $1}')
```

### Code Signing

For distribution outside App Store:

```bash
# Sign XCFramework
codesign --sign "Apple Development: Your Name (TEAM_ID)" \
  --timestamp \
  build/xcframework/C6PProtocol.xcframework

# Verify signature
codesign -dv build/xcframework/C6PProtocol.xcframework
```

---

## Further Reading

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Stateless design philosophy
- [SWIFT_INTEGRATION.md](./SWIFT_INTEGRATION.md) - Complete integration guide
- [SECURITY.md](./SECURITY.md) - Security best practices
- [Apple: Distributing Binary Frameworks](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)

---

**Questions or issues?** Open an issue at https://github.com/convro/convro-6-protocol/issues
