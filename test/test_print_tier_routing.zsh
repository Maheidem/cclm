start_test "print_tier_routing"
OUTPUT=$(print_tier_routing "glm-4.6" "glm-4.6" "glm-4.5-air" 2>&1)
assert_contains "$OUTPUT" "Opus" "has Opus label"
assert_contains "$OUTPUT" "Sonnet" "has Sonnet label"
assert_contains "$OUTPUT" "Haiku" "has Haiku label"
assert_contains "$OUTPUT" "glm-4.6" "has opus/sonnet model"
assert_contains "$OUTPUT" "glm-4.5-air" "has haiku model"
assert_contains "$OUTPUT" "startup" "has startup annotation"
assert_contains "$OUTPUT" "subagents" "has subagents annotation"
