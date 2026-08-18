#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-debug}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

swift build --package-path "$PACKAGE_DIR" --configuration "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" --configuration "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PACKAGE_DIR/.build/AegisDesktop.app"
CONTENTS_DIR="$APP_DIR/Contents"

/bin/mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
/usr/bin/ditto "$PACKAGE_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/bin/ditto "$BIN_DIR/AegisDesktop" "$CONTENTS_DIR/MacOS/AegisDesktop"
/usr/bin/codesign --force --sign - --identifier com.aegis.local "$APP_DIR"

echo "$APP_DIR"
