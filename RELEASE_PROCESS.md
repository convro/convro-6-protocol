# C6P Protocol - Release Process Guide

Comprehensive guide for maintainers on how to create, test, and publish releases.

## Table of Contents

- [Release Checklist](#release-checklist)
- [Pre-Release Preparation](#pre-release-preparation)
- [Creating a Release](#creating-a-release)
- [Post-Release Tasks](#post-release-tasks)
- [Hotfix Process](#hotfix-process)
- [Versioning Strategy](#versioning-strategy)

---

## Release Checklist

Use this checklist for every release:

### Pre-Release

- [ ] All tests passing (Rust + CI/CD)
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Version bumped in all files
- [ ] No uncommitted changes
- [ ] Branch up to date with main

### Release

- [ ] Git tag created and pushed
- [ ] GitHub Actions workflow completed
- [ ] XCFramework artifacts uploaded
- [ ] Release notes published
- [ ] Package.swift updated with checksum

### Post-Release

- [ ] Package.swift committed to main
- [ ] Release announced (if applicable)
- [ ] Integration tested in sample project
- [ ] Version bumped for next development cycle

---

## Pre-Release Preparation

### 1. Run Full Test Suite

```bash
cd rust

# Run all tests
cargo test --all

# Run with coverage (optional)
cargo test --all --features coverage

# Run clippy
cargo clippy --all -- -D warnings

# Format check
cargo fmt --all -- --check
```

**Expected:** All tests pass, no warnings.

### 2. Update Version Numbers

**Files to update:**

#### `rust/Cargo.toml` (workspace version)
```toml
[workspace.package]
version = "0.2.0"  # ← Update this
```

#### `Sources/C6PProtocol/Placeholder.swift`
```swift
public let c6pVersion = "0.2.0"  # ← Update this
```

#### (Optional) `rust/c6p-ios/README.md`
Update any version references in examples.

**Commit version bump:**
```bash
git add rust/Cargo.toml Sources/C6PProtocol/Placeholder.swift
git commit -m "Bump version to 0.2.0"
git push origin main
```

### 3. Update CHANGELOG.md

Create or update `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
# Changelog

All notable changes to C6P Protocol will be documented in this file.

## [0.2.0] - 2025-01-15

### Added
- New feature: Message acknowledgments
- API: `session_acknowledge_message()` function

### Changed
- Improved performance of key derivation (20% faster)
- Updated UniFFI to 0.29

### Fixed
- Bug: Incorrect KC2 validation in edge case
- Memory leak in session cleanup

### Security
- Constant-time comparison for all authentication tags

## [0.1.0] - 2025-01-11

### Added
- Initial release
- IslandAccord v1 handshake protocol
- ChaCha20-Poly1305 encryption
- Stateless iOS bridge with XCFramework distribution
```

**Commit changelog:**
```bash
git add CHANGELOG.md
git commit -m "Update CHANGELOG for v0.2.0"
git push origin main
```

### 4. Build and Test Locally

Test the full build pipeline:

```bash
# Build universal libraries
./Scripts/build-rust-universal.sh release

# Create XCFramework
./Scripts/build-xcframework.sh release 0.2.0

# Verify output
ls -lh build/xcframework/
```

**Expected output:**
```
C6PProtocol.xcframework/
C6PProtocol-0.2.0.xcframework.zip
checksums.txt
c6p_ios.swift
```

### 5. Integration Test

Test XCFramework in a real iOS project:

```bash
# Create test iOS project
cd /tmp
mkdir C6PTest && cd C6PTest

# Create minimal test app
cat > Package.swift << 'EOF'
// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "C6PTest",
    platforms: [.iOS(.v13)],
    dependencies: [
        .package(path: "/path/to/convro-6-protocol")
    ],
    targets: [
        .executableTarget(
            name: "C6PTest",
            dependencies: [
                .product(name: "C6PProtocol", package: "convro-6-protocol")
            ]
        )
    ]
)
EOF

# Create test source
mkdir -p Sources/C6PTest
cat > Sources/C6PTest/main.swift << 'EOF'
import Foundation
import C6PProtocol

print("Testing C6P Protocol...")

// Generate identity
let identity = try! identity_generate_identity()
print("✅ Generated device ID: \(utils_bytes_to_hex(data: identity.device_id))")

print("All tests passed!")
EOF

# Build and run
swift build
swift run
```

**Expected:** Test runs successfully, prints device ID.

---

## Creating a Release

### Option A: Automated Release (Recommended)

GitHub Actions handles the entire release process.

#### Step 1: Create and Push Tag

```bash
# Ensure you're on main with latest changes
git checkout main
git pull origin main

# Create annotated tag
git tag -a v0.2.0 -m "Release version 0.2.0"

# Push tag to trigger workflow
git push origin v0.2.0
```

#### Step 2: Monitor Workflow

1. Go to https://github.com/convro/convro-6-protocol/actions
2. Find "Build and Release XCFramework" workflow
3. Click on the running workflow
4. Monitor each job step

**Expected duration:** ~10-15 minutes

**Job steps:**
1. ✅ Checkout repository
2. ✅ Install Rust toolchain + iOS targets
3. ✅ Run tests
4. ✅ Build universal libraries
5. ✅ Create XCFramework
6. ✅ Generate checksums
7. ✅ Create GitHub release
8. ✅ Upload artifacts

#### Step 3: Verify Release

1. Go to https://github.com/convro/convro-6-protocol/releases
2. Find release "C6P Protocol v0.2.0"
3. Verify artifacts:
   - ✅ `C6PProtocol-0.2.0.xcframework.zip` (~1-2 MB)
   - ✅ `checksums.txt`
   - ✅ `c6p_ios.swift` (~100-200 KB)
   - ✅ `Package.swift.release`

4. Download and verify checksum:
```bash
curl -L -o C6PProtocol-0.2.0.xcframework.zip \
  https://github.com/convro/convro-6-protocol/releases/download/v0.2.0/C6PProtocol-0.2.0.xcframework.zip

shasum -a 256 C6PProtocol-0.2.0.xcframework.zip
# Compare with checksums.txt
```

#### Step 4: Update Package.swift

```bash
# Download updated Package.swift from release
curl -L -o Package.swift.new \
  https://github.com/convro/convro-6-protocol/releases/download/v0.2.0/Package.swift.release

# Review changes
diff Package.swift Package.swift.new

# Apply update
mv Package.swift.new Package.swift

# Commit to main
git add Package.swift
git commit -m "Update Package.swift with v0.2.0 checksum [skip ci]"
git push origin main
```

**Why `[skip ci]`?** Prevents unnecessary CI runs for Package.swift-only updates.

### Option B: Manual Release

If GitHub Actions is unavailable or you need manual control:

#### Step 1: Build Locally

```bash
# Build release artifacts
./Scripts/build-rust-universal.sh release
./Scripts/build-xcframework.sh release 0.2.0

# Generate checksum
CHECKSUM=$(shasum -a 256 build/xcframework/C6PProtocol-0.2.0.xcframework.zip | awk '{print $1}')
echo "Checksum: $CHECKSUM"
```

#### Step 2: Create Git Tag

```bash
git tag -a v0.2.0 -m "Release version 0.2.0"
git push origin v0.2.0
```

#### Step 3: Create GitHub Release

Using GitHub CLI:

```bash
gh release create v0.2.0 \
  --title "C6P Protocol v0.2.0" \
  --notes-file CHANGELOG.md \
  build/xcframework/C6PProtocol-0.2.0.xcframework.zip \
  build/xcframework/checksums.txt \
  build/xcframework/c6p_ios.swift
```

Or manually via web interface:
1. Go to https://github.com/convro/convro-6-protocol/releases/new
2. Choose tag: `v0.2.0`
3. Release title: `C6P Protocol v0.2.0`
4. Description: Copy from CHANGELOG.md
5. Attach files:
   - `C6PProtocol-0.2.0.xcframework.zip`
   - `checksums.txt`
   - `c6p_ios.swift`
6. Click "Publish release"

#### Step 4: Update Package.swift Manually

Edit `Package.swift`:

```swift
.binaryTarget(
    name: "C6PProtocolFFI",
    url: "https://github.com/convro/convro-6-protocol/releases/download/v0.2.0/C6PProtocol-0.2.0.xcframework.zip",
    checksum: "YOUR_CHECKSUM_HERE"  // ← Paste checksum from Step 1
),
```

Commit:
```bash
git add Package.swift
git commit -m "Update Package.swift with v0.2.0 checksum"
git push origin main
```

---

## Post-Release Tasks

### 1. Test SPM Integration

Create a test project using the newly released version:

```bash
mkdir /tmp/SPMTest && cd /tmp/SPMTest

cat > Package.swift << 'EOF'
// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SPMTest",
    platforms: [.iOS(.v13)],
    dependencies: [
        .package(
            url: "https://github.com/convro/convro-6-protocol.git",
            exact: "0.2.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "SPMTest",
            dependencies: [
                .product(name: "C6PProtocol", package: "convro-6-protocol")
            ]
        )
    ]
)
EOF

mkdir -p Sources/SPMTest
cat > Sources/SPMTest/main.swift << 'EOF'
import C6PProtocol
let identity = try! identity_generate_identity()
print("Device ID: \(utils_bytes_to_hex(data: identity.device_id))")
EOF

# Resolve and build
swift package resolve
swift build
swift run
```

**Expected:** Package resolves successfully, builds, and runs.

### 2. Test Xcode Integration

1. Create new iOS project in Xcode
2. **File → Add Package Dependencies**
3. Enter: `https://github.com/convro/convro-6-protocol.git`
4. Select exact version: `0.2.0`
5. Build and run

**Expected:** Project builds without errors.

### 3. Announce Release (Optional)

**Internal:**
- Update team Slack/Discord
- Send email to stakeholders

**External (if public):**
- Twitter/X announcement
- Blog post
- Reddit r/rust, r/cryptography

### 4. Prepare for Next Development Cycle

Bump version to next development version:

```bash
# Update version to 0.3.0-dev
# Edit rust/Cargo.toml
[workspace.package]
version = "0.3.0-dev"

# Commit
git add rust/Cargo.toml
git commit -m "Bump version to 0.3.0-dev for next development cycle"
git push origin main
```

---

## Hotfix Process

For critical bug fixes that need immediate release:

### 1. Create Hotfix Branch

```bash
# Branch from the release tag
git checkout v0.2.0
git checkout -b hotfix/0.2.1
```

### 2. Fix Bug

```bash
# Make minimal changes to fix the bug
# ... edit files ...

git add .
git commit -m "Fix critical bug in KC2 validation"
```

### 3. Update Version

```bash
# Update to patch version
# rust/Cargo.toml: 0.2.0 → 0.2.1

git add rust/Cargo.toml
git commit -m "Bump version to 0.2.1"
```

### 4. Test Thoroughly

```bash
cd rust
cargo test --all
```

### 5. Merge to Main

```bash
git checkout main
git merge --no-ff hotfix/0.2.1
git push origin main
```

### 6. Create Release

```bash
git tag -a v0.2.1 -m "Hotfix release 0.2.1 - Fix KC2 validation bug"
git push origin v0.2.1
```

### 7. Delete Hotfix Branch

```bash
git branch -d hotfix/0.2.1
git push origin --delete hotfix/0.2.1
```

---

## Versioning Strategy

### Semantic Versioning (SemVer)

**Format:** `MAJOR.MINOR.PATCH`

#### MAJOR (Breaking Changes)

Increment when making incompatible API changes:
- Removing public functions
- Changing function signatures
- Renaming public types
- Changing behavior of existing APIs

**Example:** `1.2.3` → `2.0.0`

#### MINOR (New Features)

Increment when adding functionality in a backward-compatible manner:
- New public functions
- New optional parameters
- New types (that don't conflict)
- Performance improvements

**Example:** `1.2.3` → `1.3.0`

#### PATCH (Bug Fixes)

Increment for backward-compatible bug fixes:
- Bug fixes
- Security patches
- Documentation updates
- Internal refactoring

**Example:** `1.2.3` → `1.2.4`

### Pre-Release Versions

**Alpha:** Early testing, unstable API
```
0.3.0-alpha.1
0.3.0-alpha.2
```

**Beta:** Feature-complete, API frozen, testing
```
0.3.0-beta.1
0.3.0-beta.2
```

**Release Candidate:** Final testing before release
```
0.3.0-rc.1
0.3.0-rc.2
```

**Stable:**
```
0.3.0
```

### Version 1.0.0 Criteria

Before releasing 1.0.0, ensure:

- [ ] API is stable and well-documented
- [ ] All core features implemented
- [ ] Comprehensive test coverage (>90%)
- [ ] Security audit completed
- [ ] Performance benchmarks established
- [ ] Production usage by at least one project
- [ ] Breaking changes are unlikely

---

## Troubleshooting Release Issues

### GitHub Actions Workflow Failed

**Check logs:**
1. Go to Actions tab
2. Click failed workflow
3. Expand failed step
4. Read error message

**Common issues:**

**Rust compilation error:**
```bash
# Test locally first
cd rust
cargo test --all
```

**Missing iOS target:**
```bash
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios
```

**XCFramework creation failed:**
```bash
# Check xcodebuild logs
xcodebuild -version
```

### Checksum Mismatch

**Symptom:** SPM reports checksum mismatch

**Fix:**
```bash
# Recalculate checksum
shasum -a 256 C6PProtocol-0.2.0.xcframework.zip

# Update Package.swift with correct checksum
```

### Binary Target Not Found

**Symptom:** SPM can't download binary target

**Check:**
1. Release exists: https://github.com/convro/convro-6-protocol/releases/tag/v0.2.0
2. Asset exists: `C6PProtocol-0.2.0.xcframework.zip`
3. URL in Package.swift is correct
4. Checksum matches

### Tag Already Exists

**Symptom:** Can't push tag, already exists

**Fix:**
```bash
# Delete remote tag
git push --delete origin v0.2.0

# Delete local tag
git tag -d v0.2.0

# Recreate tag
git tag -a v0.2.0 -m "Release version 0.2.0"
git push origin v0.2.0
```

---

## Rollback Process

If a release has critical issues:

### 1. Yanked Release (Preferred)

GitHub doesn't support yanking, but you can:

1. Edit release on GitHub
2. Mark as **Pre-release**
3. Add warning to description:
   ```
   ⚠️ WARNING: This release has been yanked due to [issue].
   Please use v0.2.2 instead.
   ```

### 2. Hotfix Release (Recommended)

Release a fixed version immediately:
```bash
# Follow hotfix process for v0.2.1 or v0.2.2
```

### 3. Delete Release (Last Resort)

Only for severely broken releases:

```bash
# Delete release
gh release delete v0.2.0 --yes

# Delete tag
git push --delete origin v0.2.0
git tag -d v0.2.0
```

**Warning:** This breaks anyone who already depends on v0.2.0!

---

## Release Calendar

### Regular Releases

**Minor releases:** Every 4-6 weeks
**Patch releases:** As needed for bugs
**Major releases:** When API stability achieved

### Security Releases

**Critical vulnerabilities:** Immediately
**High severity:** Within 48 hours
**Medium severity:** Next patch release

---

## Appendix: Release Commands Quick Reference

```bash
# Pre-release
cargo test --all
cargo clippy --all -- -D warnings
git add rust/Cargo.toml Sources/C6PProtocol/Placeholder.swift CHANGELOG.md
git commit -m "Bump version to 0.2.0"
git push origin main

# Build locally
./Scripts/build-rust-universal.sh release
./Scripts/build-xcframework.sh release 0.2.0

# Create release
git tag -a v0.2.0 -m "Release version 0.2.0"
git push origin v0.2.0

# Post-release
curl -L -o Package.swift https://github.com/convro/convro-6-protocol/releases/download/v0.2.0/Package.swift.release
git add Package.swift
git commit -m "Update Package.swift with v0.2.0 checksum [skip ci]"
git push origin main
```

---

**Maintainer Notes:**
- Always test locally before releasing
- Keep CHANGELOG.md up to date
- Verify checksums match between build and release
- Test SPM integration after each release
- Communicate breaking changes clearly

**Questions?** Contact the C6P Protocol team or open an issue.
