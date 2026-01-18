#!/bin/bash
# Build script for InvoiceFiler Release .app
# Usage: ./build.sh [--sign IDENTITY]

set -e

PROJECT="InvoiceFiler.xcodeproj"
SCHEME="InvoiceFiler"
CONFIGURATION="Release"
BUILD_DIR="./build"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
APP_NAME="InvoiceFiler.app"

# Parse arguments
SIGNING_IDENTITY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--sign IDENTITY]"
            exit 1
            ;;
    esac
done

echo "=== InvoiceFiler Release Build ==="
echo "Configuration: $CONFIGURATION"
echo "Output: $BUILD_DIR/$APP_NAME"
echo ""

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo "Cleaning previous build..."
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

# Build the app
echo "Building $SCHEME..."
echo ""

BUILD_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR"
)

# Add code signing if identity provided
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with identity: $SIGNING_IDENTITY"
    BUILD_ARGS+=(
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
        CODE_SIGNING_REQUIRED=YES
    )
else
    echo "Building without code signing (use --sign IDENTITY to sign)"
    BUILD_ARGS+=(
        CODE_SIGN_IDENTITY="-"
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
    )
fi

echo ""

xcodebuild "${BUILD_ARGS[@]}" build

# Verify output
if [ -d "$BUILD_DIR/$APP_NAME" ]; then
    echo ""
    echo "=== Build Successful ==="
    echo "Output: $BUILD_DIR/$APP_NAME"
    ls -lh "$BUILD_DIR/$APP_NAME"

    # Show signing status
    if codesign -dv "$BUILD_DIR/$APP_NAME" 2>/dev/null; then
        echo ""
        echo "App is code signed"
    else
        echo ""
        echo "App is not code signed"
    fi
else
    echo ""
    echo "ERROR: Build completed but $APP_NAME not found in $BUILD_DIR"
    exit 1
fi
