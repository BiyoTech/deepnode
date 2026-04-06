#!/usr/bin/env bash
# DeepNode Server - One-line installer
# Usage: curl -fsSL https://raw.githubusercontent.com/BiyoTech/deepnode/main/install.sh | bash
#
# Environment variables:
#   DEEPNODE_INSTALL_DIR  — installation directory (default: ~/deepnode-server)
#   DEEPNODE_VERSION      — version to install (default: latest)

set -euo pipefail

# ─── Constants ───────────────────────────────────────────────────────────────
REPO="BiyoTech/deepnode"
DEFAULT_INSTALL_DIR="$HOME/deepnode-server"
MIN_MACOS_VERSION="13.5"

# ─── Color helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Pre-flight checks ──────────────────────────────────────────────────────
check_os() {
    local os
    os="$(uname -s)"
    if [[ "$os" != "Darwin" ]]; then
        error "DeepNode currently only supports macOS. Detected OS: $os"
    fi
    ok "Operating system: macOS"
}

check_arch() {
    ARCH="$(uname -m)"
    if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
        error "Unsupported architecture: $ARCH. DeepNode requires arm64 or x86_64."
    fi
    ok "Architecture: $ARCH"
}

check_macos_version() {
    local version
    version="$(sw_vers -productVersion)"
    local major minor
    major="$(echo "$version" | cut -d. -f1)"
    minor="$(echo "$version" | cut -d. -f2)"

    local req_major req_minor
    req_major="$(echo "$MIN_MACOS_VERSION" | cut -d. -f1)"
    req_minor="$(echo "$MIN_MACOS_VERSION" | cut -d. -f2)"

    if (( major < req_major )) || (( major == req_major && minor < req_minor )); then
        error "macOS $MIN_MACOS_VERSION+ is required. Current version: $version"
    fi

    # Determine the Metal-compatible macOS major version for asset matching
    MACOS_MAJOR="$major"
    ok "macOS version: $version (Metal-compatible target: macOS $MACOS_MAJOR)"
}

check_commands() {
    for cmd in curl tar; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command '$cmd' not found. Please install it first."
        fi
    done
}

# ─── Resolve version & download URL ─────────────────────────────────────────
resolve_download_url() {
    local version="${DEEPNODE_VERSION:-latest}"
    local api_url

    if [[ "$version" == "latest" ]]; then
        api_url="https://api.github.com/repos/${REPO}/releases/latest"
    else
        # Ensure version starts with 'v'
        [[ "$version" != v* ]] && version="v${version}"
        api_url="https://api.github.com/repos/${REPO}/releases/tags/${version}"
    fi

    info "Fetching release info from: $api_url"

    local release_json
    release_json="$(curl -fsSL "$api_url" 2>/dev/null)" \
        || error "Failed to fetch release info. Check your network and the version tag."

    TAG_NAME="$(echo "$release_json" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
    if [[ -z "$TAG_NAME" ]]; then
        error "Could not parse release tag from API response."
    fi

    # Build expected asset name pattern: deepnode-<version>-macos<major>-<arch>.tar.gz
    local asset_pattern="deepnode-${TAG_NAME}-macos${MACOS_MAJOR}-${ARCH}.tar.gz"
    info "Looking for asset: $asset_pattern"

    DOWNLOAD_URL="$(echo "$release_json" | grep '"browser_download_url"' | grep "$asset_pattern" | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"

    if [[ -z "$DOWNLOAD_URL" ]]; then
        # Fallback: try macos13 (base compatible build)
        asset_pattern="deepnode-${TAG_NAME}-macos13-${ARCH}.tar.gz"
        warn "Exact macOS $MACOS_MAJOR build not found, trying base build: $asset_pattern"
        DOWNLOAD_URL="$(echo "$release_json" | grep '"browser_download_url"' | grep "$asset_pattern" | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"
    fi

    if [[ -z "$DOWNLOAD_URL" ]]; then
        error "No compatible asset found for macOS ${MACOS_MAJOR} ${ARCH} in release ${TAG_NAME}.
Available assets:
$(echo "$release_json" | grep '"browser_download_url"' | sed 's/.*"browser_download_url": *"\([^"]*\)".*/  \1/')"
    fi

    ok "Found asset: $DOWNLOAD_URL"
}

# ─── Download & install ──────────────────────────────────────────────────────
download_and_install() {
    local install_dir="${DEEPNODE_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    local tar_file="${tmp_dir}/deepnode.tar.gz"

    info "Downloading DeepNode ${TAG_NAME} ..."
    curl -fSL --progress-bar -o "$tar_file" "$DOWNLOAD_URL" \
        || error "Download failed. Please check your network connection."

    info "Extracting to $install_dir ..."
    # Remove old installation if exists
    if [[ -d "$install_dir" ]]; then
        warn "Existing installation found at $install_dir — backing up to ${install_dir}.bak"
        rm -rf "${install_dir}.bak"
        mv "$install_dir" "${install_dir}.bak"
    fi

    mkdir -p "$install_dir"
    tar xzf "$tar_file" -C "$install_dir" --strip-components=1

    # Remove macOS quarantine attribute
    info "Removing macOS quarantine attribute ..."
    xattr -rd com.apple.quarantine "$install_dir" 2>/dev/null || true

    ok "Installed to: $install_dir"
}

# ─── Print post-install instructions ─────────────────────────────────────────
print_instructions() {
    local install_dir="${DEEPNODE_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        DeepNode ${TAG_NAME} installed successfully!        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Quick start:"
    echo ""
    echo "    cd $install_dir"
    echo ""
    echo "    # Start with account credentials"
    echo "    ./deepnode-server --standalone --account <user> --password <pass>"
    echo ""
    echo "    # Or start with token"
    echo "    ./deepnode-server --standalone --token <your_token>"
    echo ""
    echo "  After starting, visit: http://127.0.0.1:8765/"
    echo ""
    echo "  For more details, see:"
    echo "    https://github.com/${REPO}#readme"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    echo ""
    info "DeepNode Server Installer"
    echo ""

    check_os
    check_arch
    check_macos_version
    check_commands
    resolve_download_url
    download_and_install
    print_instructions
}

main "$@"
