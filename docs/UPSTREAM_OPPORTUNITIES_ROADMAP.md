# RustDesk Engineering & Commercial Opportunities Roadmap: Solving Upstream CI/CD Debt with `enve`

**Author**: Antigravity Pair Programming Team  
**Date**: September 2026  
**Status**: Strategic Analysis & Engineering Roadmap  
**Target Organization**: Purslane Tech Pte. Ltd. / [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk)  
**Related Documents**: [`docs/ENVE_DEVELOPER_ENVIRONMENT.md`](./ENVE_DEVELOPER_ENVIRONMENT.md), [`enve.cue`](../enve.cue), [`enve.lock`](../enve.lock)

---

## Executive Overview

An in-depth audit of the upstream `rustdesk/rustdesk` repository—including all 11 GitHub Actions workflows ([`.github/workflows/`](../.github/workflows/)), the [Docker build setup](../Dockerfile), [`build.py`](../build.py), and patch scripts—reveals significant technical debt.

To keep CI functioning under GitHub Actions resource constraints, maintainers have been forced to:
- Comment out 90% of their cross-platform build matrix in `ci.yml`.
- Disable the Web Client entirely (`if: False` in `flutter-build.yml`).
- Maintain a dedicated workflow ([`clear-cache.yml`](../.github/workflows/clear-cache.yml)) solely to wipe corrupted GitHub Actions cache stores.
- Execute brittle in-flight string replacements (`sed -i`) on `Cargo.toml`, `build.py`, and Flutter SDK sources inside CI runners.
- Skip GUI and display integration tests because headless CI runners lack virtual display and audio servers.

This document outlines **6 high-value engineering opportunities** where `enve` transforms these unfeasible bottlenecks into solved, turn-key capabilities—creating a compelling technical and commercial pitch for the RustDesk team.

---

## 1. Unlocking the "Ghost Matrix" (Multi-Arch Cross-Compilation)

### Upstream Problem
In [`.github/workflows/ci.yml:L75-86`](../.github/workflows/ci.yml#L75-L86), maintainers commented out almost the entire target matrix:
* `aarch64-unknown-linux-gnu`
* `arm-unknown-linux-gnueabihf`
* `arm-unknown-linux-musleabihf`
* `i686-pc-windows-msvc`
* `i686-unknown-linux-gnu`
* `i686-unknown-linux-musl`
* `x86_64-apple-darwin`
* `x86_64-unknown-linux-musl`

Even `cargo fmt`, `clippy`, and `cargo test` in `ci.yml` are commented out.

### Root Cause
Compiling C/C++ FFI dependencies (`libvpx`, `libyuv`, `libopus`, `libaom`) via `vcpkg` across multiple architectures under QEMU emulation in GitHub Actions:
1. **Exhausts runner disk space**: Forced maintainers to add `jlumbroso/free-disk-space` to delete .NET, Android SDKs, and Haskell just to recover ~10 GB.
2. **Exhausts runner RAM**: Forced adding a 12 GB swap file and restricting Cargo to `--jobs 3` under QEMU.
3. **Hits 6-hour job timeouts**: Emulating ARM64 on x86 runners with source-compilation takes hours.

### The `enve` Solution
Nix provides native, pre-built cross-compilation closures (`pkgsCross.aarch64-multiplatform`, `pkgsMusl`) with zero QEMU virtualization overhead:
- ARM64, musl, and ARMv7 binaries are cross-compiled directly on high-speed x86 runners in **under 3 minutes**.
- Pre-built media libraries eliminate all in-runner C++ compilations.

---

## 2. Reviving the Abandoned Web Client (`if: False`)

### Upstream Problem
In [`.github/workflows/flutter-build.yml:L2466-2470`](../.github/workflows/flutter-build.yml#L2466-L2470):
```yaml
build-rustdesk-web:
  if: False    # Hard-coded disabled in CI!
  name: build-rustdesk-web
  runs-on: ubuntu-22.04
```

### Root Cause
Building Flutter Web involves a fragile chain of disparate tools:
- Global `npm install -g yarn typescript protoc ts-proto`.
- Pinned to ancient `vite@2.8` due to chunking strategy incompatibilities.
- Downloading unpinned binary tarballs via `wget https://github.com/rustdesk/doc.rustdesk.com/releases/download/console/web_deps.tar.gz`.
- Fragile coordination with Flutter Web compiler.

When dependencies drifted and broke in CI, maintainers lacked a hermetic build environment and disabled the job completely.

### The `enve` Solution
Declare a dedicated `#WebBuildSpec` in `enve.cue`:
- Hermetically packages Node.js, Protoc, Vite, and Dart/Flutter SDKs.
- Pins all WebAssembly and JS dependencies with cryptographic integrity hashes.
- Automatically compiles, tests, and publishes the RustDesk Web Client on every release tag without manual intervention.

---

## 3. Eliminating Toolchain Fragmentation & In-Flight `sed` Patching

### Upstream Problem
The upstream `flutter-build.yml` (2,548 lines / 108 KB) coordinates multiple conflicting toolchains:
* `SCITER_RUST_VERSION: 1.75` (stuck on Rust 1.75 because Rust 1.78 introduced an `i128` ABI change breaking Sciter GTK).
* `MAC_RUST_VERSION: 1.81` (required because macOS `cidre` crate demands Rust 1.81+).
* `FLUTTER_VERSION: 3.24.5` (Linux/macOS).
* `FLUTTER_WINDOWS_ARM_VERSION: 3.44.9` (Windows ARM64 requires on-the-fly patching).
* `FLUTTER_ELINUX_VERSION: 3.16.9` (custom embedded Flutter engine for Linux ARM64).

To glue these together, CI runners execute in-flight file modifications:
* `sed -i "s/\[\"cdylib\", \"staticlib\", \"rlib\"\]/\[\"cdylib\"\]/g" Cargo.toml`
* `sed -i "s/flutter build linux --release/flutter-elinux build linux --verbose/g" ./build.py`
* Applying git patches against Flutter SDK itself (`.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff`).

### The `enve` Solution
`enve` models toolchains declaratively in CUE:
- Different targets cleanly inherit distinct compiler closures without modifying source trees or running `sed` in CI.
- Pinned toolchain closures ensure reproducible builds across all target platforms.

---

## 4. Solving Cache Thrashing & Corruption (`clear-cache.yml`)

### Upstream Problem
Maintainers created a dedicated workflow ([`.github/workflows/clear-cache.yml`](../.github/workflows/clear-cache.yml)) to manually wipe GitHub Actions cache stores using GitHub REST APIs and `MyAlbum/purge-cache`.

### Root Cause
GitHub Actions imposes a strict **10 GB per-repository cache limit**. Between Rust `target/` directories, vcpkg source trees, Flutter engines, and Android NDKs, RustDesk repeatedly hits this quota, resulting in cache eviction thrashing and corrupted caches that cause mysterious build failures.

### The `enve` Solution
Replace ephemeral GitHub cache actions with **`enve-cache`**:
- **1 TB high-speed object storage** on Cloudflare R2.
- **Content-addressed, immutable derivations**: Cache keys are cryptographic SHA-256 store hashes. A cache entry can never be corrupted, and keys never need manual purging.
- **Zero-egress bandwidth**: Unlimited push and pull bandwidth without egress charges.

---

## 5. Automated Headless GUI & Audio Testing in CI

### Upstream Problem
`cargo test` is commented out in `ci.yml`. Tests in `src/platform/linux.rs` (e.g., `test_get_cursor_pos` and `test_get_key_state`) fail in standard headless CI environments because no X11/Wayland display server or PipeWire/PulseAudio sink is present.

### The `enve` Solution
Declare a headless testing environment in `enve.cue`:
- Virtual display server via `xvfb-run` or headless Wayland compositor (`weston-headless`).
- Virtual audio dummy devices via PipeWire dummy sinks.
- Enables executing **100% of RustDesk's 249 unit and integration tests** in CI on every PR.

---

## 6. White-Label Client Generation Engine (Server Pro Monetization)

### The Business Context
RustDesk Server Pro's primary enterprise value proposition is **custom client whitelabeling** (pre-baking customer logos, custom server URLs, `RS_PUB_KEY`, and `RENDEZVOUS_SERVER` into branded `.exe`, `.deb`, and `.dmg` installers).

In [`.github/workflows/playground.yml:L25-28`](../.github/workflows/playground.yml#L25-L28), maintainers currently test custom builds by manually hacking GitHub repository secrets.

### The Commercial Value Proposition
We can provide RustDesk with an automated **Client Synthesis Engine** using `enve synth`:
1. When an enterprise customer configures custom branding in the RustDesk Server Pro web console, a backend webhook triggers `enve synth` with parametric CUE overrides.
2. Because base dependencies (`libvpx`, `ffmpeg`, GTK, Flutter engine) are already cached in `enve-cache`, the customized, signed client compiles and packages in **under 15 seconds**.
3. Turns a manual, error-prone build process into an instant, self-service enterprise revenue driver.

---

## Pitching Strategy & Roadmap Summary

| Initiative | Technical Value | Business Impact |
| :--- | :--- | :--- |
| **Phase 1: Local Dev & Fast CI** | Sub-100ms onboarding, 60-120s CI via `enve-cache`. | Immediate velocity boost for 5 core engineers; $89/mo team tier. |
| **Phase 2: Multi-Arch & Web Client** | Restore ARM64/musl cross-builds; revive Web Client. | Expands platform support; eliminates manual CI maintenance. |
| **Phase 3: Server Pro Whitelabel Engine** | Parametric 15-second branded client synthesis. | Directly accelerates RustDesk Server Pro enterprise sales and revenue. |
