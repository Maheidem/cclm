# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

cclm is a single-file zsh script (`bin/cclm`, ~1980 lines) that bridges [Claude Code](https://claude.com/code) with local or remote LLM backends without changing how you use `claude`. It provides six backends: LM Studio, llama.cpp (llama-server), Z.ai GLM, a generic OpenAI-compatible remote, Ollama, and vLLM. Profiles are saved as plain JSON in `~/.config/cclm/` for reuse via a unified profile picker.

## Commands

### Install
```bash
git clone <repo> cclm && cd cclm
FORCE=1 bash install.sh          # skip overwrite prompt
# or manual: cp bin/cclm ~/.local/bin/ && chmod +x ~/.local/bin/cclm && mkdir -p ~/.config/cclm
```

### Run (from repo root, useful for development/testing)
```bash
./bin/cclm                      # profile picker
./bin/cclm --lms                # LM Studio direct
./bin/cclm --llama              # llama.cpp direct  
./bin/cclm --zai                # Z.ai GLM remote
./bin/cclm --remote             # generic OpenAI-compatible remote
./bin/cclm --ollama             # Ollama (OpenAI-compatible, default port 11434)
./bin/cclm --vllm               # vLLM (OpenAI-compatible, default port 8000)
./bin/cclm --host 192.168.1.50  # remote host for local backends
```

No build, lint, or test steps exist — this is a zsh script with no test framework. Debug by running `./bin/cclm` directly and inspecting stderr output (all prompts go to stderr). Use `zsh -n bin/cclm` for syntax checks (bash -n fails on zsh-specific constructs like `(N)` nullglob qualifiers).

## Architecture

### Single-file design (`bin/cclm`)
All logic lives in one zsh script organized into these sections:

1. **Setup & helpers** — portability shims (macOS/Linux stat), `slug()`, `ask()`, `human_size()`, plus three shared helpers used across backends: `display_profile_and_ask()` (prints a saved profile and returns 0/1 on accept/reject), `poll_until_ready()` (curl+jq polling loop), `print_tier_routing()` (Opus/Sonnet/Haiku routing display). `schema_display` is a thin wrapper over `display_profile_and_ask` for use with `*_PROFILE_SCHEMA` arrays.
1a. **Profile schemas** — top-level `LMS_PROFILE_SCHEMA`, `LMS_PROFILE_SCHEMA_BRIEF`, `LLAMA_PROFILE_SCHEMA`, `LLAMA_PROFILE_SCHEMA_WITH_PATH`, `ZAI_PROFILE_SCHEMA`, `REMOTE_PROFILE_SCHEMA`, `OLLAMA_PROFILE_SCHEMA`, `VLLM_PROFILE_SCHEMA` arrays of `"label|jq_filter[|group]"` specs. Each backend's display site calls `schema_display "$profile" "${SCHEMA[@]}"` rather than inlining specs. Golden-file tests in `test/golden/` pin the display output.
2. **Session state** — `load_last_session()` / `save_last_session()` read/write JSON to `~/.config/cclm/.last_session`
3. **Profile migration** — on startup, auto-renames old-format profiles (bare `<slug>.json` → `lms-<slug>.json`) and backfills the `remote_host` field in llama profiles via jq (backward compat)
4. **Argument parsing** — handles `--lms`, `--llama`, `--zai`, `--remote`, `--host=`, and passthrough args
5. **Profile picker** (`pick_profile()`) — unified list across all backends with open/edit/delete actions; sets `_PRELOADED_PROFILE` / `_PRELOADED_ACTION` globals
6. **Backend functions** — six independent functions (`run_lms`, `run_llama`, `run_zai`, `run_remote`, `run_ollama`, `run_vllm`) that each follow the same pattern:
   - Preload fast-path (from profile picker) → skip prompts, read saved JSON, set env vars, call `launch_claude`
   - Edit mode (from profile picker) → fall through to full flow with defaults pre-filled
   - Interactive config → prompt user, save new profile, call `launch_claude`
7. **`launch_claude()`** — the core function that sets all environment variables (`ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, per-tier routing via `CCLM_TIER_*`) and execs/replaces into `claude`. Also strips auth tokens (sets to `lmstudio` for local), disables telemetry/adaptive thinking, and configures context limits.

### Environment variables
cclm manages all Claude Code env vars internally:
- **Auth**: For local backends → `ANTHROPIC_API_KEY=lmstudio`; for remote/Z.ai → `ANTHROPIC_AUTH_TOKEN` from real key (then cleared)
- **Model routing**: Sets `ANTHROPIC_DEFAULT_OPUS_MODEL`, `_SONNET_MODEL`, `_HAIKU_MODEL` per tier (same model for local backends, distinct for Z.ai/remote with per-tier support)
- **Context**: `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` from profile's ctx length

### Profiles
Plain JSON in `~/.config/cclm/` prefixed by backend. Any profile may also set an optional top-level `extends: "<base-slug>"` field to inherit from another profile of the same backend (deep-merge, child wins — see `_cclm_profile_resolve`).
- LM Studio: `lms-<slug>.json` — fields: `model`, `context_length`, `gpu`, `parallel`, `ttl`, `identifier`
- llama.cpp: `llama-<slug>.json` — fields: `model`, `ctx_len`, `gpu_layers`, `flash_attn`, `cache_type_*`, `swa_full`, `batch_size`, `temperature`, `port`, `parallel_slots`, etc.
- Z.ai: `zai-<name>.json` — fields: `base_url`, `opus_model`, `sonnet_model`, `haiku_model`, `context_length`, `api_timeout_ms`
- Remote: `remote-<slug>.json` — fields: `host`, `port`, `model`, `context_length`
- Ollama: `ollama-<slug>.json` — fields: `host`, `port` (default `"11434"`), `model`, `context_length`
- vLLM: `vllm-<slug>.json` — fields: `host`, `port` (default `"8000"`), `model`, `context_length`

All profiles accept an optional `extends: "<base-slug>"` field (same-prefix parent required; resolution handled by `_cclm_profile_resolve`). Currently only the `ollama` backend consumes resolved JSON end-to-end via `_cclm_read_profile`; other backends still cat the file literally but can migrate incrementally (see `run_ollama`'s preload fast-path for the pattern).

Example templates in `profiles/examples/`.

## Testing

```bash
zsh test/run.sh              # 37 assertions covering helpers, migration, schemas
CCLM_STRICT=1 zsh test/run.sh # run under warn_create_global for missing local decls
```

Sources `bin/cclm` with `CCLM_LIB_ONLY=1` to skip main execution. Golden-file tests in `test/golden/` pin `schema_display` output byte-for-byte — never edit them manually; regenerate via `zsh test/capture_golden.zsh` if a schema intentionally changes.

**WARNING**: `bin/cclm` unconditionally sets `CONFIG_DIR="$HOME/.config/cclm"` and `mkdir -p`s it on source. Never `rm -rf "$CONFIG_DIR"` in a test/helper script after sourcing — that deletes user profiles. Use a locally-captured `MY_TMP_DIR` for teardown.

## Key patterns when editing bin/cclm
- All user prompts go to **stderr** (`>&2`); stdout is not used (claude doesn't read stdin)
- Profiles are always loaded/parsed via `jq`; never parse JSON manually in zsh
- The preload fast-path checks `_PRELOADED_PROFILE` and `_PRELOADED_ACTION` globals first — any backend modification must preserve this path for profile picker to work
- `launch_claude()` is the single point where env vars are set before invoking `claude`; modifications here affect all backends
- **Fragility warning**: ~1800-line single zsh file with duplicated backend logic is hard to maintain. Extract common patterns into helpers.
- **Helper signature pattern**: Since zsh lacks keyword args, use pipe-delimited field-spec strings like `"label|jq_filter|group"` for helper params. Callers must pass ONE arg per field — don't try to encode groups as alternating args (this was a real bug caught in review).
- **zsh scoping gotcha**: Variables assigned in a function without `local` become **global** in zsh. Always declare `local foo=false` before conditional assignment blocks like `if ...; then foo=true; fi` — otherwise state leaks across backend function calls.
- **Contract over complexity**: Rather than forcing complex signatures on `launch_claude()`, document the contract (callers must set `CCLM_*` vars before calling) — this is simpler and effective.
- **Net dedup reality**: Helper extraction savings are often offset ~30% by doc comments, edge-case guards, and spacing in zsh helpers. Still worth it for bugs caught.
