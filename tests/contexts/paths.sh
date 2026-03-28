#!/usr/bin/env sh
# tests/contexts/paths.sh — FHS path compatibility context
#
# Currently a no-op. Tests use $(whence -p) for command discovery
# and the DEFPATH mechanism ensures `command -p` works on NixOS.
#
# This hook exists for future path redirect needs (symlink farm,
# LD_PRELOAD libredirect, etc.) if tests are added that require
# hardcoded FHS paths.

return 0
