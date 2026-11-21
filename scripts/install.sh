#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacChargingSpeed"
REPO="CaptainCompileon/mac-charging-speed-widget"

echo "⚡ Installing ${APP_NAME}..."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: ${APP_NAME} is a native macOS app and must be installed on macOS (14.0+)."
  exit 1
fi

# Ensure Xcode command line tools & full Xcode are available
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Please install Xcode from the Mac App Store first."
  exit 1
fi

# Ensure XcodeGen is installed
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen via Homebrew..."
    brew install xcodegen
  else
    echo "Error: XcodeGen is required. Install Homebrew (https://brew.sh) then run: brew install xcodegen"
    exit 1
  fi
fi

WORKDIR="$(pwd)"
CLEANUP_DIR=""

if [[ ! -f "${WORKDIR}/project.yml" ]]; then
  CLEANUP_DIR="$(mktemp -d)"
  echo "Cloning ${REPO}..."
  git clone --depth 1 "https://github.com/${REPO}.git" "${CLEANUP_DIR}/repo"
  cd "${CLEANUP_DIR}/repo"
fi

trap '[[ -n "${CLEANUP_DIR}" ]] && rm -rf "${CLEANUP_DIR}"' EXIT

echo "Generating Xcode project..."
xcodegen generate

echo "Building Release bundle (Universal / native macOS)..."
xcodebuild -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  build | tail -n 20

APP_BUNDLE="build/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "Error: Build succeeded but ${APP_BUNDLE} was not found."
  exit 1
fi

echo "Installing to /Applications/${APP_NAME}.app..."
pkill -x "${APP_NAME}" 2>/dev/null || true
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"
xattr -dr com.apple.quarantine "/Applications/${APP_NAME}.app" 2>/dev/null || true

echo "Launching ${APP_NAME}..."
open "/Applications/${APP_NAME}.app"

echo ""
echo "✅ ${APP_NAME} is installed and running in your menu bar!"
echo "👉 To add Desktop Widgets: Right-click your desktop → Edit Widgets → search 'MacChargingSpeed'."
