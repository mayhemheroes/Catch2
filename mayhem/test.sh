#!/usr/bin/env bash
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

runner="build-tests/tests/SelfTest"
if [ ! -x "$runner" ]; then
  echo "SelfTest runner missing at $runner (build.sh should have built it)" >&2
  emit_ctrf "catch2-selftest" 0 1 0
  exit $?
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
set +e
"$runner" >"$log" 2>&1
rc=$?
set -e
out="$(cat "$log")"

passed=0 failed=0 skipped=0
if echo "$out" | grep -qE 'All tests passed \([0-9]+ assertions in [0-9]+ test cases\)'; then
  passed="$(echo "$out" | sed -nE 's/.*All tests passed \([0-9]+ assertions in ([0-9]+) test cases\).*/\1/p' | tail -1)"
  failed=0
elif echo "$out" | grep -qE 'test cases:[[:space:]]+[0-9]+[[:space:]]+[|][[:space:]]+[0-9]+[[:space:]]+passed'; then
  line="$(echo "$out" | grep -E 'test cases:' | tail -1)"
  total="$(echo "$line" | sed -nE 's/.*test cases:[[:space:]]+([0-9]+).*/\1/p')"
  passed="$(echo "$line" | sed -nE 's/.*[|][[:space:]]+([0-9]+)[[:space:]]+passed.*/\1/p')"
  # Catch2 prints "N failed as expected" for MAYFAIL cases — treat as 0 unexpected failures.
  if echo "$line" | grep -q 'failed as expected'; then
    failed=0
  else
    failed="$(echo "$line" | sed -nE 's/.*[|][[:space:]]+([0-9]+)[[:space:]]+failed.*/\1/p')"
  fi
  skipped="$(echo "$line" | sed -nE 's/.*[|][[:space:]]+([0-9]+)[[:space:]]+skipped.*/\1/p')"
  [ -z "$failed" ] && failed=0
  [ -z "$skipped" ] && skipped=0
  if [ -z "$passed" ] && [ -n "$total" ]; then
    passed=$(( total - failed - skipped ))
  fi
else
  echo "Could not parse Catch2 SelfTest output (exit $rc):" >&2
  tail -20 "$log" >&2
  emit_ctrf "catch2-selftest" 0 1 0
  exit $?
fi

if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then
  failed=1
  [ "$passed" -eq 0 ] && passed=0
fi

emit_ctrf "catch2-selftest" "$passed" "$failed" "$skipped"
exit $?
