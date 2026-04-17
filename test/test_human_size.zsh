start_test "human_size"
# Uses locale decimal separator (, or .); assert on unit, not format.
assert_contains "$(human_size 1024)" "KB" "1024 bytes → KB"
assert_contains "$(human_size 1048576)" "MB" "1MB → MB"
assert_contains "$(human_size 1073741824)" "GB" "1GB → GB"
assert_contains "$(human_size 5368709120)" "GB" "5GB → GB"
