#!/bin/bash
# <swiftbar.title>llama-monitor</swiftbar.title>
# <swiftbar.version>v1.0.0</swiftbar.version>
# <swiftbar.desc>Monitor local llama-server (cclm) status, generation speed, and KV cache usage.</swiftbar.desc>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:$PATH"

PORT="${CCLM_PORT:-8081}"
CACHE_DIR="${CCLM_CACHE_DIR:-$HOME/.cache/cclm}"
mkdir -p "$CACHE_DIR" 2>/dev/null
STATE_FILE="${CCLM_STATE_FILE:-$CACHE_DIR/llama_monitor.state}"
LOG_FILE="${CCLM_LOG_FILE:-$CACHE_DIR/llama-server.log}"

python3 - "$PORT" "$STATE_FILE" "$LOG_FILE" <<'PYEOF'
import sys
import json
import time
import urllib.request
import urllib.error

port      = sys.argv[1]
state_f   = sys.argv[2]
log_file  = sys.argv[3]
base_url  = f"http://localhost:{port}"

# ── helpers ──────────────────────────────────────────────────────────────────

def fetch(path, timeout=2):
    try:
        with urllib.request.urlopen(f"{base_url}{path}", timeout=timeout) as r:
            return r.read().decode()
    except Exception:
        return None

def fetch_json(path, timeout=2):
    raw = fetch(path, timeout)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None

def parse_prometheus(text, name):
    """Return float value for the first matching metric name (strips labels)."""
    if not text:
        return None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#") or not line:
            continue
        # metric name may be followed by {labels} or space
        key = line.split("{")[0].split(" ")[0]
        if key == name:
            try:
                return float(line.split()[-1])
            except Exception:
                pass
    return None

def load_state():
    try:
        with open(state_f) as f:
            return json.load(f)
    except Exception:
        return {}

def save_state(data):
    try:
        with open(state_f, "w") as f:
            json.dump(data, f)
    except Exception:
        pass

def ascii_bar(frac, width=20):
    filled = int(round(frac * width))
    filled = max(0, min(width, filled))
    return "[" + "█" * filled + "░" * (width - filled) + "]"

# ── fetch data ────────────────────────────────────────────────────────────────

# Quick health check first (1s timeout)
health_raw = fetch("/health", timeout=1)
if health_raw is None:
    # Server is offline
    print("■ llama | color=#888888 font=Menlo size=11")
    print("---")
    print(f"Server offline (port {port})")
    print("---")
    print("Refresh | refresh=true")
    sys.exit(0)

# Server is up — fetch slots and metrics in parallel-ish
slots_data   = fetch_json("/slots", timeout=2)
metrics_text = fetch("/metrics", timeout=2)
now          = time.time()

# ── parse slots ───────────────────────────────────────────────────────────────

n_slots       = 0
busy_slots    = 0
is_processing = False
n_decoded     = 0
n_predict     = 0

if slots_data and isinstance(slots_data, list):
    n_slots = len(slots_data)
    for s in slots_data:
        state = s.get("state", 0)
        # state 1 (int) or "PROCESSING"/"GENERATING" (newer builds) = processing
        state_str = str(state).upper() if state is not None else ""
        if state == 1 or state_str in ("PROCESSING", "GENERATING", "BUSY"):
            busy_slots += 1
            is_processing = True
            n_decoded = s.get("n_decoded", s.get("tokens_predicted", 0))
            n_predict = s.get("n_predict", 0)

# ── parse metrics (Prometheus) ────────────────────────────────────────────────

kv_tokens      = parse_prometheus(metrics_text, "llamacpp:kv_cache_tokens_count")
kv_max         = parse_prometheus(metrics_text, "llamacpp:kv_cache_max_tokens")
tokens_total   = parse_prometheus(metrics_text, "llamacpp:tokens_predicted_total")

# ── tok/s calculation via state file ─────────────────────────────────────────

state        = load_state()
prev_ts      = state.get("ts", 0)
prev_tokens  = state.get("tokens_predicted", 0)

toks_per_sec = None
if tokens_total is not None and prev_ts > 0 and tokens_total > prev_tokens:
    dt = now - prev_ts
    if dt > 0.1:
        toks_per_sec = (tokens_total - prev_tokens) / dt

# Save new state
save_state({"ts": now, "tokens_predicted": int(tokens_total) if tokens_total is not None else prev_tokens})

# ── determine menu bar label ──────────────────────────────────────────────────

if not is_processing:
    menubar = "◯ idle | color=#7dbb7d font=Menlo size=11"
elif n_decoded < 5:
    menubar = "⚙ prefill… | color=#e8922e font=Menlo size=11"
elif toks_per_sec is not None:
    menubar = f"▶ {toks_per_sec:.1f}/s | color=#4a9eff font=Menlo size=11"
else:
    menubar = "▶ gen | color=#4a9eff font=Menlo size=11"

print(menubar)
print("---")
print(f"llama-server · port {port} · {'running' if is_processing else 'idle'}")
print("---")

# ── generation details ────────────────────────────────────────────────────────

if is_processing:
    if n_predict and n_predict > 0:
        pct = min(100, int(n_decoded / n_predict * 100))
        print(f"Tokens: {n_decoded:,} / {n_predict:,} ({pct}%)")
        if toks_per_sec and toks_per_sec > 0:
            remaining = (n_predict - n_decoded) / toks_per_sec
            print(f"Speed: {toks_per_sec:.1f} tok/s · ETA {remaining:.0f}s")
        elif toks_per_sec is not None:
            print(f"Speed: {toks_per_sec:.1f} tok/s")
    else:
        print(f"Tokens decoded: {n_decoded:,}")
        if toks_per_sec is not None:
            print(f"Speed: {toks_per_sec:.1f} tok/s")

# ── KV cache ─────────────────────────────────────────────────────────────────

if kv_tokens is not None:
    kv_t = int(kv_tokens)
    if kv_max is not None and kv_max > 0:
        kv_m   = int(kv_max)
        kv_pct = min(100, int(kv_t / kv_m * 100))
        bar    = ascii_bar(kv_t / kv_m)
        print(f"KV cache: {kv_t:,} / {kv_m:,} ({kv_pct}%)")
        print(f"{bar} | font=Menlo size=10")
    else:
        print(f"KV cache: {kv_t:,} tokens")
else:
    print("KV cache: n/a (restart server to enable --metrics)")

# ── slots ─────────────────────────────────────────────────────────────────────

if n_slots > 0:
    print(f"Slots: {busy_slots}/{n_slots} busy")

# ── footer ────────────────────────────────────────────────────────────────────

print("---")
print("Refresh | refresh=true")
print(f"Open log | bash=tail param1=-f param2={log_file} terminal=true")

PYEOF
