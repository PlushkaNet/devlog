#!/usr/bin/env bash
set -euo pipefail

APP_USER="seclog"
APP_DIR="/opt/seclog"
DATA_DIR="/var/opt/seclog"
ENV_DIR="/etc/seclog"
UNIT_FILE="/etc/systemd/system/seclog.service"

fail() {
    echo "Fatal: $1" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail "This script must be run as root (sudo ./remove.sh)"

echo "Service is being stopped and disabled..."
systemctl stop seclog 2>/dev/null || true
systemctl disable seclog 2>/dev/null || true
rm -f "$UNIT_FILE"
systemctl daemon-reload
echo "Service stopped, unit-file deleted"

rm -rf "$ENV_DIR"
echo "Remove $ENV_DIR"

rm -rf "$DATA_DIR"
echo "Remove $DATA_DIR"

rm -rf "$APP_DIR"
echo "Remove $APP_DIR"

if id -u "$APP_USER" >/dev/null 2>&1; then
    userdel -r "$APP_USER"
    echo "Remove user $APP_USER"
else
    echo "User $APP_USER does not exist"
fi

echo
echo "Seclog uninstalled successfully"
