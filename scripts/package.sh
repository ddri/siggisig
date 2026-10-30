#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# SiggiSig Packaging & Release Script
# Builds, signs, bundles, and creates a distributable DMG for SiggiSig.
# -----------------------------------------------------------------------------

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

CONFIG="Release"
CREATE_DMG=true
SIGN_IDENTITY=""
NOTARIZE_PROFILE=""

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -c, --config <Config>       Build configuration (Release or Debug, default: Release)
    -s, --sign <Identity>       Code signing identity (name or SHA-1 hash)
                                Defaults to Developer ID, then Apple Development, then ad-hoc (-)
    -n, --notarize <Profile>    Notarize DMG with xcrun notarytool using specified Keychain profile
    --no-dmg                    Skip DMG creation (only output dist/SiggiSig.app)
    -h, --help                  Show this help message

Examples:
    ./scripts/package.sh
    ./scripts/package.sh --sign "Apple Development: you@example.com"
    ./scripts/package.sh --sign "Developer ID Application: Company" --notarize "AC_PROFILE"
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG="$2"
            shift 2
            ;;
        -s|--sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        -n|--notarize)
            NOTARIZE_PROFILE="$2"
            shift 2
            ;;
        --no-dmg)
            CREATE_DMG=false
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_usage
            exit 1
            ;;
    esac
done

echo "=================================================="
echo "  SiggiSig Packaging"
echo "=================================================="
echo "Project Directory: $PROJECT_DIR"
echo "Configuration:     $CONFIG"

# 1. Determine signing identity if not explicitly provided
if [[ -z "$SIGN_IDENTITY" ]]; then
    # Check for Developer ID Application
    DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | awk -F '"' '{print $2}' || true)
    # Check for Apple Development
    DEV_APPLE=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | awk -F '"' '{print $2}' || true)

    if [[ -n "$DEV_ID" ]]; then
        SIGN_IDENTITY="$DEV_ID"
        echo "Signing Identity:  $SIGN_IDENTITY (Auto-detected Developer ID)"
    elif [[ -n "$DEV_APPLE" ]]; then
        SIGN_IDENTITY="$DEV_APPLE"
        echo "Signing Identity:  $SIGN_IDENTITY (Auto-detected Development)"
    else
        SIGN_IDENTITY="-"
        echo "Signing Identity:  - (Ad-hoc signing, no certificate found)"
    fi
else
    echo "Signing Identity:  $SIGN_IDENTITY (User-specified)"
fi

# 2. Clean and build with xcodebuild
# Uses the committed SiggiSig.xcodeproj. Do not run `xcodegen generate` here:
# it resets code signing and forces Screen Recording to be re-authorized.
BUILD_DIR="$PROJECT_DIR/build/DerivedData"
DIST_DIR="$PROJECT_DIR/dist"
mkdir -p "$DIST_DIR"

echo ""
echo "-> Building SiggiSig ($CONFIG)..."
xcodebuild -project SiggiSig.xcodeproj \
           -scheme SiggiSig \
           -configuration "$CONFIG" \
           -derivedDataPath "$BUILD_DIR" \
           clean build \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

BUILT_APP="$BUILD_DIR/Build/Products/$CONFIG/SiggiSig.app"
TARGET_APP="$DIST_DIR/SiggiSig.app"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Error: Built application not found at $BUILT_APP" >&2
    exit 1
fi

# 3. Copy to dist/
echo ""
echo "-> Copying application bundle to dist/..."
rm -rf "$TARGET_APP"
cp -R "$BUILT_APP" "$TARGET_APP"

# Extract Version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET_APP/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
echo "Application Version: $VERSION"

# 4. Codesign with Hardened Runtime & Entitlements
echo ""
echo "-> Signing $TARGET_APP..."
ENTITLEMENTS="$PROJECT_DIR/SiggiSig/SiggiSig.entitlements"

SIGN_FLAGS=(--force --deep)
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi

if [[ -f "$ENTITLEMENTS" ]]; then
    SIGN_FLAGS+=(--entitlements "$ENTITLEMENTS")
fi

codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$TARGET_APP"

echo "-> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$TARGET_APP"
echo "Code signature valid!"

# 5. Create DMG if requested
DMG_PATH="$DIST_DIR/SiggiSig-${VERSION}.dmg"
if [[ "$CREATE_DMG" == true ]]; then
    echo ""
    echo "-> Creating distributable DMG ($DMG_PATH)..."
    STAGING_DIR="$DIST_DIR/dmg_staging"
    rm -rf "$STAGING_DIR" "$DMG_PATH"
    mkdir -p "$STAGING_DIR"

    # Copy App and link /Applications
    cp -R "$TARGET_APP" "$STAGING_DIR/SiggiSig.app"
    ln -s /Applications "$STAGING_DIR/Applications"

    hdiutil create -volname "SiggiSig" \
                   -srcfolder "$STAGING_DIR" \
                   -ov \
                   -format UDZO \
                   "$DMG_PATH"

    rm -rf "$STAGING_DIR"

    # Sign DMG if a real identity is used
    if [[ "$SIGN_IDENTITY" != "-" ]]; then
        echo "-> Signing DMG..."
        codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
    fi

    echo "DMG created successfully: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
fi

# 6. Notarize if profile provided
if [[ -n "$NOTARIZE_PROFILE" ]]; then
    if [[ "$CREATE_DMG" != true ]]; then
        echo "Error: Notarization requires a DMG package." >&2
        exit 1
    fi
    echo ""
    echo "-> Submitting $DMG_PATH to Apple notary service..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait

    echo "-> Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
    echo "Notarization and stapling complete!"
fi

echo ""
echo "=================================================="
echo "  Build & Packaging Succeeded! 🎉"
echo "=================================================="
echo "App bundle: $TARGET_APP"
if [[ "$CREATE_DMG" == true ]]; then
    echo "Disk image: $DMG_PATH"
fi
echo ""
echo "To test run locally:"
echo "  open \"$TARGET_APP\""
echo "=================================================="
