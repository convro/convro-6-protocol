#!/bin/bash
#
# Build XCFramework for iOS (device + simulator)
#
# This script:
# 1. Builds c6p-ios for iOS device architectures (arm64)
# 2. Builds c6p-ios for iOS simulator architectures (x86_64, arm64)
# 3. Creates fat binaries for each platform
# 4. Generates Swift bindings using uniffi-bindgen
# 5. Packages everything into an XCFramework
#
# Requirements:
# - Rust toolchain with iOS targets installed
# - Xcode command line tools
# - uniffi-bindgen CLI tool
#
# Usage:
#   ./scripts/build-xcframework.sh [debug|release]

set -e

# Configuration
MODE="${1:-release}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$PROJECT_ROOT/c6p-ios"
BUILD_DIR="$IOS_DIR/build"
OUTPUT_DIR="$IOS_DIR/xcframework"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust/Cargo not found. Install from https://rustup.rs"
    exit 1
fi

# Check if required iOS targets are installed
TARGETS=(
    "aarch64-apple-ios"           # iOS device (arm64)
    "aarch64-apple-ios-sim"       # iOS simulator (arm64)
    "x86_64-apple-ios"            # iOS simulator (x86_64)
)

log_info "Checking Rust iOS targets..."
for target in "${TARGETS[@]}"; do
    if ! rustup target list --installed | grep -q "$target"; then
        log_warn "Target $target not installed. Installing..."
        rustup target add "$target"
    fi
done

log_success "All required targets installed"

# Clean previous build
log_info "Cleaning previous build..."
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Determine build flags
if [ "$MODE" = "release" ]; then
    CARGO_FLAGS="--release"
    TARGET_DIR="release"
else
    CARGO_FLAGS=""
    TARGET_DIR="debug"
fi

log_info "Building c6p-ios in $MODE mode..."

# Build for each target
cd "$PROJECT_ROOT"

log_info "Building for iOS device (aarch64)..."
cargo build -p c6p-ios --target aarch64-apple-ios $CARGO_FLAGS

log_info "Building for iOS simulator (aarch64)..."
cargo build -p c6p-ios --target aarch64-apple-ios-sim $CARGO_FLAGS

log_info "Building for iOS simulator (x86_64)..."
cargo build -p c6p-ios --target x86_64-apple-ios $CARGO_FLAGS

log_success "Rust libraries built successfully"

# Create fat binary for iOS simulator (combine x86_64 + arm64)
log_info "Creating fat binary for iOS simulator..."
mkdir -p "$BUILD_DIR/ios-simulator"
lipo -create \
    "$PROJECT_ROOT/target/x86_64-apple-ios/$TARGET_DIR/libc6p_ios.a" \
    "$PROJECT_ROOT/target/aarch64-apple-ios-sim/$TARGET_DIR/libc6p_ios.a" \
    -output "$BUILD_DIR/ios-simulator/libc6p_ios.a"

log_success "iOS simulator fat binary created"

# Copy iOS device binary
log_info "Copying iOS device binary..."
mkdir -p "$BUILD_DIR/ios-device"
cp "$PROJECT_ROOT/target/aarch64-apple-ios/$TARGET_DIR/libc6p_ios.a" \
   "$BUILD_DIR/ios-device/libc6p_ios.a"

log_success "iOS device binary copied"

# Generate Swift bindings
log_info "Generating Swift bindings..."
cd "$IOS_DIR"

# Build uniffi-bindgen binary if not available
if ! command -v uniffi-bindgen &> /dev/null; then
    log_warn "uniffi-bindgen not found. Building from source..."
    cargo install uniffi-bindgen --version 0.28
fi

# Generate Swift bindings
uniffi-bindgen generate src/c6p_ios.udl \
    --language swift \
    --out-dir "$BUILD_DIR/swift"

log_success "Swift bindings generated"

# Create module map for iOS device
log_info "Creating module maps..."
cat > "$BUILD_DIR/ios-device/module.modulemap" << EOF
module c6p_ios {
    header "c6p_iosFFI.h"
    export *
}
EOF

# Create module map for iOS simulator
cat > "$BUILD_DIR/ios-simulator/module.modulemap" << EOF
module c6p_ios {
    header "c6p_iosFFI.h"
    export *
}
EOF

# Copy headers
cp "$BUILD_DIR/swift/c6p_iosFFI.h" "$BUILD_DIR/ios-device/"
cp "$BUILD_DIR/swift/c6p_iosFFI.h" "$BUILD_DIR/ios-simulator/"
cp "$BUILD_DIR/swift/c6p_iosFFI.modulemap" "$BUILD_DIR/ios-device/" 2>/dev/null || true
cp "$BUILD_DIR/swift/c6p_iosFFI.modulemap" "$BUILD_DIR/ios-simulator/" 2>/dev/null || true

log_success "Module maps created"

# Create XCFramework
log_info "Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/ios-device/libc6p_ios.a" \
    -headers "$BUILD_DIR/ios-device" \
    -library "$BUILD_DIR/ios-simulator/libc6p_ios.a" \
    -headers "$BUILD_DIR/ios-simulator" \
    -output "$OUTPUT_DIR/c6p_ios.xcframework"

log_success "XCFramework created at $OUTPUT_DIR/c6p_ios.xcframework"

# Copy Swift source file
log_info "Copying Swift bindings..."
cp "$BUILD_DIR/swift/c6p_ios.swift" "$OUTPUT_DIR/"

log_success "Swift bindings copied to $OUTPUT_DIR/c6p_ios.swift"

# Print summary
echo ""
echo "======================================"
echo "✅ Build Complete!"
echo "======================================"
echo ""
echo "📦 XCFramework: $OUTPUT_DIR/c6p_ios.xcframework"
echo "🔧 Swift bindings: $OUTPUT_DIR/c6p_ios.swift"
echo ""
echo "To use in Xcode:"
echo "1. Drag c6p_ios.xcframework into your Xcode project"
echo "2. Add c6p_ios.swift to your project"
echo "3. Import: import c6p_ios"
echo ""
