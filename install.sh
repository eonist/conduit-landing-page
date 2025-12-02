#!/usr/bin/env bash
# Auto-install and update the Conduit MCP server + Figma plugin.
#
# Usage:
#   curl -sSL https://conduit.design/install.sh | bash
#

# IMPORTANT: This script handles installation ONLY.
# The MCP host (e.g., Cursor, VSCode) must run the server in a separate step
# after this script completes. This two-step process (install, then run) is
# critical to prevent the installer's output from interfering with the server's
# stdio communication channel with the host.

set -euo pipefail

# -----------------------------
# Configuration
# Defines constants and paths used throughout the script.
# -----------------------------

# Directory where the executable will be installed.
INSTALL_DIR="${HOME}/.local/bin"
BINARY_NAME="conduit-mcp"
BINARY_PATH="${INSTALL_DIR}/${BINARY_NAME}"

# Directory where the Figma plugin will be installed.
PLUGIN_DIR="${HOME}/.conduit/figma-plugin"
PLUGIN_ZIP_NAME="figma-plugin.zip"

# GitHub repository details for downloading release assets.
GITHUB_OWNER="conduit-design"
GITHUB_REPO="conduit_design"
BASE_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download"

# -----------------------------
# Helpers
# Utility functions used by the installer.
# -----------------------------

# Logs a standard message to stderr.
log() {
  printf '[conduit.install] %s\n' "$*" >&2
}

# Logs an error message to stderr.
err() {
  printf '[conduit.install][ERROR] %s\n' "$*" >&2
}

# Detects the OS and CPU architecture to download the correct binary.
detect_os_arch() {
  local uname_s uname_m
  uname_s="$(uname -s | tr '[:upper:]' '[:lower:]')"
  uname_m="$(uname -m)"

  case "${uname_s}" in
    darwin) OS_NAME="macos" ;;
    linux)  OS_NAME="linux" ;;
    *)
      err "Unsupported OS: ${uname_s}. Only macOS and Linux are supported in v1."
      exit 1
      ;;
  esac

  case "${uname_m}" in
    x86_64|amd64) ARCH_NAME="x64" ;;
    arm64|aarch64) ARCH_NAME="arm64" ;;
    *)
      err "Unsupported architecture: ${uname_m}. Supported: x86_64, arm64."
      exit 1
      ;;
  esac
  
  log "Detected: ${OS_NAME}-${ARCH_NAME}"
}

# Checks if a file needs to be updated.
# Returns 0 (true) if the file doesn't exist or is older than 24 hours.
needs_update() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    return 0 # Needs update because it doesn't exist.
  fi
  # Check if file is older than 1 day.
  if [ "$(uname -s)" = "Darwin" ]; then
    # macOS
    if [ $(( $(date +%s) - $(stat -f %m "${path}") )) -gt 86400 ]; then
      return 0 # Needs update.
    fi
  else
    # Linux: find returns success (0) if file is older than 24 hours (-mtime +0).
    if find "${path}" -mtime +0 >/dev/null 2>&1; then
      return 0 # Needs update.
    fi
  fi
  return 1 # Up-to-date.
}

# Creates the installation directory if it does not already exist.
ensure_install_dir() {
  mkdir -p "${INSTALL_DIR}"
}

# Creates the Figma plugin directory if it does not already exist.
ensure_plugin_dir() {
  mkdir -p "${PLUGIN_DIR}"
}

# Checks if the 'unzip' command is available.
have_unzip() {
  command -v unzip >/dev/null 2>&1
}

# -----------------------------
# Install / update binary
# Downloads and installs the main conduit-mcp executable.
# -----------------------------

install_or_update_binary() {
  detect_os_arch
  ensure_install_dir

  # Determine the correct binary asset based on OS and architecture.
  local asset="conduit-${OS_NAME}-${ARCH_NAME}"
  local url="${BASE_URL}/${asset}"

  # Only download if the binary is missing or outdated.
  if needs_update "${BINARY_PATH}"; then
    log "Installing/updating Conduit MCP binary (${asset})..."
    log "Downloading from: ${url}"
    
    # Download with better error handling
    if ! curl -fsSL --show-error "${url}" -o "${BINARY_PATH}.tmp"; then
      err "Failed to download binary from ${url}"
      err "Please check your internet connection and try again."
      rm -f "${BINARY_PATH}.tmp"
      exit 1
    fi
    
    # Verify download is not empty
    if [ ! -s "${BINARY_PATH}.tmp" ]; then
      err "Downloaded file is empty"
      rm -f "${BINARY_PATH}.tmp"
      exit 1
    fi
    
    # Move to final location
    sync || true # Ensure file system buffers are flushed before atomic move
    mv "${BINARY_PATH}.tmp" "${BINARY_PATH}"
    chmod +x "${BINARY_PATH}"
    
    # Verify it's a valid binary for the detected OS.
    if [ "${OS_NAME}" = "macos" ]; then
      if ! file "${BINARY_PATH}" | grep -q "Mach-O"; then
        err "Downloaded file is not a valid macOS executable. File type: $(file ${BINARY_PATH})"
        exit 1
      fi
      log "Binary verified as valid Mach-O executable."
    elif [ "${OS_NAME}" = "linux" ]; then
      if ! file "${BINARY_PATH}" | grep -q "ELF"; then
        err "Downloaded file is not a valid Linux executable. File type: $(file ${BINARY_PATH})"
        exit 1
      fi
      log "Binary verified as valid ELF executable."
    fi
    
    log "Binary installed successfully to: ${BINARY_PATH}"
  else
    log "Conduit MCP binary is up-to-date: ${BINARY_PATH}"
  fi
}

# -----------------------------
# Install / update Figma plugin
# Downloads and extracts the Figma plugin.
# -----------------------------

install_or_update_plugin() {
  ensure_plugin_dir

  local manifest_path="${PLUGIN_DIR}/manifest.json"
  local url="${BASE_URL}/${PLUGIN_ZIP_NAME}"

  # Only download if the plugin's manifest is missing or outdated.
  if ! needs_update "${manifest_path}"; then
    log "Figma plugin is up-to-date at ${PLUGIN_DIR}"
    return 0
  fi

  if ! have_unzip; then
    err "unzip not found. Please install unzip and re-run the installer."
    return 1
  fi

  log "Installing/updating Figma plugin from ${PLUGIN_ZIP_NAME}..."

  local tmp_zip
  tmp_zip="$(mktemp)"

  if ! curl -fsSL --show-error "${url}" -o "${tmp_zip}"; then
    err "Failed to download Figma plugin from ${url}"
    err "Please check your internet connection and try again."
    rm -f "${tmp_zip}"
    return 1
  fi

  # Verify download is not empty
  if [ ! -s "${tmp_zip}" ]; then
    err "Downloaded Figma plugin file is empty"
    rm -f "${tmp_zip}"
    return 1
  fi

  sync || true # Ensure file system buffers are flushed before atomic move
  unzip -o "${tmp_zip}" -d "${PLUGIN_DIR}" >/dev/null

  rm -f "${tmp_zip}"

  log "Figma plugin installed to: ${PLUGIN_DIR}"
  log "Import into Figma via: Plugins → Development → Import plugin from manifest"
  log "Manifest path: ${manifest_path}"
}

# -----------------------------
# Main
# Main execution block that orchestrates the installation.
# -----------------------------

# Step 1: Install or update the main binary. This is a critical step.
install_or_update_binary

# Step 2: Install or update the Figma plugin.
# The `|| true` ensures that a failure in the plugin installation does not
# stop the script, as the main binary is the most critical component.
install_or_update_plugin || true

log "Installation complete. To run the server manually, execute: ${BINARY_PATH} --stdio"
