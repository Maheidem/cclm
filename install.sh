#!/usr/bin/env bash
# cclm installer — copies bin/cclm into $HOME/.local/bin and sets up config dir.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_DIR/bin/cclm"
BIN_DST_DIR="$HOME/.local/bin"
BIN_DST="$BIN_DST_DIR/cclm"
CONFIG_DIR="$HOME/.config/cclm"

echo "=== cclm installer ==="
echo

# ── Prerequisites check ──────────────────────────────────────────────────────
missing=()
for cmd in claude jq curl; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
  echo "Missing required commands: ${missing[*]}" >&2
  echo "Install them before continuing." >&2
  exit 1
fi

has_lms=0
has_llama=0
command -v lms >/dev/null 2>&1 && has_lms=1
command -v llama-server >/dev/null 2>&1 && has_llama=1
if (( has_lms == 0 && has_llama == 0 )); then
  echo "Warning: neither 'lms' (LM Studio CLI) nor 'llama-server' (llama.cpp) found in PATH." >&2
  echo "Install at least one before running cclm." >&2
fi

# ── Install binary ───────────────────────────────────────────────────────────
mkdir -p "$BIN_DST_DIR"
if [[ -f "$BIN_DST" ]] && ! cmp -s "$BIN_SRC" "$BIN_DST"; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    read -r -p "Overwrite existing $BIN_DST? (y/N): " _ow
    [[ "$_ow" =~ ^[Yy]$ ]] || { echo "Skipping binary install (re-run with FORCE=1 to bypass)."; SKIP_BIN=1; }
  fi
fi
if [[ "${SKIP_BIN:-0}" != "1" ]]; then
  cp "$BIN_SRC" "$BIN_DST"
  chmod +x "$BIN_DST"
  echo "Installed: $BIN_DST"
fi

# ── Config dir ───────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
echo "Config dir: $CONFIG_DIR"

# ── PATH hint ────────────────────────────────────────────────────────────────
case ":$PATH:" in
  *":$BIN_DST_DIR:"*) ;;
  *)
    echo
    echo "Note: $BIN_DST_DIR is not in your PATH."
    echo "Add this to your shell rc (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

echo
echo "Done. Run 'cclm' to get started."
