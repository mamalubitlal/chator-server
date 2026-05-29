#!/bin/bash
# =============================================================================
# Quick Synapse DB fix — creates missing refresh_tokens table and verifies schema
# Run: sudo bash deploy/fix-synapse-db.sh
# Safe to run multiple times (idempotent)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1"; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIX_PY="${SCRIPT_DIR}/fix-refresh-tokens.py"

if [[ ! -f "${FIX_PY}" ]]; then
    error "fix-refresh-tokens.py not found at ${FIX_PY}"
fi

info "Fixing Synapse database schema..."
python3 "${FIX_PY}"

echo ""
info "Done. You can now restart Synapse:"
echo "  supervisorctl restart synapse"
echo ""
