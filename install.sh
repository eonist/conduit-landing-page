#!/usr/bin/env bash
# Auto-install and run the Conduit MCP server + Figma plugin.
#
# Usage:
#   curl -sSL https://conduit.design/install.sh | bash -s -- [--run]
#
set -euo pipefail

# -----------------------------
# Configuration
# -----------------------------

INSTALL_DIR="${HOME}/.local/bin"
BINARY_NAME="conduit-mcp"
BINARY_PATH="${INSTALL_DIR}/${BINARY_NAME}"

PLUGIN_DIR="${HOME}/.conduit/figma-plugin"
PLUGIN_ZIP_NAME="figma-plugin.zip"

GITHUB_OWNER="conduit-design"
GITHUB_REPO="conduit_design"
BASE_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest/download"

# -----------------------------
# Helpers
# -----------------------------

log() {
  printf '[conduit.install] %s\n' "$*" >&2
}

err() {
  printf '[conduit.install][ERROR] %s\n' "$*" >&2
}

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

needs_update() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    return 0
  fi
  # Check if file is older than 1 day
  if [ "$(uname -s)" = "Darwin" ]; then
    # macOS
    if [ $(( $(date +%s) - $(stat -f %m "${path}") )) -gt 86400 ]; then
      return 0
    fi
  else
    # Linux
    if find "${path}" -mtime +0 >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

ensure_install_dir() {
  mkdir -p "${INSTALL_DIR}"
}

ensure_plugin_dir() {
  mkdir -p "${PLUGIN_DIR}"
}

have_unzip() {
  command -v unzip >/dev/null 2>&1
}

# -----------------------------
# Install / update binary
# -----------------------------

install_or_update_binary() {
  detect_os_arch
  ensure_install_dir

  local asset="conduit-${OS_NAME}-${ARCH_NAME}"
  local url="${BASE_URL}/${asset}"

  if needs_update "${BINARY_PATH}"; then
    log "Installing/updating Conduit MCP binary (${asset})..."
    log "Downloading from: ${url}"
    
    # Download with better error handling
    if ! curl -fsSL --fail --show-error "${url}" -o "${BINARY_PATH}.tmp"; then
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
    
    # Verify it's a valid binary (macOS only)
    if [ "${OS_NAME}" = "macos" ]; then
      if ! file "${BINARY_PATH}" | grep -q "Mach-O"; then
        err "Downloaded file is not a valid macOS executable"
        err "File type: $(file ${BINARY_PATH})"
        exit 1
      fi
      log "Binary verified as valid Mach-O executable"
    fi
    
    log "Binary installed successfully to: ${BINARY_PATH}"
  else
    log "Conduit MCP binary is up-to-date: ${BINARY_PATH}"
  fi
}

# -----------------------------
# Install / update Figma plugin
# -----------------------------

install_or_update_plugin() {
  ensure_plugin_dir

  local manifest_path="${PLUGIN_DIR}/manifest.json"
  local url="${BASE_URL}/${PLUGIN_ZIP_NAME}"

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

  if ! curl -fsSL --fail --show-error "${url}" -o "${tmp_zip}"; then
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
# -----------------------------

RUN_AFTER_INSTALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run)
      RUN_AFTER_INSTALL=1
      shift
      ;;
    --help|-h)
      cat <<EOF
Conduit MCP installer

Usage:
  bash install.sh [--run]

Options:
  --run   After installing/updating, exec the conduit MCP binary with --stdio
EOF
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      exit 1
      ;;
  esac
done

install_or_update_binary
install_or_update_plugin || true

if [ "${RUN_AFTER_INSTALL}" -eq 1 ]; then
  log "Launching Conduit MCP server via ${BINARY_PATH} --stdio..."
  exec "${BINARY_PATH}" --stdio
else
  log "Installation complete. To run manually: ${BINARY_PATH} --stdio"
fi
