#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-debug}"
SIGNING_IDENTITY="${AEGIS_CODESIGN_IDENTITY:-}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "AegisDesktop development signing identity is not configured." >&2
  echo "Export AEGIS_CODESIGN_IDENTITY with an Apple Development certificate SHA-1." >&2
  echo "Example: export AEGIS_CODESIGN_IDENTITY=<certificate-sha1>" >&2
  exit 3
fi

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
  echo "AEGIS_CODESIGN_IDENTITY does not match an available code-signing identity." >&2
  exit 4
fi

swift build --package-path "$PACKAGE_DIR" --configuration "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" --configuration "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PACKAGE_DIR/.build/AegisDesktop.app"
CONTENTS_DIR="$APP_DIR/Contents"

/bin/mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
/usr/bin/ditto "$PACKAGE_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/bin/ditto "$BIN_DIR/AegisDesktop" "$CONTENTS_DIR/MacOS/AegisDesktop"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier com.aegis.local "$APP_DIR"

SIGNING_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
TEAM_IDENTIFIER="$(print -r -- "$SIGNING_DETAILS" | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "AegisDesktop development signing diagnostics:" >&2
echo "  canonical app path: $APP_DIR" >&2
echo "  bundle identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS_DIR/Info.plist")" >&2
echo "  configured signing identity: $SIGNING_IDENTITY" >&2
echo "  TeamIdentifier: ${TEAM_IDENTIFIER:-not set}" >&2
echo "  signing verification: passed" >&2

echo "$APP_DIR"
