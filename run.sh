#!/usr/bin/env bash
# Meta-installer: Downloads installer, runs it, then execs the binary.
# This is for use in MCP configurations that want a single command.
set -e

# Run the installer, redirect output to stderr to keep stdout clean
curl -sSL https://conduit.design/install.sh | bash >&2

# Exec the binary with clean stdout for MCP communication
exec ~/.local/bin/conduit-mcp --stdio
