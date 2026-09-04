#!/usr/bin/env bash
# ==============================================================================
# RustDesk Parametric Whitelabel Client Synthesis Engine
#
# Generates turnkey branded RustDesk client packages (.deb and .rpm) with
# pre-baked rendezvous servers, public keys, and custom application branding
# in ~15-30 seconds, replacing upstream's 45-90 minute playground.yml rebuilds.
# ==============================================================================
set -euo pipefail

# Default Configuration
APP_NAME="RustDesk"
PACKAGE_NAME="rustdesk"
RENDEZVOUS_SERVER="rs-ny.rustdesk.com"
PUBLIC_KEY="OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw="
VERSION="1.5.0"
OUTPUT_DIR="dist/whitelabel"
ARCH="$(uname -m)"
BUILD_PROFILE="dev"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --app-name <name>           Branded Application Name (e.g. "Acme Remote")
  --package-name <pkg>        Package and binary name (e.g. "acme-remote")
  --rendezvous-server <host>  Enterprise ID / Rendezvous Server URL
  --public-key <key>          Enterprise Ed25519 Public Key
  --version <ver>             Package version (default: 1.5.0)
  --output-dir <dir>          Deliverable output directory (default: dist/whitelabel)
  --arch <arch>               Architecture (x86_64 or aarch64, default: $(uname -m))
  --profile <dev|release>     Cargo build profile (default: dev)
  -h, --help                  Show this help message
EOF
    exit 1
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        --package-name)
            PACKAGE_NAME="$2"
            shift 2
            ;;
        --rendezvous-server)
            RENDEZVOUS_SERVER="$2"
            shift 2
            ;;
        --public-key)
            PUBLIC_KEY="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --profile)
            BUILD_PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "❌ Unknown option: $1" >&2
            usage
            ;;
    esac
done

START_TIME=$(date +%s%N)

echo "========================================================================"
echo " 🚀 RustDesk Parametric Whitelabel Client Synthesis Engine"
echo "========================================================================"
echo " • App Name:          ${APP_NAME}"
echo " • Package Name:       ${PACKAGE_NAME}"
echo " • Rendezvous Server:  ${RENDEZVOUS_SERVER}"
echo " • Public Key:         ${PUBLIC_KEY:0:16}... (truncated)"
echo " • Target Arch:        ${ARCH}"
echo " • Version:            ${VERSION}"
echo " • Cargo Profile:      ${BUILD_PROFILE}"
echo " • Output Directory:   ${OUTPUT_DIR}"
echo "========================================================================"

# Step 0: Ensure parametric patch is applied to hbb_common submodule
if ! grep -q "RUSTDESK_APP_NAME" libs/hbb_common/src/config.rs 2>/dev/null; then
    echo "🔧 Applying parametric whitelabel patch to libs/hbb_common..."
    git -C libs/hbb_common apply ../../patches/0001-parametric-whitelabel-config.patch 2>/dev/null \
        || patch -p1 -d libs/hbb_common < patches/0001-parametric-whitelabel-config.patch
fi

# Step 1: Hermetic Parametric Cargo Compilation
echo ""
echo "📦 Phase 1: Compiling Parametric Executable via enve..."
CARGO_ARGS=(--bin rustdesk --features linux-pkg-config)
if [[ "${BUILD_PROFILE}" == "release" ]]; then
    CARGO_ARGS+=(--release)
fi

export RUSTDESK_APP_NAME="${APP_NAME}"
export RENDEZVOUS_SERVER="${RENDEZVOUS_SERVER}"
export RS_PUB_KEY="${PUBLIC_KEY}"

COMPILE_START=$(date +%s%N)
if [[ "${ARCH}" == "x86_64" ]] && command -v enve >/dev/null 2>&1; then
    enve run -- cargo build "${CARGO_ARGS[@]}"
else
    cargo build "${CARGO_ARGS[@]}"
fi
COMPILE_END=$(date +%s%N)
COMPILE_MS=$(( (COMPILE_END - COMPILE_START) / 1000000 ))
# Locate compiled binary
CARGO_PROFILE_DIR="${BUILD_PROFILE}"
if [[ "${BUILD_PROFILE}" == "dev" ]]; then
    CARGO_PROFILE_DIR="debug"
fi

TARGET_BIN=""
SEARCH_DIRS=(
    "${HOME}/.cargo/target/${CARGO_PROFILE_DIR}/rustdesk"
    "target/${CARGO_PROFILE_DIR}/rustdesk"
    "/tmp/cargo-target/${CARGO_PROFILE_DIR}/rustdesk"
)
for candidate in "${SEARCH_DIRS[@]}"; do
    if [[ -f "${candidate}" && -x "${candidate}" ]]; then
        if [[ -z "${TARGET_BIN}" ]] || [[ "${candidate}" -nt "${TARGET_BIN}" ]]; then
            TARGET_BIN="${candidate}"
        fi
    fi
done

if [[ -z "${TARGET_BIN}" ]]; then
    TARGET_BIN=$(find target "${HOME}/.cargo/target" /tmp/cargo-target -type f -name "rustdesk" -perm /111 -print -quit 2>/dev/null || true)
fi

if [[ -z "${TARGET_BIN}" || ! -f "${TARGET_BIN}" ]]; then
    echo "❌ Error: Could not locate compiled rustdesk executable!" >&2
    exit 1
fi

echo "   Found compiled binary at: ${TARGET_BIN}"

# Step 2: Staging Branded Artifacts
echo ""
echo "🎨 Phase 2: Staging Branded Assets & Desktop Integrations..."
STAGE_DIR=$(mktemp -d -t whitelabel-stage-XXXXXX)
trap 'rm -rf "${STAGE_DIR}"' EXIT

mkdir -p "${STAGE_DIR}/usr/bin"
mkdir -p "${STAGE_DIR}/usr/share/applications"
mkdir -p "${STAGE_DIR}/usr/lib/systemd/system"
mkdir -p "${OUTPUT_DIR}"

# Copy and strip binary
cp "${TARGET_BIN}" "${STAGE_DIR}/usr/bin/${PACKAGE_NAME}"
strip "${STAGE_DIR}/usr/bin/${PACKAGE_NAME}" 2>/dev/null || true

# Generate Custom Systemd Service
cat <<EOF > "${STAGE_DIR}/usr/lib/systemd/system/${PACKAGE_NAME}.service"
[Unit]
Description=${APP_NAME} Remote Desktop Service
Requires=network.target
After=systemd-user-sessions.service

[Service]
Type=simple
ExecStart=/usr/bin/${PACKAGE_NAME} --service
ExecStop=pkill -f "${PACKAGE_NAME} --"
PIDFile=/run/${PACKAGE_NAME}.pid
KillMode=mixed
TimeoutStopSec=30
User=root
LimitNOFILE=100000
Environment="PULSE_LATENCY_MSEC=60" "PIPEWIRE_LATENCY=1024/48000"

[Install]
WantedBy=multi-user.target
EOF

# Generate Custom Desktop Entry
cat <<EOF > "${STAGE_DIR}/usr/share/applications/${PACKAGE_NAME}.desktop"
[Desktop Entry]
Name=${APP_NAME}
GenericName=Remote Desktop
Comment=${APP_NAME} Secure Enterprise Remote Desktop Client
Exec=/usr/bin/${PACKAGE_NAME} %u
Icon=${PACKAGE_NAME}
Terminal=false
Type=Application
StartupNotify=true
Categories=Network;RemoteAccess;GTK;
Actions=new-window;
StartupWMClass=${PACKAGE_NAME}

[Desktop Action new-window]
Name=Open a New Window
Exec=/usr/bin/${PACKAGE_NAME} %u
EOF

# Step 3: Declarative Packaging with nFPM
echo ""
echo "📦 Phase 3: Synthesizing Native Packages with nFPM..."
NFPM_ARCH="${ARCH}"
if [[ "${ARCH}" == "x86_64" || "${ARCH}" == "amd64" ]]; then
    NFPM_ARCH="amd64"
elif [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
    NFPM_ARCH="arm64"
fi

NFPM_CONFIG="${STAGE_DIR}/nfpm.yaml"
cat <<EOF > "${NFPM_CONFIG}"
name: "${PACKAGE_NAME}"
arch: "${NFPM_ARCH}"
platform: "linux"
version: "${VERSION}"
section: "net"
priority: "optional"
maintainer: "${APP_NAME} <support@${RENDEZVOUS_SERVER}>"
description: "${APP_NAME} Remote Desktop Client (Custom Whitelabel Build)"
vendor: "${APP_NAME}"
homepage: "https://${RENDEZVOUS_SERVER}"
license: "GPL-3.0"

contents:
  - src: "${STAGE_DIR}/usr/bin/${PACKAGE_NAME}"
    dst: "/usr/bin/${PACKAGE_NAME}"
    file_info:
      mode: 0755
  - src: "${STAGE_DIR}/usr/lib/systemd/system/${PACKAGE_NAME}.service"
    dst: "/usr/lib/systemd/system/${PACKAGE_NAME}.service"
    file_info:
      mode: 0644
  - src: "${STAGE_DIR}/usr/share/applications/${PACKAGE_NAME}.desktop"
    dst: "/usr/share/applications/${PACKAGE_NAME}.desktop"
    file_info:
      mode: 0644
  - src: "res/128x128@2x.png"
    dst: "/usr/share/icons/hicolor/256x256/apps/${PACKAGE_NAME}.png"
    file_info:
      mode: 0644
  - src: "res/scalable.svg"
    dst: "/usr/share/icons/hicolor/scalable/apps/${PACKAGE_NAME}.svg"
    file_info:
      mode: 0644

overrides:
  deb:
    depends:
      - libgtk-3-0
      - libxcb-randr0
      - libxdo3
      - libxfixes3
      - libasound2
      - libpulse0
    scripts:
      postinstall: res/DEBIAN/postinst
      preremove: res/DEBIAN/prerm
      postremove: res/DEBIAN/postrm
  rpm:
    depends:
      - gtk3
      - libxcb
      - libXfixes
      - alsa-lib
      - pulseaudio-libs
EOF

PKG_START=$(date +%s%N)
nfpm pkg --config "${NFPM_CONFIG}" --packager deb --target "${OUTPUT_DIR}"
nfpm pkg --config "${NFPM_CONFIG}" --packager rpm --target "${OUTPUT_DIR}"
PKG_END=$(date +%s%N)
PKG_MS=$(( (PKG_END - PKG_START) / 1000000 ))
echo "   Finished nFPM packaging in $(( PKG_MS / 1000 )).$(( (PKG_MS % 1000) / 100 ))s"

# Step 4: Self-Verification & Cryptographic Inspection
echo ""
echo "🔍 Phase 4: Self-Verification & Binary String Audit..."
STAGE_BIN="${STAGE_DIR}/usr/bin/${PACKAGE_NAME}"
echo "   Target Arch:      ${ARCH} (Host: $(uname -m))"
if command -v file >/dev/null 2>&1; then
    echo "   Binary Info:      $(file -b "${STAGE_BIN}")"
fi
if grep -aq "${RENDEZVOUS_SERVER}" "${STAGE_BIN}"; then
    echo "   ✅ Verified: Custom Rendezvous Server '${RENDEZVOUS_SERVER}' is baked directly into the binary!"
else
    echo "   ⚠️ Warning: Rendezvous Server string was not found in binary."
fi

if grep -aq "${PUBLIC_KEY}" "${STAGE_BIN}"; then
    echo "   ✅ Verified: Custom Public Key is baked directly into the binary!"
else
    echo "   ⚠️ Warning: Public Key string was not found in binary."
fi

if grep -aq "${APP_NAME}" "${STAGE_BIN}"; then
    echo "   ✅ Verified: Custom Application Name '${APP_NAME}' is baked directly into the binary!"
else
    echo "   ⚠️ Warning: Application Name string was not found in binary."
fi

END_TIME=$(date +%s%N)
TOTAL_MS=$(( (END_TIME - START_TIME) / 1000000 ))
TOTAL_SEC=$(( TOTAL_MS / 1000 ))

echo ""
echo "========================================================================"
echo " 🏆 Whitelabel Synthesis Complete in ${TOTAL_SEC}.$(( (TOTAL_MS % 1000) / 100 )) seconds!"
echo "========================================================================"
echo " Generated Deliverables in ${OUTPUT_DIR}:"
ls -lh "${OUTPUT_DIR}"/${PACKAGE_NAME}*
echo ""
echo " Checksums (SHA-256):"
sha256sum "${OUTPUT_DIR}"/${PACKAGE_NAME}*
echo "========================================================================"
