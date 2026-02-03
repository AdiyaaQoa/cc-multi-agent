#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# setup.sh - Compatibility Wrapper Script
# ═══════════════════════════════════════════════════════════════════════════════
# This script has been superseded by deploy.sh
# For backward compatibility, all arguments are forwarded to deploy.sh
#
# Recommended: Use ./deploy.sh directly
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/deploy.sh" "$@"
