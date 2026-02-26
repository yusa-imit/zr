# zr installer script for Windows
# Usage: irm https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1 | iex

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\zr\bin",
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"

# Configuration
$Repo = "yusa-imit/zr"
$BinaryName = "zr.exe"

# Utility functions
function Write-ColorText {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Log {
    param([string]$Message)
    Write-ColorText "==> $Message" "Blue"
}

function Write-Success {
    param([string]$Message)
    Write-ColorText "✓ $Message" "Green"
}

function Write-Error {
    param([string]$Message)
    Write-ColorText "✗ $Message" "Red"
    exit 1
}

function Write-Warning {
    param([string]$Message)
    Write-ColorText "⚠ $Message" "Yellow"
}

# Detect architecture
function Get-Architecture {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq "AMD64") {
        return "x86_64"
    } elseif ($arch -eq "ARM64") {
        return "aarch64"
    } else {
        Write-Error "Unsupported architecture: $arch"
    }
}

# Get latest release version
function Get-LatestVersion {
    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
        return $response.tag_name
    } catch {
        Write-Error "Failed to fetch latest release version: $_"
    }
}

# Download and install binary
function Install-Binary {
    param(
        [string]$Arch,
        [string]$Ver
    )

    $artifactName = "zr-${Arch}-windows.exe"
    $downloadUrl = "https://github.com/$Repo/releases/download/$Ver/$artifactName"
    $tmpFile = "$env:TEMP\$artifactName"

    Write-Log "Downloading zr $Ver for $Arch-windows..."

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpFile -UseBasicParsing
    } catch {
        Write-Error "Failed to download binary from ${downloadUrl}: $_"
    }

    # Create install directory if it doesn't exist
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Move binary to install directory
    $installPath = Join-Path $InstallDir $BinaryName
    Move-Item -Path $tmpFile -Destination $installPath -Force

    Write-Success "Installed zr to $installPath"
    return $installPath
}

# Check if install directory is in PATH
function Test-PathContains {
    param([string]$Dir)

    $pathDirs = $env:PATH -split ";"
    foreach ($pathDir in $pathDirs) {
        if ($pathDir -eq $Dir) {
            return $true
        }
    }
    return $false
}

# Add directory to PATH
function Add-ToPath {
    param([string]$Dir)

    if (Test-PathContains $Dir) {
        return
    }

    Write-Warning "Install directory $Dir is not in your PATH"
    Write-Host ""
    Write-Host "Add it to your PATH by running (as Administrator):"
    Write-Host ""
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `$env:Path + ';$Dir', 'User')"
    Write-Host ""
    Write-Host "Or add it to your current session:"
    Write-Host ""
    Write-Host "  `$env:PATH += ';$Dir'"
    Write-Host ""

    # Add to current session
    $env:PATH += ";$Dir"
    Write-Success "Added to current session PATH"
}

# Main installation flow
function Main {
    Write-Host "zr installer"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""

    # Detect architecture
    $arch = Get-Architecture
    Write-Log "Detected architecture: $arch"

    # Get version
    $ver = if ($Version -eq "latest") {
        Get-LatestVersion
    } else {
        $Version
    }
    Write-Log "Version: $ver"

    # Install binary
    $installPath = Install-Binary -Arch $arch -Ver $ver

    Write-Host ""
    Write-Success "zr installed successfully!"

    # Check PATH
    Add-ToPath -Dir $InstallDir

    # Verify installation
    try {
        $installedVersion = & $installPath --version 2>&1 | Select-Object -First 1
        Write-Success "Version: $installedVersion"
    } catch {
        Write-Warning "Could not verify installation"
    }

    Write-Host ""
    Write-Host "Get started:"
    Write-Host "  zr init          # Create a new zr.toml"
    Write-Host "  zr list          # List available tasks"
    Write-Host "  zr run <task>    # Run a task"
    Write-Host ""
    Write-Host "Documentation: https://github.com/$Repo"
}

Main
