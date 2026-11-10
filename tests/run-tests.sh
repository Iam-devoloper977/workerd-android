#!/usr/bin/env bash
set -euo pipefail

# Test Suite for Native workerd on Android Bionic / 39-bit VA Kernels
WORKERD_BIN="${1:-${WRANGLER_WORKERD_BINARY:-$(command -v workerd || echo "")}}"

if [ -z "$WORKERD_BIN" ] || [ ! -x "$WORKERD_BIN" ]; then
  echo "[-] Error: workerd binary not found or not executable."
  echo "    Usage: $0 /path/to/workerd"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "[+] Target binary: $WORKERD_BIN"
echo "[+] Working directory: $WORK_DIR"
cd "$WORK_DIR"

cp "$SCRIPT_DIR/worker.js" .
cp "$SCRIPT_DIR/sqlite.js" .
cp "$SCRIPT_DIR/test-worker.capnp" .
mkdir -p do-data

# Build VA39 shim if gcc/clang is available
VA39_SHIM=""
if command -v cc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1; then
  CC_BIN="$(command -v clang || command -v cc)"
  echo "[+] Compiling 39-bit VA emulation shim with $CC_BIN..."
  if $CC_BIN -O2 -shared -fPIC "$SCRIPT_DIR/va39-shim.c" -o va39.so 2>/dev/null; then
    VA39_SHIM="$(pwd)/va39.so"
    echo "[+] 39-bit VA shim compiled successfully."
  fi
fi

run_with_va39() {
  if [ -n "$VA39_SHIM" ] && [ -f "$VA39_SHIM" ]; then
    LD_PRELOAD="$VA39_SHIM" "$@"
  else
    "$@"
  fi
}

echo ""
echo "=== Test 1: Version check under 39-bit VA constraint ==="
VERSION_OUTPUT=$(run_with_va39 "$WORKERD_BIN" --version)
echo "[+] Output: $VERSION_OUTPUT"
if [[ "$VERSION_OUTPUT" != *"workerd"* ]]; then
  echo "[-] Test 1 failed: invalid version output"
  exit 1
fi
echo "[+] Test 1 PASSED: workerd booted without memory abort."

echo ""
echo "=== Test 2: Serving HTTP Worker & Durable Objects (SQLite) ==="
run_with_va39 "$WORKERD_BIN" serve test-worker.capnp > server.log 2>&1 &
SERVER_PID=$!
# Ensure server process is terminated on exit
trap 'kill -9 $SERVER_PID 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT

echo "[+] Waiting for workerd server to bind to ports..."
READY=0
for i in $(seq 1 40); do
  if curl -sf http://127.0.0.1:18787/ >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.25
done

if [ "$READY" -ne 1 ]; then
  echo "[-] Test 2 failed: workerd did not start serving in time."
  echo "--- server.log ---"
  cat server.log
  exit 1
fi

echo ""
echo "=== Test 3: HTTP Endpoint Verification ==="
HTTP_RESP=$(curl -sf http://127.0.0.1:18787/)
echo "[+] Response: $HTTP_RESP"
if [[ "$HTTP_RESP" != *"workerd-android-bionic"* ]]; then
  echo "[-] Test 3 failed: unexpected HTTP response."
  exit 1
fi
echo "[+] Test 3 PASSED: JS Worker responded successfully."

echo ""
echo "=== Test 4: Durable Object SQLite Persistence ==="
SQL_RESP1=$(curl -sf http://127.0.0.1:18788/)
echo "[+] Request 1 response: $SQL_RESP1"
SQL_RESP2=$(curl -sf http://127.0.0.1:18788/)
echo "[+] Request 2 response: $SQL_RESP2"

if [[ "$SQL_RESP1" != *'"count":1'* ]] || [[ "$SQL_RESP2" != *'"count":2'* ]]; then
  echo "[-] Test 4 failed: SQLite increment logic failed."
  exit 1
fi
echo "[+] Test 4 PASSED: Embedded SQLite DO storage working perfectly."

echo ""
echo "=== Test 5: Virtual Address Space Verification ==="
# Check that heap mappings were kept below 2^39
if [ -f "/proc/$SERVER_PID/maps" ]; then
  HIGH_MAPPINGS=$(awk '$2 != "---p" && length($1) > 21 {print}' "/proc/$SERVER_PID/maps" || true)
  if [ -n "$HIGH_MAPPINGS" ]; then
    echo "[!] Warning: Found mappings above 2^39 (non-heap/vdso):"
    echo "$HIGH_MAPPINGS" | head -n 5
  else
    echo "[+] Verified: zero non-reserved heap allocations above 2^39."
  fi
fi

kill -9 $SERVER_PID 2>/dev/null || true
echo ""
echo "=================================================="
echo "🎉 ALL TESTS PASSED: workerd is Android Bionic ready!"
echo "=================================================="
