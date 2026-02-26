#!/usr/bin/env bash
# zr installer script
# Usage: curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh

set -euo pipefail

# Configuration
REPO="yusa-imit/zr"
INSTALL_DIR="${ZR_INSTALL_DIR:-$HOME/.local/bin}"
BINARY_NAME="zr"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}==>${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Detect OS and architecture
detect_platform() {
    local os arch

    # Detect OS
    case "$(uname -s)" in
        Linux*)     os="linux" ;;
        Darwin*)    os="macos" ;;
        MINGW*|MSYS*|CYGWIN*) os="windows" ;;
        *)          error "Unsupported operating system: $(uname -s)" ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64)   arch="x86_64" ;;
        aarch64|arm64)  arch="aarch64" ;;
        *)              error "Unsupported architecture: $(uname -m)" ;;
    esac

    echo "${arch}-${os}"
}

# Get latest release version
get_latest_version() {
    local version
    version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        error "Failed to fetch latest release version"
    fi

    echo "$version"
}

# Download and install binary
install_binary() {
    local platform="$1"
    local version="$2"
    local artifact_name extension

    # Determine artifact name and extension
    if [[ "$platform" == *"windows"* ]]; then
        artifact_name="zr-${platform}.exe"
        extension=".exe"
    else
        artifact_name="zr-${platform}"
        extension=""
    fi

    local download_url="https://github.com/${REPO}/releases/download/${version}/${artifact_name}"
    local tmp_file="/tmp/${artifact_name}"

    log "Downloading zr ${version} for ${platform}..."
    if ! curl -fsSL -o "$tmp_file" "$download_url"; then
        error "Failed to download binary from ${download_url}"
    fi

    # Make binary executable
    chmod +x "$tmp_file"

    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"

    # Move binary to install directory
    local install_path="${INSTALL_DIR}/${BINARY_NAME}${extension}"
    mv "$tmp_file" "$install_path"

    success "Installed zr to ${install_path}"
}

# Check if install directory is in PATH
check_path() {
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        warn "Install directory ${INSTALL_DIR} is not in your PATH"
        echo ""
        echo "Add it to your PATH by adding this to your shell profile:"
        echo ""
        echo "  export PATH=\"\${PATH}:${INSTALL_DIR}\""
        echo ""
    fi
}

# Main installation flow
main() {
    echo "zr installer"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Detect platform
    local platform
    platform=$(detect_platform)
    log "Detected platform: ${platform}"

    # Get latest version
    local version
    version=$(get_latest_version)
    log "Latest version: ${version}"

    # Install binary
    install_binary "$platform" "$version"

    echo ""
    success "zr installed successfully!"

    # Verify installation
    if command -v zr &> /dev/null; then
        local installed_version
        installed_version=$(zr --version 2>/dev/null | head -n1 || echo "unknown")
        success "Version: ${installed_version}"
    else
        check_path
    fi

    echo ""
    echo "Get started:"
    echo "  zr init          # Create a new zr.toml"
    echo "  zr list          # List available tasks"
    echo "  zr run <task>    # Run a task"
    echo ""
    echo "Documentation: https://github.com/${REPO}"
}

main "$@"
