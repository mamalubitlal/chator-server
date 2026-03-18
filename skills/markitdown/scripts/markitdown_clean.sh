#!/usr/bin/env bash
# Wrapper around markitdown that suppresses noisy onnxruntime/pydub warnings.
# Usage: markitdown_clean.sh <file> [args...]
# All arguments are forwarded to markitdown.
exec markitdown "$@" 2>/dev/null
