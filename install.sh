#!/bin/bash

# Configuration
GITHUB_REPO="yusa-imit/zr"
INSTALL_DIR="/usr/local/bin"
TEMP_DIR="/tmp/zr-install"

# Determine OS and architecture
if [[ "$(uname)" == "Darwin" ]]; then
    if [[ "$(uname -m)" == "arm64" ]]; then
        BINARY_SUFFIX="aarch64-macos"
    else
        BINARY_SUFFIX="x86_64-macos"
    fi
else
    BINARY_SUFFIX="x86_64-linux"
fi

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Create temporary directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || exit 1

echo "Fetching latest release information..."
LATEST_RELEASE_URL=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep "browser_download_url.*$BINARY_SUFFIX" | cut -d '"' -f 4)

if [ -z "$LATEST_RELEASE_URL" ]; then
    echo "Error: Could not find appropriate release for your system"
    exit 1
fi

echo "Downloading latest version..."
if ! curl -L -o zr "$LATEST_RELEASE_URL"; then
    echo "Error: Download failed"
    exit 1
fi

echo "Installing..."
chmod +x zr
mv zr "$INSTALL_DIR/zr"

# Cleanup
cd / && rm -rf "$TEMP_DIR"

echo "Installation completed. You can now use 'zr' command."

# Optional: Add bash completion
if [ -d "/etc/bash_completion.d" ]; then
    cat > /etc/bash_completion.d/zr << 'EOF'
_zr() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--help --version" # Add your command options here

    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
}
complete -F _zr zr
EOF
    echo "Bash completion installed."
fi

# Optional: Add man page
if [ -d "/usr/local/share/man/man1" ]; then
    mkdir -p "/usr/local/share/man/man1"
    cat > /usr/local/share/man/man1/zr.1 << 'EOF'
.TH ZR 1 "$(date +"%B %Y")" "Version 1.0" "ZR Manual"
.SH NAME
zr \- your program description
.SH SYNOPSIS
.B zr
[\fIOPTION\fR]... [\fIFILE\fR]...
.SH DESCRIPTION
Brief description of what your program does.
.SH OPTIONS
.TP
.BR \-h ", " \-\-help
Display help message
.TP
.BR \-v ", " \-\-version
Display version information
EOF
    echo "Man page installed."
fi

echo "Installation completed successfully!"