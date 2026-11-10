# workerd-android

Native **Cloudflare `workerd`** (the JavaScript/Wasm runtime powering Cloudflare Workers) compiled for **Android ARM64 (Bionic libc)** to run directly inside **Termux without PRoot or Glibc**.

---

## ⚡ Quick Start (Termux 1-Line Installer)

Run this command inside Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/Iam-devoloper977/workerd-android/main/install.sh | bash
```

This script:
1. Downloads the latest pre-compiled `workerd` ARM64 binary.
2. Installs it into `~/.local/bin/workerd`.
3. Adds `export WRANGLER_WORKERD_BINARY="$HOME/.local/bin/workerd"` and `export MINIFLARE_WORKERD_PATH="$HOME/.local/bin/workerd"` to `~/.bashrc`.
4. Tests binary execution natively (`workerd --version`).

Once installed, reload your shell or run `source ~/.bashrc`. You can now run `wrangler dev` in local mode seamlessly:

```bash
npx wrangler dev
```

---

## 🔍 Technical Hurdles Solved

### 1. 39-bit Virtual Address (VA) Space Kernel Abort
Standard upstream `workerd` links against Google TCMalloc, which reserves bits 42–44 in pointers for allocation metadata and asserts a 48-bit address space. Modern Android kernels (Snapdragon, MediaTek, Exynos on Android 10–14) are compiled with:

```text
CONFIG_ARM64_VA_BITS=39
```

When TCMalloc boots, its call to `MmapAligned()` fails because the top address bits cannot be mapped, causing an immediate kernel abort:

```text
external/com_google_tcmalloc/tcmalloc/system-alloc.cc:776] Note: the allocation may have failed because TCMalloc assumes a 48-bit virtual address space size
external/com_google_tcmalloc/tcmalloc/arena.cc:56] CHECK in Alloc: FATAL ERROR: Out of memory trying to allocate internal tcmalloc data
```

**Solution:** The patch sets `--@workerd//src/workerd/server:use_tcmalloc=False` and configures Bazel to use `@bazel_tools//tools/cpp:malloc`. This routes memory management to Android Bionic's system allocator (`malloc`/`free`), which runs cleanly on 39-bit VA spaces.

### 2. Android Bionic libc Compatibility
- Passes `-D__ANDROID_API__=29`, `-D__ANDROID__`, and `-D_GNU_SOURCE`.
- Resolves `<sys/ucontext.h>` architecture registers for AArch64 signal frames.
- Configures LLD linker flags (`-fuse-ld=lld`, `-Wl,-z,nocopyreloc`).

### 3. Wrangler & Miniflare NPM Integration
Upstream `@cloudflare/workerd` npm packages check `process.platform` and abort with `Unsupported platform: android arm64 LE`.
Our patch updates `npm/lib/node-platform.ts` and `npm/lib/node-install.ts` to recognize `android arm64 LE` and honor `WRANGLER_WORKERD_BINARY` and `MINIFLARE_WORKERD_PATH`.

---

## 🧪 Verification Test Suite

This repository includes a comprehensive test suite in `tests/run-tests.sh`:
1. **39-bit VA Emulation Shim (`tests/va39-shim.c`):** Uses an `LD_PRELOAD` constructor that maps `PROT_NONE` from `2^39` to `2^48` to emulate the exact memory bounds of an Android kernel on standard Linux runners.
2. **Runtime Boot Test:** Verifies `workerd --version` under the VA39 constraint.
3. **HTTP Server Test:** Spins up a live JS worker and asserts HTTP 200 responses.
4. **Durable Objects & SQLite Storage Test:** Tests persistent embedded SQLite queries inside a Durable Object.
5. **Memory Mapping Audit:** Inspects `/proc/$PID/maps` to verify zero non-reserved allocations above $2^{39}$.

Run tests locally:
```bash
bash tests/run-tests.sh ~/.local/bin/workerd
```

---

## 🤖 Automated Weekly Builds

The GitHub Actions workflow [`.github/workflows/weekly-build.yml`](.github/workflows/weekly-build.yml) automatically:
- Runs every Sunday at 00:00 UTC (`cron: '0 0 * * 0'`).
- Detects new release tags on [`cloudflare/workerd`](https://github.com/cloudflare/workerd).
- Applies `patches/workerd-android-bionic.patch`.
- Compiles the ARM64 binary natively on GitHub's `ubuntu-24.04-arm` runners.
- Executes the full 39-bit VA test suite.
- Publishes release archives (`workerd-android-arm64.tar.gz`) with SHA256 checksums.

---

## 📖 References & Community Credits
- Upstream Issue #5020: [TCMalloc assumes a 48-bit virtual address space size](https://github.com/cloudflare/workerd/issues/5020)
- Upstream Issue #5178: [Support arm64 android & termux](https://github.com/cloudflare/workerd/issues/5178)
- Community research: [coolcomfort/workerd-android-arm64](https://github.com/coolcomfort/workerd-android-arm64) & [greyoak111/workerd-android](https://github.com/greyoak111/workerd-android)
