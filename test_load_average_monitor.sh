#!/usr/bin/env bash
# Tests for load_average_monitor.sh. Run with: bash test_load_average_monitor.sh
#
# The tests use fixture files rather than /proc so they are deterministic
# and do not depend on the machine's actual load.

set -euo pipefail

# Resolve the directory of this script so the test works from anywhere.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=load_average_monitor.sh
source "$TEST_DIR/load_average_monitor.sh"

# assert_eq EXPECTED ACTUAL LABEL
# Print a TAP-like line and exit non-zero on mismatch. The exit is
# deliberate: a failing assertion must stop the suite so the first
# failure is visible.
assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok - %s\n' "$label"
  else
    printf 'not ok - %s\n' "$label"
    printf '  expected: %q\n' "$expected"
    printf '  actual:   %q\n' "$actual"
    exit 1
  fi
}

# assert_exit EXPECTED ACTUAL LABEL
assert_exit() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    printf 'ok - %s\n' "$label"
  else
    printf 'not ok - %s\n' "$label"
    printf '  expected exit: %d\n' "$expected"
    printf '  actual exit:   %d\n' "$actual"
    exit 1
  fi
}

# Create a temporary directory for fixtures.
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Fixture: a normal /proc/loadavg line.
printf '0.50 0.60 0.70 1/234 5678\n' > "$TMPDIR_TEST/loadavg_normal"
# Fixture: exactly at the threshold.
printf '4.00 3.90 3.80 1/234 5678\n' > "$TMPDIR_TEST/loadavg_at"
# Fixture: above the threshold.
printf '4.01 3.90 3.80 1/234 5678\n' > "$TMPDIR_TEST/loadavg_above"
# Fixture: a copy with trailing whitespace and extra spaces between fields.
printf '1.25   0.10 0.20 1/1 1\n' > "$TMPDIR_TEST/loadavg_spaces"
# Fixture: empty file.
: > "$TMPDIR_TEST/loadavg_empty"
# Fixture: garbage first field.
printf 'not-a-number 0 0 0/0 0\n' > "$TMPDIR_TEST/loadavg_garbage"

# --- read_loadavg_1min -------------------------------------------------

assert_eq "0.50" "$(read_loadavg_1min "$TMPDIR_TEST/loadavg_normal")" \
  'read_loadavg_1min returns the first field'

assert_eq "1.25" "$(read_loadavg_1min "$TMPDIR_TEST/loadavg_spaces")" \
  'read_loadavg_1min tolerates extra whitespace'

set +e
read_loadavg_1min "$TMPDIR_TEST/loadavg_empty" >/dev/null 2>&1
rc=$?
set -e
assert_exit 1 "$rc" 'read_loadavg_1min rejects an empty file'

set +e
read_loadavg_1min "$TMPDIR_TEST/loadavg_garbage" >/dev/null 2>&1
rc=$?
set -e
assert_exit 1 "$rc" 'read_loadavg_1min rejects a non-numeric first field'

set +e
read_loadavg_1min "$TMPDIR_TEST/does-not-exist" >/dev/null 2>&1
rc=$?
set -e
assert_exit 1 "$rc" 'read_loadavg_1min rejects a missing file'

# --- compare_loadavg ---------------------------------------------------

assert_eq "below" "$(compare_loadavg 1.0 "$TMPDIR_TEST/loadavg_normal")" \
  'compare_loadavg reports below when load < threshold'

assert_eq "at" "$(compare_loadavg 4.00 "$TMPDIR_TEST/loadavg_at")" \
  'compare_loadavg reports at when load equals threshold'

assert_eq "above" "$(compare_loadavg 4.00 "$TMPDIR_TEST/loadavg_above")" \
  'compare_loadavg reports above when load exceeds threshold'

set +e
compare_loadavg "" "$TMPDIR_TEST/loadavg_normal" >/dev/null 2>&1
rc=$?
set -e
assert_exit 2 "$rc" 'compare_loadavg rejects an empty threshold'

set +e
compare_loadavg "abc" "$TMPDIR_TEST/loadavg_normal" >/dev/null 2>&1
rc=$?
set -e
assert_exit 2 "$rc" 'compare_loadavg rejects a non-numeric threshold'

# --- is_overloaded -----------------------------------------------------

set +e
is_overloaded 1.0 "$TMPDIR_TEST/loadavg_normal" >/dev/null 2>&1
rc=$?
set -e
assert_exit 0 "$rc" 'is_overloaded returns 0 when below threshold'

set +e
is_overloaded 4.00 "$TMPDIR_TEST/loadavg_at" >/dev/null 2>&1
rc=$?
set -e
assert_exit 1 "$rc" 'is_overloaded returns 1 when exactly at threshold'

set +e
is_overloaded 4.00 "$TMPDIR_TEST/loadavg_above" >/dev/null 2>&1
rc=$?
set -e
assert_exit 1 "$rc" 'is_overloaded returns 1 when above threshold'

set +e
is_overloaded 1.0 "$TMPDIR_TEST/loadavg_garbage" >/dev/null 2>&1
rc=$?
set -e
assert_exit 2 "$rc" 'is_overloaded returns 2 on a parse error'

printf '1..%d\n' 13
