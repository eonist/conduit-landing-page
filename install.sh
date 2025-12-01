#!/usr/bin/env bash
# Auto-install and run the Conduit MCP server + Figma plugin.
#
# Usage:
#   curl -sSL https://conduit.design/install.sh | bash -s -- [--run]
#
# Behavior:
#   - Detects OS/arch (macOS/Linux, x64/arm64)
#   - Downloads the appropriate conduit-mcp binary from GitHub Releases
#   - Installs it to ~/.local/bin/conduit-mcp (creating the dir if needed)
#   - Downloads figma-plugin.zip and extracts it to ~/.conduit/figma-plugin/
#   - If invoked with --run, ensures everything is up-to-date and then
#     execs `conduit-mcp --stdio`.
#
# NOTE: For v1 this expects assets in the public repo:
#   https://github.com/conduit-design/conduit_design
# with names like:
#   conduit-macos-arm64, conduit-macos-x64, conduit-linux-x64, conduit-linux-arm64
#   figma-plugin.zip
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
  # stderr so MCP clients don't confuse logs with protocol
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
}

needs_update() {
  # Returns 0 (true) if file is missing or older than 1 day
  local path="$1"
  if [ ! -f "${path}" ]; then
    return 0
  fi
  # -mtime +0 means strictly older than 24h; adjust if you want a different cadence
  if find "${path}" -mtime +0 >/dev/null 2>&1; then
    return 0
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
  if command -v unzip >/dev/null 2>&1; then
    return 0
  fi
  return 1
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
    local tmp_file
    tmp_file="$(mktemp)" # Create a temporary file

    if curl -fsSL "${url}" -o "${tmp_file}"; then
      sync || true # Ensure file is synced to disk
      # Remove quarantine attribute for macOS consistency
      xattr -d com.apple.quarantine "${tmp_file}" 2>/dev/null || true
      mv "${tmp_file}" "${BINARY_PATH}" # Atomically move
      chmod +x "${BINARY_PATH}" || true
    else
      rm -f "${tmp_file}" # Clean up temp file on failure
      err "Failed to download binary from ${url}"
      exit 1
    fi
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

  curl -fsSL "${url}" -o "${tmp_zip}"

  # -o: overwrite existing; -d: destination directory
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
