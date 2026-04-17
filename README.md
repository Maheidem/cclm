# cclm — Claude Code via Local (or Remote) Models

A zsh launcher that bridges [Claude Code](https://claude.com/code) with an LLM of your choice — local GPU, LAN host, or remote Anthropic-compatible API — without changing how you use `claude`. Pick a model, save a profile, and drop straight into Claude Code.

Six backends are supported:

- **`lms`** — [LM Studio](https://lmstudio.ai/) (local or remote, via `lms` CLI + OpenAI-compatible API)
- **`llama`** — [llama.cpp](https://github.com/ggerganov/llama.cpp) `llama-server` (local or remote)
- **`zai`** — [Z.ai GLM](https://z.ai) remote Anthropic-compatible endpoint, with per-tier (Opus / Sonnet / Haiku) model selection
- **`remote`** — generic OpenAI-compatible remote (base URL + model name + ctx)
- **`ollama`** — [Ollama](https://ollama.com/) OpenAI-compatible endpoint (defaults to `localhost:11434`)
- **`vllm`** — [vLLM](https://github.com/vllm-project/vllm) OpenAI-compatible endpoint (defaults to `localhost:8000`)

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
cclm --vllm                # vLLM (OpenAI-compatible; default port 8000)
cclm --host <ip_or_name>   # remote host for --lms / --llama
cclm --llama --resume      # any unknown arg is passed through to claude
cclm status                # health report (last session, profiles, backend reachability) — does not launch claude
cclm edit <slug> [field]   # targeted edit of one profile field; no backend re-prompt
```

### Edit a profile field (`cclm edit`)

Change a single profile field without re-running the full backend flow. Omit the
field to get an interactive numbered picker; pass a field to edit it directly.
Matching is exact on the jq-key first, else case-insensitive substring on
key or label — ambiguous matches are rejected with the candidates listed.

```bash
cclm edit llama-qwen3                  # pick a field interactively
cclm edit llama-qwen3 ctx_len          # direct edit by jq-key
cclm edit remote-anthropic Host        # label-substring match also works
```

JSON types are preserved across edits (a numeric `context_length` stays a
number; a `null` field stays null when the new value is left empty), so
profile files remain byte-compatible with the existing parser.

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

### Per-project config (`.cclmrc`)

Drop a `.cclmrc` file at the root of a project and `cclm` will auto-select a profile whenever you run it from anywhere inside that tree. Discovery walks up from `$PWD`, stopping at the first match, at `$HOME`, or at `/` — whichever comes first. `$PWD` is honored as a logical path, so `cd`'ing through a symlink works as expected.

Format is one `key=value` per line; blank lines and `#` comments are ignored. Supported keys:

```ini
# Pin to a specific saved profile (highest-specificity option).
profile=llama-qwen3

# Or, pin only the backend and let the picker handle the profile.
# backend=lms   # one of: lms | llama | zai | remote | ollama | vllm
```

**Precedence:** CLI flags (`--lms`, `--llama`, …) > positional slug (`cclm lms-qwen3`) > `.cclmrc` > interactive picker. On a successful hit, cclm prints one diagnostic line to stderr before dispatching:

```
[cclm] using .cclmrc from /path/to/project/.cclmrc: profile=llama-qwen3
```

Malformed lines, unknown backends, or a `profile=` pointing at a non-existent file each produce a stderr warning and fall through to the picker (never a hard exit). Unknown keys warn but are otherwise ignored for forward compatibility.

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

### Benchmarking (`cclm bench`)

Compare throughput across saved profiles without launching `claude`. `cclm bench` POSTs a short prompt to `/v1/chat/completions` on each backend and reports wallclock, prompt/completion tokens, and tokens/second in a markdown-style table.

```bash
cclm bench                                            # bench every saved profile (except zai)
cclm bench --profiles lms-qwen3,ollama-llama3         # comma-separated subset
cclm bench --iterations 3                             # per-iter rows + a mean row per profile
cclm bench --prompt-file ./my-prompt.txt              # custom prompt (keep it short, <= ~50 tok)
cclm bench --dry-run                                  # print the curl commands, don't execute
```

Output goes to stdout (pipe-safe: `cclm bench | tee bench.md`); progress and skip warnings go to stderr. Exit code is 0 if at least one profile benches successfully, non-zero only if every profile fails.

| Field | Notes |
|---|---|
| `wallclock (s)` | Measured via zsh `$EPOCHREALTIME` (float seconds, sub-millisecond) |
| `prompt_tok` / `completion_tok` | Read directly from the backend's `usage.*` fields |
| `tok/s` | `completion_tok / wallclock` (includes network + queue, not server-internal throughput) |

**Auth:** no `Authorization` header is sent by default — local backends (LM Studio, llama.cpp, Ollama, vLLM) accept unauthenticated requests on localhost. For remote endpoints that require a key, set `CCLM_BENCH_API_KEY` in the environment; it is sent as `Authorization: Bearer <key>`.

**Limitations:** `zai-*.json` profiles are skipped with a stderr warning. Z.ai speaks the Anthropic-native `/v1/messages` protocol, which has a different request/response shape than OpenAI chat completions; a future pass may add native support. Profiles with missing `host` or `model` fields are also skipped. An unreachable backend is a per-profile warning, never a hard exit.

### Classic flow

When no profiles exist or you choose "New session":

1. Pick backend (lms / llama / zai / remote)
2. Depending on backend, pick or enter a model (LM Studio/llama list available; Z.ai lets you pick Opus/Sonnet/Haiku tiers separately; remote asks for model name)
3. Tune parameters (ctx, GPU layers, sampling, port, timeout…) — current profile values are used as defaults on subsequent runs
4. For local `llama.cpp`: server starts, `cclm` polls `/health`, then launches `claude` — `llama-server` is killed on exit
5. For remote hosts: `cclm` prints a copy-pasteable one-liner to run there, polls for readiness, then launches `claude`

**LM Studio auto-detection:** the `--lms` picker queries `lms ps` on start. If a model is already loaded, it becomes the default (press Enter to accept) when a saved profile exists for it; otherwise cclm offers a synthetic `0) Use currently-loaded model: …` entry at the top of the list and falls through to the usual "save new profile?" prompt. If `lms ps` fails or nothing is loaded, the picker behaves exactly as before.

## Profiles

Profiles are plain JSON files in `~/.config/cclm/`, prefixed by backend:

- **LM Studio:** `lms-<slug>.json`
- **llama.cpp:** `llama-<slug>.json`
- **Z.ai:** `zai-<name>.json`
- **Remote:** `remote-<slug>.json`
- **Ollama:** `ollama-<slug>.json`
- **vLLM:** `vllm-<slug>.json`

Each profile captures model identifiers, server parameters, and (for remote setups) the host address. On first run cclm offers to save your answers; on subsequent runs the values become defaults.

Example templates live in `profiles/examples/`.

### Profile inheritance (`extends`)

Any profile JSON may set an optional top-level `extends: "<base-slug>"` field. When cclm loads the profile it reads the base, then deep-merges the child on top (child keys override). The base must belong to the **same backend** (e.g. an `ollama-*` profile can only extend another `ollama-*`). Chains are supported up to 10 levels deep; cycles are rejected.

`~/.config/cclm/ollama-base.json`:

```json
{
  "host": "localhost",
  "port": "11434",
  "model": "llama3.1:70b",
  "context_length": 65536
}
```

`~/.config/cclm/ollama-big-ctx.json`:

```json
{
  "extends": "ollama-base",
  "context_length": 262144
}
```

Launching `ollama-big-ctx` inherits host/port/model from the base and overrides the context window. The profile picker still shows the file-literal values (so you can see at a glance what's overridden); to inspect the merged result, run `cclm profile resolve <slug>` — it prints the resolved JSON on stdout.

> Currently wired end-to-end for the `ollama` backend. Other backends still read profile files directly; `extends` is ignored there until they're migrated.

### Per-profile MCP servers

Any profile JSON may carry an optional top-level `mcp_servers` object mapping server name to server config. When cclm loads a profile that has this field, it merges the entries into `~/.claude.json`'s `mcpServers` (after backing the original up to `~/.claude.json.cclm-backup`) so Claude Code sees exactly the MCP servers you want per profile. Same-named servers are overridden by the profile — profile wins.

```json
{
  "model": "qwen/qwen3-coder-30b",
  "context_length": 200000,
  "mcp_servers": {
    "fs":     { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/src"] },
    "sqlite": { "command": "uvx", "args": ["mcp-server-sqlite", "--db-path", "/tmp/app.db"] }
  }
}
```

**Caveat — exec replaces the process.** `launch_claude` ends with `exec claude`, which replaces the cclm process with claude. That means the cclm-side EXIT trap that would roll `~/.claude.json` back never fires on a successful launch. Instead, the backup is left on disk and restored automatically at the start of the **next** cclm invocation (you'll see `cclm: restoring … from previous session backup.` on stderr). The EXIT trap only matters when cclm dies before exec — e.g. a jq failure, `--dry-run`, Ctrl-C during the merge.

**Dry run.** `cclm --dry-run` (or `--print-env`) prints the JSON that *would* be written to `~/.claude.json` and exits without touching any file or spawning claude.

## Backend notes

### Z.ai (`--zai`)

Z.ai speaks the Anthropic API, so cclm routes `claude` there via `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`. You pick three models (one per tier: Opus / Sonnet / Haiku) which are then mapped to Claude Code's model tiers:

| Claude tier | Env variable cclm sets | Typical Z.ai model |
|---|---|---|
| Opus  | `CCLM_TIER_OPUS`   | `glm-4.6` |
| Sonnet | `CCLM_TIER_SONNET` | `glm-4.6` |
| Haiku | `CCLM_TIER_HAIKU`  | `glm-4.5-air` |

The configure step will offer "same as Opus/Sonnet" shortcuts so you don't have to type the model three times.

`ZAI_API_KEY` is read from the environment. cclm will offer to save it to `~/.zshenv` on first run. For a more secure alternative, store it in your system credential store with `cclm keys add zai` — see [Credential storage](#credential-storage) below.

### Generic remote (`--remote`)

Point cclm at any OpenAI-compatible endpoint. You'll be asked for `base_url`, model name per tier, `context_length`, and `api_timeout_ms`. Stored as `remote-<slug>.json`. Before writing the profile cclm probes `<url>/v1/models` (≤2s) and confirms the chosen model id is present; if it isn't, you're prompted to save anyway. Set `CCLM_SKIP_VALIDATE=1` to bypass the probe in offline workflows.

### Ollama (`--ollama`)

Ollama exposes an OpenAI-compatible API at `http://<host>:11434/v1`. cclm prompts for `host[:port]` (default `localhost:11434`), lists available models via `/v1/models` (or falls back to manual entry), then asks for `context_length`. Stored as `ollama-<slug>.json`. Start Ollama with `ollama serve` before launching. Before writing the profile cclm probes `<url>/v1/models` (≤2s) and confirms the chosen model id is present; if it isn't, you're prompted to save anyway. Set `CCLM_SKIP_VALIDATE=1` to bypass the probe in offline workflows.

### vLLM (`--vllm`)

vLLM exposes an OpenAI-compatible API at `http://<host>:8000/v1`. cclm prompts for `host[:port]` (default `localhost:8000`), lists available models via `/v1/models` (or falls back to manual entry), then asks for `context_length`. Stored as `vllm-<slug>.json`. Start vLLM with `vllm serve <model>` (or your usual `python -m vllm.entrypoints.openai.api_server …` invocation) before launching. Before writing the profile cclm probes `<url>/v1/models` (≤2s) and confirms the chosen model id is present; if it isn't, you're prompted to save anyway. Set `CCLM_SKIP_VALIDATE=1` to bypass the probe in offline workflows.

### LM Studio / llama.cpp remote

Use `--host <ip>` with `--lms` or `--llama` to run the backend on another machine. cclm prints a copy-pasteable one-liner to run there (binding `--host 0.0.0.0` for llama.cpp, `lms server start --port …` for LM Studio) and polls for readiness.

## Credential storage

`cclm keys` stores API tokens in your OS credential store so they never touch `~/.zshenv` in plaintext.

```bash
cclm keys add zai        # prompt for secret (input hidden), store in keychain
cclm keys get zai        # print the stored secret on stdout (for scripting)
cclm keys list           # list key names only — values are never shown
cclm keys remove zai     # delete the stored entry
```

Backends are auto-detected in this order:

1. **macOS Keychain** via `security` — entries stored under the service name `cclm-<name>`.
2. **Linux libsecret** via `secret-tool` — attributes `service=cclm name=<name>`.
3. **File fallback** — `~/.config/cclm/keys/<name>` with mode `0600` in a `0700` directory, when neither CLI is available. cclm prints a stderr warning so you know you're on the fallback path.

When `run_zai` needs the Z.ai key it looks up (in order) `cclm keys get zai`, then the `ZAI_API_KEY` env var, then the file fallback. Existing users with `ZAI_API_KEY` in their shell continue to work with zero changes; migrating is as simple as `cclm keys add zai` and removing the `export` from your shell rc.

Secrets are never logged: `add`/`remove`/`list` only print status to stderr, and only `cclm keys get` emits the value — on stdout, so pipes and command substitution work cleanly.

## Environment variables

| Variable | Purpose |
|---|---|
| `CCLM_MODELS_DIR` | Override the GGUF scan directory (default: `~/.cache/lm-studio/models`) |
| `CCLM_API_TIMEOUT_MS` | Override API timeout passed to claude (default: profile value or 3000000 for remote) |
| `CCLM_TIER_OPUS` / `_SONNET` / `_HAIKU` | Set by cclm for zai/remote backends; claude reads these via `ANTHROPIC_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL` |
| `ZAI_API_KEY` | Z.ai API token — read from env (back-compat). Prefer `cclm keys add zai` for keychain storage |
| `ANTHROPIC_API_KEY` | `cclm` overrides this to `lmstudio` for local sessions; don't set manually unless your backend needs it |
| `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` | Set by cclm per backend; do not set manually |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Set by cclm to the profile's context length so claude auto-compacts at the correct boundary |

## Limitations

- **macOS-first** — tested on macOS; Linux should work (stat is OS-aware) but is not yet tested
- **No Windows support** — zsh-only script
- **Local LM Studio default model path** — `~/.cache/lm-studio/models`; override with `CCLM_MODELS_DIR`
- **No cross-backend tier routing** — Claude Code accepts exactly one `ANTHROPIC_BASE_URL` and one `ANTHROPIC_AUTH_TOKEN` per session; its HTTP client (`AO` class) is instantiated once against a single endpoint. The per-tier env vars (`ANTHROPIC_DEFAULT_OPUS_MODEL`, `_SONNET_MODEL`, `_HAIKU_MODEL`, and `CLAUDE_CODE_SUBAGENT_MODEL`) override the model **name** only — every tier's request still goes to the same base URL with the same auth. Verified in `claude` 2.1.113 (no `ANTHROPIC_BASE_URL_OPUS` / `_SONNET` / `_HAIKU` or equivalent in the binary). This means a profile cannot send, say, Opus to Z.ai and Haiku to a local llama-server in the same session. The only workaround is a local reverse proxy that inspects the `model` field of each request and fans out to distinct upstreams — out of scope for cclm, which is intentionally a launcher, not a router.
