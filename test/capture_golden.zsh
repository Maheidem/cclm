#!/usr/bin/env zsh
# Capture golden-file display snapshots for every display_profile_and_ask
# call-site using current code. Run BEFORE refactoring schemas; compare AFTER.

set +xeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GOLDEN_DIR="$SCRIPT_DIR/golden"
mkdir -p "$GOLDEN_DIR"

export CCLM_LIB_ONLY=1
# NOTE: bin/cclm unconditionally sets CONFIG_DIR="$HOME/.config/cclm" on source
# and runs mkdir -p on it. Never `rm -rf $CONFIG_DIR` in this script — that
# would delete user profiles. (Learned the hard way.)
MY_TMP_DIR="$(mktemp -d)"
export CONFIG_DIR="$MY_TMP_DIR"
source "$REPO_DIR/bin/cclm"
set +xeuo pipefail

capture() {
  local name="$1" profile="$2"; shift 2
  echo n | display_profile_and_ask "$profile" "$@" > /dev/null 2> "$GOLDEN_DIR/${name}.txt"
  echo "  captured: $name"
}

# LMS inner (backend picker interactive flow)
capture "lms_inner" "$SCRIPT_DIR/fixtures/lms-test.json" \
  "Context length|.context_length" \
  "GPU offload|.gpu" \
  "Parallel|.parallel"

# LMS outer (classic flow)
capture "lms_outer" "$SCRIPT_DIR/fixtures/lms-test.json" \
  "Context length|.context_length" \
  "GPU offload|.gpu" \
  "Parallel requests|.parallel" \
  "TTL (seconds)|.ttl // \"-\"" \
  "API identifier|.identifier // \"-\""

# LLAMA inner (with Model path)
capture "llama_inner" "$SCRIPT_DIR/fixtures/llama-test.json" \
  "Model path|.model_path" \
  "Context length|.ctx_len|Loading" \
  "GPU layers|.gpu_layers|Loading" \
  "Flash attention|.flash_attn|Loading" \
  "KV cache type K|.cache_type_k|Loading" \
  "KV cache type V|.cache_type_v|Loading" \
  "SWA full|.swa_full|Loading" \
  "Batch size|.batch_size|Loading" \
  "Ubatch size|.ubatch_size|Loading" \
  "Temperature|.temperature|Sampling" \
  "Top-P|.top_p|Sampling" \
  "Top-K|.top_k|Sampling" \
  "Min-P|.min_p|Sampling" \
  "Repeat penalty|.repeat_penalty|Sampling" \
  "Port|.port|Server" \
  "Parallel slots|.parallel_slots|Server" \
  "Slot save path|.slot_save_path // \"\"|Server"

# LLAMA outer (no Model path; adds Cache RAM)
capture "llama_outer" "$SCRIPT_DIR/fixtures/llama-test.json" \
  "Context length|.ctx_len|Loading" \
  "GPU layers|.gpu_layers|Loading" \
  "Flash attention|.flash_attn|Loading" \
  "KV cache type K|.cache_type_k|Loading" \
  "KV cache type V|.cache_type_v|Loading" \
  "SWA full|.swa_full|Loading" \
  "Batch size|.batch_size|Loading" \
  "Ubatch size|.ubatch_size|Loading" \
  "Temperature|.temperature|Sampling" \
  "Top-P|.top_p|Sampling" \
  "Top-K|.top_k|Sampling" \
  "Min-P|.min_p|Sampling" \
  "Repeat penalty|.repeat_penalty|Sampling" \
  "Port|.port|Server" \
  "Parallel slots|.parallel_slots|Server" \
  "Slot save path|.slot_save_path // \"\"|Server" \
  "Cache RAM (MB)|.cache_ram // \"\"|Server"

# ZAI
capture "zai" "$SCRIPT_DIR/fixtures/zai-test.json" \
  "Base URL|.base_url" \
  "Opus|.opus_model" \
  "Sonnet|.sonnet_model" \
  "Haiku|.haiku_model" \
  "Context|.context_length" \
  "Timeout|.api_timeout_ms"

echo "All golden snapshots captured to $GOLDEN_DIR"
rm -rf "$MY_TMP_DIR"
