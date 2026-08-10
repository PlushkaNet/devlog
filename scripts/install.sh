#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/PlushkaNet/devlog"
REPO_BRANCH="master"
APP_USER="seclog"
APP_DIR="/opt/seclog"
DATA_DIR="/var/opt/seclog"
ENV_DIR="/etc/seclog"
ENV_FILE="$ENV_DIR/env"
UNIT_FILE="/etc/systemd/system/seclog.service"

FETCH_URL="$REPO_URL/archive/refs/heads/$REPO_BRANCH.zip"

fail() {
    echo "Fatal: $1" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail "This script must be run as root (sudo ./install.sh)"

echo "Checking environment..."
echo

REQUIRED=("curl" "unzip" "go" "useradd" "find" "systemctl" "install" "sha256sum")
for cmd in "${REQUIRED[@]}"; do
    printf "Checking $cmd..."
    command -v "$cmd" > /dev/null 2>&1 || {
        echo "failed"
        fail "$cmd is not installed. Install $cmd and run this script again"
    }
    echo "success"
done
echo

read -s -p "Admin password: " secret
echo
[ -n "$secret" ] || fail "Admin password must not be empty"

read -s -p "Confirm admin password: " confirm
echo
[ "$secret" = "$confirm" ] || fail "Admin password mismatch"

TMP_DIR=$(mktemp -d "/tmp/seclog.XXXXXXXXXXXXXXXXXX")
echo "Downloading zip archive from $FETCH_URL to $TMP_DIR"
curl -fsSLo $TMP_DIR/zip $FETCH_URL

echo "Extracting zip archive at $TMP_DIR/zip"
cd $TMP_DIR
unzip $TMP_DIR/zip
TMP_REPO=$(find . -maxdepth 1 -type d -name "*-$REPO_BRANCH" -exec realpath {} \; | head -n1)

if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
    echo "Create system user $APP_USER"
else
    echo "User $APP_USER was not created because it already exists"
fi

hash="$(printf '%s' "$secret" | sha256sum | cut -d' ' -f1)"

install -d -m 700 "$ENV_DIR"
install -m 600 /dev/null "$ENV_FILE"
printf 'SECRET_HASH=%s\n' "$hash" > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "Secret was saved at $ENV_FILE"

install -d -m 755 "$APP_DIR"
install -d -m 755 "$DATA_DIR"

echo "Compiling binary..."
( cd "$TMP_REPO/src" && CGO_ENABLED=0 go build -o "$APP_DIR/seclog" . )

install -m 644 "$TMP_REPO/static/404.html" "$TMP_REPO/static/login.html" "$APP_DIR/"
echo "Binary and build were installed into $APP_DIR"

chown -R "$APP_USER:$APP_USER" "$DATA_DIR"
echo "User $APP_USER now owns $DATA_DIR"

install -m 644 "$TMP_REPO/scripts/seclog.service" "$UNIT_FILE"
echo "Systemd unit-file was installed into $UNIT_FILE"

rm -rf $TMP_DIR
echo "$TMP_DIR was removed"

systemctl daemon-reload
systemctl enable seclog
systemctl restart seclog

echo
echo "Seclog service was installed and added to startup"
echo "Check service status:    systemctl status seclog"
echo "Check logs:              journalctl -u seclog -f"
