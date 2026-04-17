# cclm — Claude Code via Local (or Remote) Models

A zsh launcher that bridges [Claude Code](https://claude.com/code) with an LLM of your choice — local GPU, LAN host, or remote Anthropic-compatible API — without changing how you use `claude`. Pick a model, save a profile, and drop straight into Claude Code.

Five backends are supported:

- **`lms`** — [LM Studio](https://lmstudio.ai/) (local or remote, via `lms` CLI + OpenAI-compatible API)
- **`llama`** — [llama.cpp](https://github.com/ggerganov/llama.cpp) `llama-server` (local or remote)
- **`zai`** — [Z.ai GLM](https://z.ai) remote Anthropic-compatible endpoint, with per-tier (Opus / Sonnet / Haiku) model selection
- **`remote`** — generic OpenAI-compatible remote (base URL + model name + ctx)
- **`ollama`** — [Ollama](https://ollama.com/) OpenAI-compatible endpoint (defaults to `localhost:11434`)

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

This copies `bin/cclm` to `~/.local/bin/cclm` and creates `~/.config/cclm/`.

Manual install:

```bash
cp bin/cclm ~/.local/bin/ && chmod +x ~/.local/bin/cclm
mkdir -p ~/.config/cclm
```

### Shell completion

`install.sh` offers (default Yes) to install completions from `completions/`:

- **zsh** — on macOS with Homebrew present, `_cclm` is copied to
  `$(brew --prefix)/share/zsh/site-functions/`. Otherwise it goes to
  `~/.zsh/completions/_cclm`; in that case add the dir to `$fpath` in your
  `~/.zshrc` before `compinit`:

  ```zsh
  fpath=("$HOME/.zsh/completions" $fpath)
  autoload -U compinit && compinit
  ```

- **bash** — copied to `$(brew --prefix)/etc/bash_completion.d/cclm`
  (Homebrew) or `/etc/bash_completion.d/cclm` when writable, else
  `~/.bash_completion.d/cclm`. In the last case, source it from `~/.bashrc`:

  ```bash
  [[ -r "$HOME/.bash_completion.d/cclm" ]] && source "$HOME/.bash_completion.d/cclm"
  ```

Completions cover the top-level flags (`--lms --llama --zai --remote --host=
--resume --dry-run --print-env`), profile slugs taken from
`~/.config/cclm/*.json`, and recently-used hosts (from
`~/.config/cclm/.last_session`) after `--host=`. Test it manually with:

```bash
cclm <TAB>             # flags and profile slugs
cclm --host=<TAB>      # recent hosts
```

## Usage

```bash
cclm                       # profile picker (backend picker if no profiles)
cclm --lms                 # LM Studio backend directly
cclm --llama               # llama.cpp backend directly
cclm --zai                 # Z.ai GLM remote (tier selection)
cclm --remote              # generic OpenAI-compatible remote
cclm --ollama              # Ollama (OpenAI-compatible; default port 11434)
cclm --host <ip_or_name>   # remote host for --lms / --llama
cclm --llama --resume      # any unknown arg is passed through to claude
cclm status                # health report (last session, profiles, backend reachability) — does not launch claude
```

### Status (`cclm status`)

Prints a non-interactive health report and exits — useful for quick checks or piping into scripts:

```
Last session:
  backend:      llama
  profile:      llama-qwen3-27b.json
  model:        Qwen3.5-27B
  remote_host:  192.168.1.100

Saved profiles (grouped by backend):
  [lms] (2)
    - qwen3-27b                              ctx:131072
    - gemma-4-e2b                            ctx:65536
  [llama] (1)
    - qwen3-27b                              ctx:262144

Backend reachability:
  localhost:1234                           ✓ UP
  localhost:8081                           ✗ DOWN
  localhost:11434                          ✗ DOWN
  192.168.1.100:8081                       ✓ UP
```

Section headers go to stderr; data rows to stdout, so `cclm status | grep UP` works. Probes use a 1s timeout per endpoint and never hard-fail if a backend is down.

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

### Session log

Every real launch (not `--dry-run`) appends one JSONL record to `~/.cache/cclm/sessions.log` with:

```json
{"ts_start":"2026-04-17T14:32:11Z","backend":"llama","profile_basename":"llama-qwen3.json","host":"localhost","model":"qwen3","pid":12345}
```

Only `ts_start` is recorded. `cclm` ends with `exec claude`, which replaces the current process — nothing can run after that, so there is no `ts_end`. The log is append-only; cclm never rotates or deletes entries.

Summarize with `cclm log`:

```bash
cclm log                    # last 10 sessions, tabular
cclm log --last 7d          # filter to sessions within the last N days
cclm log --profile qwen3    # substring match against profile_basename
cclm log --json             # dump raw JSONL (combines with filters above)
```

If the log file does not exist yet, `cclm log` prints `No sessions logged yet.` and exits 0. Override the log location with `CCLM_CACHE_DIR=/some/path` (the file is always `$CCLM_CACHE_DIR/sessions.log`).

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
- **Ollama:** `ollama-<slug>.json`

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

### Ollama (`--ollama`)

Ollama exposes an OpenAI-compatible API at `http://<host>:11434/v1`. cclm prompts for `host[:port]` (default `localhost:11434`), lists available models via `/v1/models` (or falls back to manual entry), then asks for `context_length`. Stored as `ollama-<slug>.json`. Start Ollama with `ollama serve` before launching.

### LM Studio / llama.cpp remote

Use `--host <ip>` with `--lms` or `--llama` to run the backend on another machine. cclm prints a copy-pasteable one-liner to run there (binding `--host 0.0.0.0` for llama.cpp, `lms server start --port …` for LM Studio) and polls for readiness.

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
- **No Windows support** — zsh-only script
- **Local LM Studio default model path** — `~/.cache/lm-studio/models`; override with `CCLM_MODELS_DIR`
