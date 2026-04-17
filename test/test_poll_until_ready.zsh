start_test "poll_until_ready"

# Spin up a tiny HTTP server that returns JSON at /health.json
PORT=$(( 20000 + RANDOM % 10000 ))
SERVER_ROOT=$(mktemp -d)
echo '{"status":"ok"}' > "$SERVER_ROOT/health.json"
( cd "$SERVER_ROOT" && python3 -m http.server "$PORT" >/dev/null 2>&1 ) &
SERVER_PID=$!

# Give server time to bind
for _ in 1 2 3 4 5; do
  curl -sf --max-time 1 "http://127.0.0.1:${PORT}/health.json" >/dev/null 2>&1 && break
  sleep 0.3
done

# Poll succeeds quickly
RC=0
OUTPUT=$(poll_until_ready "http://127.0.0.1:${PORT}/health.json" '.status == "ok"' 5 1 "test-server" 2>&1) || RC=$?
assert_exit 0 $RC "returns 0 when server ready"
assert_contains "$OUTPUT" "ready" "emits 'ready'"

# Poll against nonexistent port times out
RC=0
OUTPUT=$(poll_until_ready "http://127.0.0.1:1/health" '.status == "ok"' 2 1 "dead-server" 2>&1) || RC=$?
assert_exit 1 $RC "returns 1 on timeout"
assert_contains "$OUTPUT" "Timed out" "emits timeout message"

kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null
rm -rf "$SERVER_ROOT"
