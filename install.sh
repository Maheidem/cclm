#!/usr/bin/env bash
# cclm installer — copies bin/cclm into $HOME/.local/bin and sets up config dir.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_DIR/bin/cclm"
BIN_DST_DIR="$HOME/.local/bin"
BIN_DST="$BIN_DST_DIR/cclm"
CONFIG_DIR="$HOME/.config/cclm"
ZSH_COMP_SRC="$REPO_DIR/completions/_cclm"
BASH_COMP_SRC="$REPO_DIR/completions/cclm.bash"

# ask_yes_default <prompt>  →  returns 0 (yes) by default, 1 on explicit no.
# FORCE=1 skips the prompt and answers yes.
ask_yes_default() {
  local prompt="$1" ans
  if [[ "${FORCE:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "$prompt (Y/n): " ans || return 1
  [[ -z "$ans" || "$ans" =~ ^[Yy]$ ]]
}

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

# ── Shell completions ────────────────────────────────────────────────────────
# zsh
if [[ -f "$ZSH_COMP_SRC" ]]; then
  echo
  zsh_dst=""
  zsh_hint=""
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$brew_prefix" && -d "$brew_prefix/share/zsh/site-functions" ]]; then
      zsh_dst="$brew_prefix/share/zsh/site-functions/_cclm"
    fi
  fi
  if [[ -z "$zsh_dst" ]]; then
    zsh_dst="$HOME/.zsh/completions/_cclm"
    zsh_hint="Add this to your ~/.zshrc (before 'compinit'):
  fpath=(\"\$HOME/.zsh/completions\" \$fpath)"
  fi
  if ask_yes_default "Install zsh completion to $zsh_dst?"; then
    mkdir -p "$(dirname "$zsh_dst")"
    cp "$ZSH_COMP_SRC" "$zsh_dst"
    echo "Installed: $zsh_dst"
    [[ -n "$zsh_hint" ]] && echo "$zsh_hint"
  else
    echo "Skipped zsh completion."
  fi
fi

# bash
if [[ -f "$BASH_COMP_SRC" ]]; then
  echo
  bash_dst=""
  bash_hint=""
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="${brew_prefix:-$(brew --prefix 2>/dev/null || true)}"
    if [[ -n "$brew_prefix" && -d "$brew_prefix/etc/bash_completion.d" ]]; then
      bash_dst="$brew_prefix/etc/bash_completion.d/cclm"
    fi
  fi
  if [[ -z "$bash_dst" && -d "/etc/bash_completion.d" && -w "/etc/bash_completion.d" ]]; then
    bash_dst="/etc/bash_completion.d/cclm"
  fi
  if [[ -z "$bash_dst" ]]; then
    bash_dst="$HOME/.bash_completion.d/cclm"
    bash_hint="Add this to your ~/.bashrc:
  [[ -r \"\$HOME/.bash_completion.d/cclm\" ]] && source \"\$HOME/.bash_completion.d/cclm\""
  fi
  if ask_yes_default "Install bash completion to $bash_dst?"; then
    mkdir -p "$(dirname "$bash_dst")"
    cp "$BASH_COMP_SRC" "$bash_dst"
    echo "Installed: $bash_dst"
    [[ -n "$bash_hint" ]] && echo "$bash_hint"
  else
    echo "Skipped bash completion."
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
