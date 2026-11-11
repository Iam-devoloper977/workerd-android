#!/usr/bin/env bash
set -euo pipefail

# Workerd Native Android ARM64 Installer for Termux
# Repository: https://github.com/Iam-devoloper977/workerd-android

REPO="Iam-devoloper977/workerd-android"
TARGET_DIR="${HOME}/.local/bin"
TARGET_BIN="${TARGET_DIR}/workerd"

echo "=========================================================="
echo " Cloudflare workerd Native Installer for Android (Termux)"
echo "=========================================================="

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "[-] Error: Unsupported architecture '$ARCH'. Only aarch64/arm64 is supported."
  exit 1
fi

mkdir -p "$TARGET_DIR"

echo "[+] Fetching latest release info from $REPO..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)

if [ -z "$RELEASE_JSON" ] || [ "$RELEASE_JSON" = "null" ]; then
  # Fallback to direct download URL if API rate-limited
  echo "[!] GitHub API rate-limited, falling back to latest release asset..."
  DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/workerd-android-arm64.tar.gz"
else
  TAG_NAME=$(echo "$RELEASE_JSON" | grep -m1 '"tag_name":' | cut -d'"' -f4)
  echo "[+] Found release: $TAG_NAME"
  DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep "browser_download_url.*workerd-android-arm64.tar.gz" | cut -d'"' -f4)
  if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG_NAME}/workerd-android-arm64.tar.gz"
  fi
fi

echo "[+] Downloading workerd from $DOWNLOAD_URL..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/workerd.tar.gz"
tar -xzf "$TMP_DIR/workerd.tar.gz" -C "$TMP_DIR"

if [ -f "$TMP_DIR/workerd" ]; then
  mv "$TMP_DIR/workerd" "$TARGET_BIN"
elif [ -f "$TMP_DIR/workerd-linux-arm64" ]; then
  mv "$TMP_DIR/workerd-linux-arm64" "$TARGET_BIN"
fi
chmod +x "$TARGET_BIN"

echo "[+] Installed binary to $TARGET_BIN"

# Idempotently configure environment variables in ~/.bashrc
BASHRC="${HOME}/.bashrc"
touch "$BASHRC"

ENV_LINE_WRANGLER='export WRANGLER_WORKERD_BINARY="$HOME/.local/bin/workerd"'
ENV_LINE_MINIFLARE='export MINIFLARE_WORKERD_PATH="$HOME/.local/bin/workerd"'
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

if ! grep -q "WRANGLER_WORKERD_BINARY" "$BASHRC"; then
  echo "" >> "$BASHRC"
  echo "# Cloudflare workerd native Android ARM64 overrides" >> "$BASHRC"
  echo "$PATH_LINE" >> "$BASHRC"
  echo "$ENV_LINE_WRANGLER" >> "$BASHRC"
  echo "$ENV_LINE_MINIFLARE" >> "$BASHRC"
  echo "[+] Added WRANGLER_WORKERD_BINARY and MINIFLARE_WORKERD_PATH to $BASHRC"
else
  echo "[+] Environment variables already present in $BASHRC"
fi

export WRANGLER_WORKERD_BINARY="$TARGET_BIN"
export MINIFLARE_WORKERD_PATH="$TARGET_BIN"
export PATH="$TARGET_DIR:$PATH"

echo ""
echo "[+] Verifying workerd binary..."
if "$TARGET_BIN" --version 2>/dev/null; then
  echo ""
  echo "=========================================================="
  echo "🎉 Installation Successful!"
  echo "Native workerd is ready. You can now run:"
  echo "    npx wrangler dev"
  echo "without PRoot, Glibc shims, or 39-bit VA kernel aborts."
  echo "=========================================================="
elif [ -x /system/bin/linker64 ] && /system/bin/linker64 "$TARGET_BIN" --version >/dev/null 2>&1; then
  mv "$TARGET_BIN" "${TARGET_BIN}.real"
  cat > "$TARGET_BIN" << 'WRAPPER'
#!/usr/bin/env bash
exec /system/bin/linker64 "${BASH_SOURCE[0]}.real" "$@"
WRAPPER
  chmod +x "$TARGET_BIN" "${TARGET_BIN}.real"
  echo ""
  echo "=========================================================="
  echo "🎉 Installation Successful (configured with Bionic linker64 wrapper)!"
  echo "Native workerd is ready. You can now run:"
  echo "    npx wrangler dev"
  echo "without PRoot, Glibc shims, or 39-bit VA kernel aborts."
  echo "=========================================================="
else
  echo "[-] Warning: Failed to execute $TARGET_BIN."
fi
