#!/bin/sh
# zr installation script for macOS/Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
    darwin) OS="macos" ;;
    linux) OS="linux" ;;
    *)
        echo "${RED}✗${NC} Unsupported OS: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *)
        echo "${RED}✗${NC} Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Get latest release version
echo "${YELLOW}→${NC} Fetching latest release..."
VERSION=$(curl -fsSL https://api.github.com/repos/yusa-imit/zr/releases/latest | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$')

if [ -z "$VERSION" ]; then
    echo "${RED}✗${NC} Failed to fetch latest version"
    exit 1
fi

echo "${GREEN}✓${NC} Latest version: $VERSION"

# Download URL
BINARY_NAME="zr-${VERSION}-${OS}-${ARCH}"
DOWNLOAD_URL="https://github.com/yusa-imit/zr/releases/download/${VERSION}/${BINARY_NAME}"

# Create temporary directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "${YELLOW}→${NC} Downloading zr..."
if ! curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/zr"; then
    echo "${RED}✗${NC} Failed to download zr from $DOWNLOAD_URL"
    exit 1
fi

# Make executable
chmod +x "$TMP_DIR/zr"

# Determine install location
INSTALL_DIR="${ZR_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"

# Install binary
echo "${YELLOW}→${NC} Installing to $INSTALL_DIR/zr..."
mv "$TMP_DIR/zr" "$INSTALL_DIR/zr"

echo "${GREEN}✓${NC} zr installed successfully!"
echo ""
echo "Run 'zr --version' to verify installation"
echo ""

# Check if install dir is in PATH
case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        echo "${YELLOW}⚠${NC}  $INSTALL_DIR is not in your PATH"
        echo "   Add this line to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo "   export PATH=\"\$PATH:$INSTALL_DIR\""
        ;;
esac
