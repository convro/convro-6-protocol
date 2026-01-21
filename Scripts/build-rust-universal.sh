#!/bin/bash
#
# build-rust-universal.sh
# Compiles c6p-ios Rust library for all iOS architectures
#
# Usage: ./Scripts/build-rust-universal.sh [debug|release]
#
# Outputs:
#   - Universal static libraries for iOS
#   - UniFFI-generated Swift bindings
#   - C headers for XCFramework
#
# Requirements:
#   - Rust with iOS targets installed
#   - uniffi-bindgen CLI tool
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_DIR="$REPO_ROOT/rust"
C6P_IOS_DIR="$RUST_DIR/c6p-ios"

BUILD_MODE="${1:-release}"
BUILD_DIR="$REPO_ROOT/build"
OUTPUT_DIR="$BUILD_DIR/xcframework-staging"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# iOS Target Architectures
# ============================================================================

# iOS Device (ARM64)
TARGET_IOS_DEVICE="aarch64-apple-ios"

# iOS Simulator (ARM64 for Apple Silicon, x86_64 for Intel)
TARGET_IOS_SIM_ARM64="aarch64-apple-ios-sim"
TARGET_IOS_SIM_X86_64="x86_64-apple-ios"

# All targets
ALL_TARGETS=(
    "$TARGET_IOS_DEVICE"
    "$TARGET_IOS_SIM_ARM64"
    "$TARGET_IOS_SIM_X86_64"
)

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

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found"
        exit 1
    fi
}

# ============================================================================
# Validation
# ============================================================================

log_info "Starting Rust universal build for iOS..."
log_info "Build mode: $BUILD_MODE"
log_info "Repo root: $REPO_ROOT"

# Check required commands
check_command "cargo"
check_command "rustc"
check_command "lipo"

# Validate build mode
if [[ "$BUILD_MODE" != "debug" && "$BUILD_MODE" != "release" ]]; then
    log_error "Invalid build mode: $BUILD_MODE (must be 'debug' or 'release')"
    exit 1
fi

# Check if c6p-ios directory exists
if [[ ! -d "$C6P_IOS_DIR" ]]; then
    log_error "c6p-ios directory not found at: $C6P_IOS_DIR"
    exit 1
fi

# ============================================================================
# Install Rust Targets
# ============================================================================

log_info "Checking Rust targets..."

for target in "${ALL_TARGETS[@]}"; do
    if ! rustup target list --installed | grep -q "^${target}$"; then
        log_warning "Target $target not installed, installing..."
        rustup target add "$target"
    else
        log_success "Target $target already installed"
    fi
done

# ============================================================================
# Clean Previous Build
# ============================================================================

log_info "Cleaning previous build artifacts..."

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ============================================================================
# Build for Each Architecture
# ============================================================================

CARGO_FLAGS=""
if [[ "$BUILD_MODE" == "release" ]]; then
    CARGO_FLAGS="--release"
fi

TARGET_DIR="$RUST_DIR/target"
LIB_NAME="libc6p_ios.a"

log_info "Building Rust library for all targets..."

for target in "${ALL_TARGETS[@]}"; do
    log_info "Building for $target..."

    cd "$RUST_DIR"
    cargo build \
        --package c6p-ios \
        --lib \
        --target "$target" \
        $CARGO_FLAGS

    # Verify library exists
    LIB_PATH="$TARGET_DIR/$target/$BUILD_MODE/$LIB_NAME"
    if [[ ! -f "$LIB_PATH" ]]; then
        log_error "Build failed: library not found at $LIB_PATH"
        exit 1
    fi

    log_success "Built $target → $LIB_PATH"
done

# ============================================================================
# Create Universal Binaries with lipo
# ============================================================================

log_info "Creating universal binaries..."

# iOS Device (only ARM64, no need for lipo)
IOS_DEVICE_DIR="$OUTPUT_DIR/ios-arm64"
mkdir -p "$IOS_DEVICE_DIR"
cp "$TARGET_DIR/$TARGET_IOS_DEVICE/$BUILD_MODE/$LIB_NAME" "$IOS_DEVICE_DIR/$LIB_NAME"
log_success "iOS Device binary: $IOS_DEVICE_DIR/$LIB_NAME"

# iOS Simulator (ARM64 + x86_64 universal binary)
IOS_SIM_DIR="$OUTPUT_DIR/ios-arm64_x86_64-simulator"
mkdir -p "$IOS_SIM_DIR"

lipo -create \
    "$TARGET_DIR/$TARGET_IOS_SIM_ARM64/$BUILD_MODE/$LIB_NAME" \
    "$TARGET_DIR/$TARGET_IOS_SIM_X86_64/$BUILD_MODE/$LIB_NAME" \
    -output "$IOS_SIM_DIR/$LIB_NAME"

log_success "iOS Simulator universal binary: $IOS_SIM_DIR/$LIB_NAME"

# Verify lipo output
lipo -info "$IOS_SIM_DIR/$LIB_NAME"

# ============================================================================
# Generate UniFFI Bindings
# ============================================================================

log_info "Generating Swift bindings with UniFFI..."

cd "$C6P_IOS_DIR"

# Build uniffi-bindgen binary if not available
if ! command -v uniffi-bindgen &> /dev/null; then
    log_info "uniffi-bindgen not found, building from source..."
    cargo run --bin uniffi-bindgen -- generate --library "$TARGET_DIR/$TARGET_IOS_DEVICE/$BUILD_MODE/$LIB_NAME" --language swift --out-dir "$OUTPUT_DIR/bindings" src/c6p_ios.udl
else
    uniffi-bindgen generate --library "$TARGET_DIR/$TARGET_IOS_DEVICE/$BUILD_MODE/$LIB_NAME" --language swift --out-dir "$OUTPUT_DIR/bindings" src/c6p_ios.udl
fi

# Check if bindings were generated
SWIFT_FILE="$OUTPUT_DIR/bindings/c6p_ios.swift"
MODULEMAP_FILE="$OUTPUT_DIR/bindings/c6p_iosFFI.modulemap"
HEADER_FILE="$OUTPUT_DIR/bindings/c6p_iosFFI.h"

if [[ ! -f "$SWIFT_FILE" ]]; then
    log_error "Swift bindings not generated: $SWIFT_FILE"
    exit 1
fi

log_success "Generated Swift bindings: $SWIFT_FILE"

# Copy bindings to each architecture directory
for arch_dir in "$IOS_DEVICE_DIR" "$IOS_SIM_DIR"; do
    mkdir -p "$arch_dir/Headers"
    cp "$HEADER_FILE" "$arch_dir/Headers/" 2>/dev/null || log_warning "Header file not found, will use module.modulemap"
    cp "$MODULEMAP_FILE" "$arch_dir/" 2>/dev/null || log_warning "Modulemap not found"
    cp "$SWIFT_FILE" "$arch_dir/" 2>/dev/null || true
done

# ============================================================================
# Create Module Maps (if not generated by UniFFI)
# ============================================================================

create_modulemap() {
    local arch_dir=$1
    local modulemap_path="$arch_dir/module.modulemap"

    cat > "$modulemap_path" << 'EOF'
module c6p_iosFFI {
    header "Headers/c6p_iosFFI.h"
    export *
}
EOF

    log_success "Created module.modulemap for $(basename $arch_dir)"
}

# Create module maps if needed
if [[ ! -f "$IOS_DEVICE_DIR/c6p_iosFFI.modulemap" ]]; then
    create_modulemap "$IOS_DEVICE_DIR"
fi

if [[ ! -f "$IOS_SIM_DIR/c6p_iosFFI.modulemap" ]]; then
    create_modulemap "$IOS_SIM_DIR"
fi

# ============================================================================
# Summary
# ============================================================================

log_success "✓ Rust universal build completed!"
echo ""
log_info "Build artifacts:"
echo "  iOS Device:    $IOS_DEVICE_DIR"
echo "  iOS Simulator: $IOS_SIM_DIR"
echo "  Swift Source:  $SWIFT_FILE"
echo ""
log_info "Next step: Run build-xcframework.sh to create XCFramework"
