<#
.SYNOPSIS
    Installs zr command-line tool for Windows from GitHub releases.
.DESCRIPTION
    Downloads and installs zr from GitHub releases, adds it to PATH, and creates necessary shortcuts.
.NOTES
    Requires Administrator privileges to modify PATH environment variable.
#>

# Ensure running with administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script as Administrator!"
    exit 1
}

# Configuration
$AppName = "zr"
$InstallDir = Join-Path (Join-Path $env:LOCALAPPDATA "Programs") $AppName
$ExeName = "zr.exe"
$GithubRepo = "yusa-imit/zr"
$TempDir = Join-Path $env:TEMP "zr-install"

# Create temporary and installation directories
try {
    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Write-Host "Created installation directory: $InstallDir"
    }
} catch {
    Write-Error "Failed to create directories: $_"
    exit 1
}

# Get latest release
try {
    Write-Host "Fetching latest release information..."
    $ReleasesUri = "https://api.github.com/repos/$GithubRepo/releases/latest"
    $LatestRelease = Invoke-RestMethod -Uri $ReleasesUri -Method Get
    $WindowsAsset = $LatestRelease.assets | Where-Object { $_.name -like "*windows.exe" }
    
    if (-not $WindowsAsset) {
        Write-Error "Could not find Windows executable in latest release"
        exit 1
    }

    # Download the executable
    Write-Host "Downloading latest version..."
    $DownloadPath = Join-Path $TempDir "zr-windows.exe"
    Invoke-WebRequest -Uri $WindowsAsset.browser_download_url -OutFile $DownloadPath

    # Copy executable to installation directory
    Copy-Item -Path $DownloadPath -Destination (Join-Path $InstallDir $ExeName) -Force
    Write-Host "Installed executable version $($LatestRelease.tag_name)"
} catch {
    Write-Error "Failed to download and install executable: $_"
    exit 1
} finally {
    # Cleanup
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
}

# Add to PATH if not already present
try {
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($UserPath -notlike "*$InstallDir*") {
        $NewPath = "$InstallDir;$UserPath"
        [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
        Write-Host "Added installation directory to PATH"
        
        # Update current session's PATH
        $env:PATH = "$InstallDir;$env:PATH"
    } else {
        Write-Host "Installation directory already in PATH"
    }
} catch {
    Write-Error "Failed to update PATH: $_"
    exit 1
}

# Create uninstall script
$UninstallScript = @'
<#
.SYNOPSIS
    Uninstalls zr command-line tool.
#>

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script as Administrator!"
    exit 1
}

$InstallDir = Split-Path -Parent $PSCommandPath
$AppName = Split-Path -Leaf $InstallDir

try {
    # Remove from PATH
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $NewPath = ($UserPath -split ';' | Where-Object { $_ -ne $InstallDir }) -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
    Write-Host "Removed from PATH"

    # Remove Start Menu shortcut
    $StartMenuPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName"
    if (Test-Path $StartMenuPath) {
        Remove-Item -Path $StartMenuPath -Recurse -Force
        Write-Host "Removed Start Menu shortcut"
    }

    # Remove installation directory
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "Removed installation directory"

    Write-Host "Uninstallation complete"
} catch {
    Write-Error "Failed during uninstallation: $_"
    exit 1
}
'@

Set-Content -Path (Join-Path $InstallDir "uninstall.ps1") -Value $UninstallScript
Write-Host "Created uninstall script"

# Create Start Menu shortcut
$StartMenuPath = Join-Path (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs") $AppName
if (-not (Test-Path $StartMenuPath)) {
    New-Item -ItemType Directory -Path $StartMenuPath -Force | Out-Null
}

$WShell = New-Object -ComObject WScript.Shell
$Shortcut = $WShell.CreateShortcut((Join-Path $StartMenuPath "$AppName.lnk"))
$Shortcut.TargetPath = Join-Path $InstallDir $ExeName
$Shortcut.Save()
Write-Host "Created Start Menu shortcut"

Write-Host "`nInstallation completed successfully!"
Write-Host "You can now use 'zr' from any terminal."
Write-Host "To uninstall, run uninstall.ps1 from: $InstallDir"
Write-Host "`nPlease restart your terminal to use the 'zr' command."