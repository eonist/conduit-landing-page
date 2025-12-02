#!/usr/bin/env pwsh
# Meta-installer: Downloads installer, runs it, then execs the binary.
# This is for use in MCP configurations that want a single command.
$ErrorActionPreference = "Stop"

# Run the installer, redirect all of its output streams to stderr to keep stdout clean.
$scriptContent = (Invoke-WebRequest -Uri 'https://conduit.design/install.ps1' -UseBasicParsing).Content
Invoke-Expression $scriptContent *>&2

# Exec the binary with a clean stdout for MCP communication.
# The '&' call operator is used to execute the command.
& "$env:USERPROFILE\.local\bin\conduit-mcp.exe" --stdio
