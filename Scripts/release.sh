#!/bin/bash
#
# release.sh
# Complete release workflow helper script
#
# Usage:
#   ./Scripts/release.sh [version]
#
# Example:
#   ./Scripts/release.sh 0.1.0
#
# This script automates the complete local release process:
#   1. Run tests
#   2. Build Rust universal libraries
#   3. Create XCFramework
#   4. Generate checksums
#   5. Create git tag
#   6. (Optional) Push tag to trigger GitHub Actions
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${MAGENTA}==>${NC} $1"
    echo ""
}

ask_yes_no() {
    local question=$1
    local default=${2:-n}

    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    while true; do
        read -p "$(echo -e ${CYAN}${question}${NC}) $prompt: " response
        response=${response:-$default}

        case "$response" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

# ============================================================================
# Validation
# ============================================================================

if [[ -z "$VERSION" ]]; then
    log_error "Version not specified"
    echo "Usage: $0 <version>"
    echo "Example: $0 0.1.0"
    exit 1
fi

# Validate version format (basic semver check)
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.]+)?$'; then
    log_error "Invalid version format: $VERSION"
    echo "Expected format: MAJOR.MINOR.PATCH (e.g., 0.1.0)"
    echo "Or: MAJOR.MINOR.PATCH-prerelease (e.g., 0.1.0-alpha.1)"
    exit 1
fi

log_step "C6P Protocol Release Workflow"
log_info "Version: $VERSION"
log_info "Repo: $REPO_ROOT"

# Check for uncommitted changes
cd "$REPO_ROOT"
if [[ -n "$(git status --porcelain)" ]]; then
    log_warning "You have uncommitted changes:"
    git status --short
    echo ""
    if ! ask_yes_no "Continue anyway?"; then
        exit 1
    fi
fi

# ============================================================================
# Step 1: Run Tests
# ============================================================================

log_step "Step 1: Running Rust tests"

cd "$REPO_ROOT/rust"

if ask_yes_no "Run full test suite?" y; then
    log_info "Running cargo test..."
    cargo test --all

    log_info "Running clippy..."
    cargo clippy --all -- -D warnings

    log_info "Checking formatting..."
    cargo fmt --all -- --check

    log_success "All tests passed!"
else
    log_warning "Skipping tests (not recommended for releases)"
fi

# ============================================================================
# Step 2: Version Check
# ============================================================================

log_step "Step 2: Version consistency check"

CARGO_VERSION=$(grep '^version = ' rust/Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
SWIFT_VERSION=$(grep 'c6pVersion = ' Sources/C6PProtocol/Placeholder.swift | sed 's/.*"\(.*\)"/\1/')

log_info "Cargo.toml version: $CARGO_VERSION"
log_info "Placeholder.swift version: $SWIFT_VERSION"
log_info "Target version: $VERSION"

if [[ "$CARGO_VERSION" != "$VERSION" ]] || [[ "$SWIFT_VERSION" != "$VERSION" ]]; then
    log_warning "Version mismatch detected!"
    echo ""
    echo "To fix:"
    echo "  1. Edit rust/Cargo.toml: version = \"$VERSION\""
    echo "  2. Edit Sources/C6PProtocol/Placeholder.swift: c6pVersion = \"$VERSION\""
    echo "  3. Commit: git commit -m 'Bump version to $VERSION'"
    echo ""
    if ! ask_yes_no "Continue anyway?"; then
        exit 1
    fi
fi

# ============================================================================
# Step 3: Build Rust Universal Libraries
# ============================================================================

log_step "Step 3: Building Rust universal libraries"

if ask_yes_no "Build Rust universal libraries?" y; then
    cd "$REPO_ROOT"
    ./Scripts/build-rust-universal.sh release
    log_success "Rust universal libraries built"
else
    log_warning "Skipping Rust build"
    if [[ ! -d "$REPO_ROOT/build/xcframework-staging" ]]; then
        log_error "Staging directory not found. You must run build-rust-universal.sh first."
        exit 1
    fi
fi

# ============================================================================
# Step 4: Create XCFramework
# ============================================================================

log_step "Step 4: Creating XCFramework"

if ask_yes_no "Create XCFramework?" y; then
    cd "$REPO_ROOT"
    ./Scripts/build-xcframework.sh release "$VERSION"
    log_success "XCFramework created"
else
    log_warning "Skipping XCFramework creation"
fi

# ============================================================================
# Step 5: Verify Build Artifacts
# ============================================================================

log_step "Step 5: Verifying build artifacts"

EXPECTED_FILES=(
    "build/xcframework/C6PProtocol.xcframework"
    "build/xcframework/C6PProtocol-$VERSION.xcframework.zip"
    "build/xcframework/checksums.txt"
    "build/xcframework/c6p_ios.swift"
)

ALL_EXIST=true
for file in "${EXPECTED_FILES[@]}"; do
    if [[ -e "$REPO_ROOT/$file" ]]; then
        log_success "Found: $file"
    else
        log_error "Missing: $file"
        ALL_EXIST=false
    fi
done

if [[ "$ALL_EXIST" != true ]]; then
    log_error "Some build artifacts are missing"
    exit 1
fi

# Show file sizes
echo ""
log_info "Build artifact sizes:"
du -h "$REPO_ROOT/build/xcframework/C6PProtocol-$VERSION.xcframework.zip"
du -sh "$REPO_ROOT/build/xcframework/C6PProtocol.xcframework"

# Show checksum
echo ""
log_info "Checksum:"
cat "$REPO_ROOT/build/xcframework/checksums.txt" | grep SHA-256 -A1 | tail -1

# ============================================================================
# Step 6: Create Git Tag
# ============================================================================

log_step "Step 6: Git tag creation"

TAG_NAME="v$VERSION"

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    log_warning "Tag $TAG_NAME already exists"
    if ask_yes_no "Delete existing tag and recreate?"; then
        git tag -d "$TAG_NAME"
        if git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"; then
            log_warning "Tag also exists on remote"
            if ask_yes_no "Delete remote tag?"; then
                git push --delete origin "$TAG_NAME"
            fi
        fi
    else
        log_info "Using existing tag"
    fi
fi

if ! git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    if ask_yes_no "Create git tag $TAG_NAME?" y; then
        git tag -a "$TAG_NAME" -m "Release version $VERSION"
        log_success "Created tag: $TAG_NAME"
    fi
fi

# ============================================================================
# Step 7: Push Tag (Optional)
# ============================================================================

log_step "Step 7: Push to remote (optional)"

echo ""
log_info "Next steps:"
echo "  1. Review build artifacts in: $REPO_ROOT/build/xcframework/"
echo "  2. Test XCFramework locally"
echo "  3. Push tag to trigger release workflow:"
echo ""
echo "     ${CYAN}git push origin $TAG_NAME${NC}"
echo ""
echo "  4. Monitor GitHub Actions: https://github.com/convro/convro-6-protocol/actions"
echo "  5. Verify release: https://github.com/convro/convro-6-protocol/releases"
echo ""

if ask_yes_no "Push tag to remote now?" n; then
    git push origin "$TAG_NAME"
    log_success "Tag pushed! GitHub Actions workflow will start shortly."
    echo ""
    log_info "Monitor progress at: https://github.com/convro/convro-6-protocol/actions"
else
    log_info "Tag NOT pushed. You can push later with:"
    echo "  git push origin $TAG_NAME"
fi

# ============================================================================
# Summary
# ============================================================================

log_step "Release Preparation Complete! 🎉"

cat << EOF

====================================================================
  C6P Protocol v$VERSION - Local Build Summary
====================================================================

  Status:        SUCCESS ✓
  Framework:     C6PProtocol.xcframework
  Package:       C6PProtocol-$VERSION.xcframework.zip
  Git Tag:       $TAG_NAME (local)

  Build Output:  $REPO_ROOT/build/xcframework/

====================================================================

To complete the release:

  1. Test locally:
     • Import XCFramework in a test iOS project
     • Verify all APIs work correctly

  2. Push tag to trigger GitHub Actions:
     git push origin $TAG_NAME

  3. After release completes:
     • Download Package.swift.release from GitHub
     • Commit updated Package.swift to main
     • Announce release (if applicable)

====================================================================
EOF

# ============================================================================
# Optional: Open build directory
# ============================================================================

if command -v open &> /dev/null; then
    if ask_yes_no "Open build directory in Finder?" n; then
        open "$REPO_ROOT/build/xcframework/"
    fi
fi
