#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_DIR="$($SCRIPT_DIR/build-app.sh "${1:-debug}" | /usr/bin/tail -n 1)"

/usr/bin/open "$APP_DIR"
echo "Launched $APP_DIR"
