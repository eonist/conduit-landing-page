#!/usr/bin/env pwsh
<#
Auto-install and update the Conduit MCP server + Figma plugin on Windows.

Intended usage (from docs / MCP hosts):
  iwr https://conduit.design/install.ps1 -UseBasicParsing | iex
  conduit-mcp --stdio

This script:
  - Detects Windows x64
  - Downloads the appropriate conduit-mcp Windows binary from GitHub Releases
  - Installs it to $HOME/.local/bin/conduit-mcp.exe
  - Downloads figma-plugin.zip and extracts it to $HOME/.conduit/figma-plugin
  - Optionally, with -Run, execs `conduit-mcp.exe --stdio`

Release assets are expected in:
  https://github.com/conduit-design/conduit_design/releases/latest/download
with names like:
  conduit-windows-x64.exe
  figma-plugin.zip
#>

[CmdletBinding()]
param(
    [switch]$Run
)

$ErrorActionPreference = "Stop"

function Write-ConduitLog {
    param([string]$Message)
    Write-Host "[conduit.install] $Message"
}

function Write-ConduitError {
    param([string]$Message)
    Write-Error "[conduit.install] $Message"
}

function Get-ConduitHome {
    if ($env:HOME) {
        return $env:HOME
    }
    return [Environment]::GetFolderPath('UserProfile')
}

$home = Get-ConduitHome

# -----------------------------
# Configuration
# -----------------------------

$InstallDir  = Join-Path $home ".local\bin"
$BinaryName  = "conduit-mcp.exe"
$BinaryPath  = Join-Path $InstallDir $BinaryName

$PluginDir      = Join-Path $home ".conduit\figma-plugin"
$PluginZipName  = "figma-plugin.zip"

$GitHubOwner = "conduit-design"
$GitHubRepo  = "conduit_design"
$BaseUrl     = "https://github.com/$GitHubOwner/$GitHubRepo/releases/latest/download"

# -----------------------------
# Helpers
# -----------------------------

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Test-NeedsUpdate {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }
    $item = Get-Item -LiteralPath $Path
    $lastWrite = $item.LastWriteTimeUtc
    $age = (Get-Date).ToUniversalTime() - $lastWrite
    # Older than 24 hours?
    return ($age.TotalHours -gt 24)
}

function Get-WindowsArchTag {
    # Map PROCESSOR_ARCHITECTURE to our release arch tag
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch -Regex ($arch) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default {
            Write-ConduitError "Unsupported Windows architecture '$arch'. Only x64 and arm64 are supported in this version."
            exit 1
        }
    }
}

# -----------------------------
# Install / update binary
# -----------------------------

function Install-OrUpdate-Binary {
    Ensure-Directory $InstallDir

    $archTag = Get-WindowsArchTag
    $asset   = "conduit-windows-$archTag.exe"
    $url     = "$BaseUrl/$asset"

    if (Test-NeedsUpdate $BinaryPath) {
        Write-ConduitLog "Installing/updating Conduit MCP binary ($asset)..."
        Write-ConduitLog "Downloading from: $url"
        
        $tmpBinary = [System.IO.Path]::GetTempFileName()
        
        try {
            # Download to temp file
            if (-not (Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $tmpBinary -ErrorAction Stop)) {
                throw "Failed to download binary"
            }
            
            # Verify file is not empty
            if ((Get-Item -LiteralPath $tmpBinary).Length -eq 0) {
                throw "Downloaded file is empty"
            }
            
            # Verify binary has MZ header (PE executable signature)
            $bytes = Get-Content -LiteralPath $tmpBinary -Encoding Byte -TotalCount 2 -ErrorAction Stop
            if (-not ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A)) {
                throw "Downloaded file is not a valid Windows executable (missing MZ header)"
            }
            
            Write-ConduitLog "Binary verified as valid Windows executable"
            
            # Atomic move to final location
            Move-Item -LiteralPath $tmpBinary -Destination $BinaryPath -Force
            Write-ConduitLog "Binary installed successfully to: $BinaryPath"
        }
        catch {
            if (Test-Path -LiteralPath $tmpBinary) {
                Remove-Item -LiteralPath $tmpBinary -ErrorAction SilentlyContinue
            }
            Write-ConduitError "Failed to download binary: $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-ConduitLog "Conduit MCP binary is up-to-date: $BinaryPath"
    }
}

# -----------------------------
# Install / update Figma plugin
# -----------------------------

function Install-OrUpdate-Plugin {
    Ensure-Directory $PluginDir

    $manifestPath = Join-Path $PluginDir "manifest.json"
    $url          = "$BaseUrl/$PluginZipName"

    if (-not (Test-NeedsUpdate $manifestPath)) {
        Write-ConduitLog "Figma plugin is up-to-date at $PluginDir"
        return
    }

    if (-not (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) {
        Write-ConduitError "Expand-Archive cmdlet not found. Please update PowerShell (5.0+) or install the 'Microsoft.PowerShell.Archive' module, then re-run the installer."
        return
    }

    Write-ConduitLog "Installing/updating Figma plugin from $PluginZipName..."

    $tmpZip = [System.IO.Path]::GetTempFileName()

    try {
        # Download plugin
        if (-not (Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $tmpZip -ErrorAction Stop)) {
            throw "Failed to download Figma plugin"
        }
        
        # Verify file is not empty
        if ((Get-Item -LiteralPath $tmpZip).Length -eq 0) {
            throw "Downloaded Figma plugin file is empty"
        }
        
        # Extract
        Expand-Archive -Path $tmpZip -DestinationPath $PluginDir -Force -ErrorAction Stop
    }
    catch {
        Write-ConduitError "Failed to install Figma plugin: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tmpZip) {
            Remove-Item -LiteralPath $tmpZip -ErrorAction SilentlyContinue
        }
    }

    Write-ConduitLog "Figma plugin installed to: $PluginDir"
    Write-ConduitLog "Import into Figma via: Plugins → Development → Import plugin from manifest"
    Write-ConduitLog "Manifest path: $(Join-Path $PluginDir 'manifest.json')"
}

# -----------------------------
# Main
# -----------------------------

try {
    Install-OrUpdate-Binary

    try {
        Install-OrUpdate-Plugin
    }
    catch {
        # Mirror install.sh: plugin failure should not abort binary install
        Write-ConduitError ("Figma plugin installation failed: " + $_.Exception.Message)
    }

    # For MCP usage (iwr ... | iex), always launch the server so the process
    # stays running and speaks MCP over stdio, similar to install.sh --run.
    Write-ConduitLog "Launching Conduit MCP server via '$BinaryPath --stdio'..."
    & $BinaryPath --stdio
}
catch {
    Write-ConduitError ($_.Exception.Message)
    exit 1
}
