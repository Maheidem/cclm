#!/usr/bin/env bash
# cclm installer — copies bin/cclm into $HOME/.local/bin and sets up config dir.
# Optionally installs the SwiftBar monitoring plugin on macOS.

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
cp "$BIN_SRC" "$BIN_DST"
chmod +x "$BIN_DST"
echo "Installed: $BIN_DST"

# ── Config dir ───────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
echo "Config dir: $CONFIG_DIR"

# ── Optional SwiftBar plugin (macOS only) ────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  SWIFTBAR_DIR="$HOME/Library/Application Support/SwiftBar/plugins"
  if [[ -d "$SWIFTBAR_DIR" ]]; then
    read -r -p "Install SwiftBar llama-server monitor plugin? (y/N): " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      cp "$REPO_DIR/plugins/swiftbar/llama-monitor.5s.sh" "$SWIFTBAR_DIR/"
      chmod +x "$SWIFTBAR_DIR/llama-monitor.5s.sh"
      echo "Installed SwiftBar plugin to: $SWIFTBAR_DIR/llama-monitor.5s.sh"
      echo "Refresh SwiftBar (menu bar icon → Refresh all) to activate it."
    fi
  else
    echo "SwiftBar not detected at $SWIFTBAR_DIR — skipping plugin."
  fi
fi

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
