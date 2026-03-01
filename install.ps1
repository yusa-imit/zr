# zr installation script for Windows
# Usage: irm https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

# Colors
function Write-Success { param($msg) Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "→ $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "✗ $msg" -ForegroundColor Red }

# Detect architecture
$Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else {
    Write-Error "32-bit Windows is not supported"
    return
}

# Get latest release version
Write-Info "Fetching latest release..."
try {
    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/yusa-imit/zr/releases/latest"
    $Version = $Release.tag_name
} catch {
    Write-Error "Failed to fetch latest version: $_"
    return
}

Write-Success "Latest version: $Version"

# Download URL
$BinaryName = "zr-$Arch-windows.exe"
$DownloadUrl = "https://github.com/yusa-imit/zr/releases/download/$Version/$BinaryName"

# Determine install location
$InstallDir = if ($env:ZR_INSTALL_DIR) { 
    $env:ZR_INSTALL_DIR 
} else { 
    "$env:LOCALAPPDATA\Programs\zr"
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$InstallPath = Join-Path $InstallDir "zr.exe"

# Download binary
Write-Info "Downloading zr..."
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallPath -ErrorAction Stop

    # Verify the file was actually downloaded and has non-zero size
    if (-not (Test-Path $InstallPath)) {
        throw "Binary file was not created at $InstallPath"
    }
    $FileInfo = Get-Item $InstallPath
    if ($FileInfo.Length -eq 0) {
        Remove-Item $InstallPath -Force
        throw "Downloaded file is empty (0 bytes)"
    }
} catch {
    Write-Error "Failed to download zr from $DownloadUrl : $_"
    Write-Host ""
    Write-Host "Please try:" -ForegroundColor Yellow
    Write-Host "  1. Check your internet connection" -ForegroundColor Cyan
    Write-Host "  2. Download manually from: https://github.com/yusa-imit/zr/releases/latest" -ForegroundColor Cyan
    Write-Host "  3. Extract the binary to: $InstallDir" -ForegroundColor Cyan
    return
}

Write-Success "zr installed successfully to $InstallPath"
Write-Host ""
Write-Host "Run 'zr --version' to verify installation"
Write-Host ""

# Check if install dir is in PATH
$PathArray = $env:PATH -split ';'
if ($PathArray -notcontains $InstallDir) {
    Write-Host "⚠  $InstallDir is not in your PATH" -ForegroundColor Yellow
    Write-Host "   Add it to PATH with:" -ForegroundColor Yellow
    Write-Host "   `$env:PATH += ';$InstallDir'" -ForegroundColor Cyan
    Write-Host "   Or add it permanently via System Properties > Environment Variables"
}
