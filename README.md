# cclm — Claude Code via Local (or Remote) Models

A zsh launcher that bridges [Claude Code](https://claude.com/code) with an LLM of your choice — local GPU, LAN host, or remote Anthropic-compatible API — without changing how you use `claude`. Pick a model, save a profile, and drop straight into Claude Code.

Four backends are supported:

- **`lms`** — [LM Studio](https://lmstudio.ai/) (local or remote, via `lms` CLI + OpenAI-compatible API)
- **`llama`** — [llama.cpp](https://github.com/ggerganov/llama.cpp) `llama-server` (local or remote)
- **`zai`** — [Z.ai GLM](https://z.ai) remote Anthropic-compatible endpoint, with per-tier (Opus / Sonnet / Haiku) model selection
- **`remote`** — generic OpenAI-compatible remote (base URL + model name + ctx)

Also includes a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that shows live `llama-server` metrics (tokens/s, context usage, generating/idle state) in the macOS menu bar.

## Prerequisites

- [`claude`](https://claude.com/code) CLI on `PATH`
- `jq` and `curl`
- At least one backend tool:
  - [`lms`](https://lmstudio.ai/docs/cli) for LM Studio
  - `llama-server` from llama.cpp (`brew install llama.cpp`)
  - Z.ai or another OpenAI-compatible endpoint for the remote backends (no local tool needed)

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
cclm                       # profile picker (backend picker if no profiles)
cclm --lms                 # LM Studio backend directly
cclm --llama               # llama.cpp backend directly
cclm --zai                 # Z.ai GLM remote (tier selection)
cclm --remote              # generic OpenAI-compatible remote
cclm --host <ip_or_name>   # remote host for --lms / --llama
cclm --llama --resume      # any unknown arg is passed through to claude
```

### Profile picker

On runs with saved profiles, `cclm` shows a unified picker across all backends:

```
Saved profiles:

   1) [llama] Qwen3.5-27B        remote:192.168.1.100  ctx:262144
   2) [llama] gemma-4-E2B        local                 ctx:130000
   3) [lms]   qwen3.5-27b        local                 ctx:200000
   4) [zai]   glm-4.6            z.ai                  ctx:200000
   5) [remote] llama-3.3-70b     10.0.0.5:8080         ctx:131072

  n) New session (full config)  q) Quit

Choice: 1

  [llama] Qwen3.5-27B
    o) Open/launch
    e) Edit parameters
    d) Delete
    b) Back to list

  Action [o]: ← Enter = launch
```

Actions:

- **o (open)** — launch immediately with saved profile settings
- **e (edit)** — re-prompt all parameters with current values as defaults, then launch
- **d (delete)** — remove the profile (with confirmation)
- **n (new)** — skip the picker, use the classic backend/model selection flow

### Resume last session

On the backend picker, if there is a recorded previous session, option `0) Resume last session` appears — selecting it re-dispatches to that backend against the previously-used remote host and model. State lives at `~/.config/cclm/.last_session`.

### Classic flow

When no profiles exist or you choose "New session":

1. Pick backend (lms / llama / zai / remote)
2. Depending on backend, pick or enter a model (LM Studio/llama list available; Z.ai lets you pick Opus/Sonnet/Haiku tiers separately; remote asks for model name)
3. Tune parameters (ctx, GPU layers, sampling, port, timeout…) — current profile values are used as defaults on subsequent runs
4. For local `llama.cpp`: server starts, `cclm` polls `/health`, then launches `claude` — `llama-server` is killed on exit
5. For remote hosts: `cclm` prints a copy-pasteable one-liner to run there, polls for readiness, then launches `claude`

## Profiles

Profiles are plain JSON files in `~/.config/cclm/`, prefixed by backend:

- **LM Studio:** `lms-<slug>.json`
- **llama.cpp:** `llama-<slug>.json`
- **Z.ai:** `zai-<name>.json`
- **Remote:** `remote-<slug>.json`

Each profile captures model identifiers, server parameters, and (for remote setups) the host address. On first run cclm offers to save your answers; on subsequent runs the values become defaults.

Example templates live in `profiles/examples/`.

## Backend notes

### Z.ai (`--zai`)

Z.ai speaks the Anthropic API, so cclm routes `claude` there via `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`. You pick three models (one per tier: Opus / Sonnet / Haiku) which are then mapped to Claude Code's model tiers:

| Claude tier | Env variable cclm sets | Typical Z.ai model |
|---|---|---|
| Opus  | `CCLM_TIER_OPUS`   | `glm-4.6` |
| Sonnet | `CCLM_TIER_SONNET` | `glm-4.6` |
| Haiku | `CCLM_TIER_HAIKU`  | `glm-4.5-air` |

The configure step will offer "same as Opus/Sonnet" shortcuts so you don't have to type the model three times.

`ZAI_API_KEY` is read from the environment. cclm will offer to save it to `~/.zshenv` on first run.

### Generic remote (`--remote`)

Point cclm at any OpenAI-compatible endpoint. You'll be asked for `base_url`, model name per tier, `context_length`, and `api_timeout_ms`. Stored as `remote-<slug>.json`.

### LM Studio / llama.cpp remote

Use `--host <ip>` with `--lms` or `--llama` to run the backend on another machine. cclm prints a copy-pasteable one-liner to run there (binding `--host 0.0.0.0` for llama.cpp, `lms server start --port …` for LM Studio) and polls for readiness.

## SwiftBar plugin (macOS)

`plugins/swiftbar/llama-monitor.5s.sh` polls `llama-server` on `localhost:8081` every 5 seconds and shows:

- **Menu bar**: `◯ idle` (green), `⚙ prefill…` (orange), or `▶ X.X tok/s` (blue, generating)
- **Dropdown**: context %, KV cache %, slot info, refresh action, open server log

Install manually:

```bash
cp plugins/swiftbar/llama-monitor.5s.sh "$HOME/Library/Application Support/SwiftBar/plugins/"
```

The plugin requires `llama-server` to be started with `--metrics` (cclm does this automatically). Server log lives at `~/.cache/cclm/llama-server.log`.

## Environment variables

| Variable | Purpose |
|---|---|
| `CCLM_MODELS_DIR` | Override the GGUF scan directory (default: `~/.cache/lm-studio/models`) |
| `CCLM_API_TIMEOUT_MS` | Override API timeout passed to claude (default: profile value or 3000000 for remote) |
| `CCLM_TIER_OPUS` / `_SONNET` / `_HAIKU` | Set by cclm for zai/remote backends; claude reads these via `ANTHROPIC_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL` |
| `ZAI_API_KEY` | Z.ai API token — read from env, optionally persisted to `~/.zshenv` |
| `ANTHROPIC_API_KEY` | `cclm` overrides this to `lmstudio` for local sessions; don't set manually unless your backend needs it |
| `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` | Set by cclm per backend; do not set manually |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Set by cclm to the profile's context length so claude auto-compacts at the correct boundary |

## Limitations

- **macOS-first** — tested on macOS; Linux should work (stat is OS-aware) but is not yet tested
- **SwiftBar plugin is macOS-only**
- **No Windows support** — zsh-only script
- **Local LM Studio default model path** — `~/.cache/lm-studio/models`; override with `CCLM_MODELS_DIR`
