# cclm — Claude Code via Local Models

A zsh launcher that bridges [Claude Code](https://claude.com/code) with local LLMs served by [LM Studio](https://lmstudio.ai/) or [llama.cpp](https://github.com/ggerganov/llama.cpp) (`llama-server`). Pick a model, tune server/sampling parameters, and drop straight into Claude Code — all routed to your local GPU instead of the Anthropic API.

Also includes a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that shows live `llama-server` metrics (tokens/s, context usage, generating/idle state) in the macOS menu bar.

## Prerequisites

- [`claude`](https://claude.com/code) CLI installed and on `PATH`
- At least one backend:
  - [`lms`](https://lmstudio.ai/docs/cli) — LM Studio CLI, or
  - `llama-server` — from llama.cpp (`brew install llama.cpp` on macOS)
- `jq` and `curl`

## Install

```bash
git clone <this-repo> cclm && cd cclm
bash install.sh
```

This copies `bin/cclm` to `~/.local/bin/cclm` and creates `~/.config/cclm/`. On macOS it also offers to install the SwiftBar plugin.

Manual install:

```bash
cp bin/cclm ~/.local/bin/ && chmod +x ~/.local/bin/cclm
mkdir -p ~/.config/cclm
```

## Usage

```bash
cclm                       # profile picker (or backend picker if no profiles)
cclm --lms                 # LM Studio backend directly
cclm --llama               # llama.cpp backend directly
cclm --llama -c            # passthrough flag to claude (resume last session)
cclm --llama --resume      # passthrough --resume to claude
```

### Profile Picker

On first run with saved profiles, `cclm` shows a unified profile picker:

```
Saved profiles:

  1) [llama] Qwen3.5-27B        remote:192.168.1.100  ctx:262144
  2) [llama] gemma-4-E2B        local                 ctx:130000
  3) [lms]   qwen3.5-27b        local                 ctx:200000

  n) New session (full config)  q) Quit

Choice: 1

  [llama] Qwen3.5-27B
    o) Open/launch
    e) Edit parameters
    d) Delete
    b) Back to list

  Action [o]: ← press Enter = launch
```

Actions:
- **o (open)**: Launch immediately with saved profile settings
- **e (edit)**: Reconfigure params (current values as defaults), then launch
- **d (delete)**: Remove the profile (with confirmation)
- **n (new)**: Skip picker, use the classic backend/model selection flow

### Classic Flow

When no profiles exist or you choose "New session":

1. Pick backend (LM Studio or llama.cpp)
2. Pick or enter a model
3. Load or save a profile (stored per-model in `~/.config/cclm/`)
4. For `llama.cpp`: tune context, KV cache type, flash attention, sampling, port, etc.
5. Server starts (locally or via one-liner on a remote host), `cclm` polls `/health`, then launches `claude` with the right `ANTHROPIC_BASE_URL`

When `claude` exits, a local `llama-server` started by `cclm` is automatically killed.

## Profiles

Profiles are plain JSON files saved per-model, prefixed by backend:

- LM Studio: `~/.config/cclm/lms-<slug>.json`
- llama.cpp: `~/.config/cclm/llama-<slug>.json`
- Z.ai: `~/.config/cclm/zai-<name>.json`

Each profile stores the model path, server parameters (context length, GPU layers, sampling settings, port, etc.), and for remote setups, the host address.

See `profiles/examples/` for starter templates. The script will offer to save your answers on first launch and reload them next time.

## SwiftBar plugin (macOS)

`plugins/swiftbar/llama-monitor.5s.sh` polls `llama-server` on `localhost:8081` every 5 seconds and shows:

- **Menu bar**: `◯ idle` (green), `⚙ prefill…` (orange), or `▶ X.X tok/s` (blue, generating)
- **Dropdown**: context %, KV cache %, slot info, refresh action, open server log

Install manually:

```bash
cp plugins/swiftbar/llama-monitor.5s.sh "$HOME/Library/Application Support/SwiftBar/plugins/"
```

The plugin requires `llama-server` to be started with `--metrics` (cclm does this automatically).

## Remote servers

If you want to run `llama-server` or `lms` on a different machine (a GPU box on your LAN), pick a **remote host** at the onboarding prompt. `cclm` will:

1. Walk you through the same configuration questions
2. Print a copy-pasteable one-liner to run on the remote machine
3. Poll `http://<remote>:<port>/health` for up to 5 minutes
4. Launch `claude` once the remote server is ready

The remote one-liner uses `--host 0.0.0.0` so make sure your firewall allows the chosen port (default 8081 for llama.cpp).

## Environment variables

| Variable | Purpose |
|---|---|
| `CCLM_MODELS_DIR` | Override the GGUF scan directory (default: `~/.cache/lm-studio/models`) |
| `ANTHROPIC_API_KEY` | `cclm` overrides this to `lmstudio` for local sessions; set it yourself only if your backend needs it |

`cclm` exports `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to the real context reported by the server, so the Claude Code TUI shows the right window size.

## Limitations

- **macOS-first** — tested on macOS; Linux should work (the `stat` call is OS-aware) but is not yet tested
- **LM Studio default model path** — `~/.cache/lm-studio/models`; override with `CCLM_MODELS_DIR` if you store GGUFs elsewhere
- **SwiftBar plugin is macOS-only** — no Linux equivalent yet
- **No Windows support** — zsh-only script
