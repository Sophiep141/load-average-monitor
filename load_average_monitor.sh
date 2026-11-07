#!/usr/bin/env bash
# load_average_monitor.sh - read /proc/loadavg and compare the 1-minute
# average against a threshold. Exits non-zero when the load is at or above
# the threshold.
#
# The library is deliberately tiny: it parses one line of a documented
# kernel interface and does one comparison. It is sourced by the test
# script and by callers who want to reuse the parsing.
#
# The 1-minute average is the first field of /proc/loadavg. The remaining
# fields (5-minute, 15-minute, runnable/total, last pid) are ignored.
#
# Why the threshold comparison is `>=` and not `>`: an operator who sets
# the threshold to 4.0 usually means "4.0 is already too much". Using `>`
# would silently allow exactly 4.0, which is the number they typed. The
# README states this decision so it is not a surprise.

set -euo pipefail

# Default path to the kernel load average file. Kept as a variable so the
# test suite can point it at a fixture without touching /proc.
LOADAVG_FILE="${LOADAVG_FILE:-/proc/loadavg}"

# read_loadavg_1min PATH
#
# Print the first field of PATH (the 1-minute load average) and nothing
# else. Returns 1 if PATH cannot be read or the first field is not a
# non-negative decimal number. We validate rather than trusting the
# kernel because the file is also used by tests and by anyone who points
# LOADAVG_FILE at a copy.
read_loadavg_1min() {
  local path="${1:-$LOADAVG_FILE}"
  local line field

  if [[ ! -r "$path" ]]; then
    printf 'load_average_monitor: cannot read %s\n' "$path" >&2
    return 1
  fi

  # Read only the first line; /proc/loadavg is a single line but a copy
  # might not be.
  IFS= read -r line < "$path" || {
    printf 'load_average_monitor: %s is empty\n' "$path" >&2
    return 1
  }

  # First whitespace-delimited field.
  field="${line%%[[:space:]]*}"

  if [[ -z "$field" ]]; then
    printf 'load_average_monitor: %s has no first field\n' "$path" >&2
    return 1
  fi

  # Reject anything that is not digits with an optional fractional part.
  # Bash's [[ =~ ]] is a builtin, so no external grep is needed.
  if [[ ! "$field" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'load_average_monitor: %s is not a load average\n' "$field" >&2
    return 1
  fi

  printf '%s\n' "$field"
}

# compare_loadavg THRESHOLD [PATH]
#
# Compare the 1-minute load average from PATH against THRESHOLD.
# Prints one of the strings "below", "at", or "above" and returns:
#   0 when the load is strictly below the threshold,
#   1 when the load is at or above the threshold,
#   2 on a usage or parse error.
#
# The three-way result is deliberate: the caller (the CLI below) only
# needs the boolean, but the tests want to distinguish "exactly equal"
# from "above" without re-implementing the comparison.
compare_loadavg() {
  local threshold="${1:-}"
  local path="${2:-$LOADAVG_FILE}"
  local load

  if [[ -z "$threshold" ]]; then
    printf 'load_average_monitor: threshold is required\n' >&2
    return 2
  fi

  if [[ ! "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'load_average_monitor: threshold %s is not a number\n' "$threshold" >&2
    return 2
  fi

  load="$(read_loadavg_1min "$path")" || return 2

  # awk is a coreutils-adjacent POSIX tool and is the simplest way to do
  # a float comparison in bash. It is used only for arithmetic, never for
  # parsing the file, so its locale behaviour cannot affect the parse.
  awk -v load="$load" -v threshold="$threshold" '
    BEGIN {
      if (load < threshold) {
        print "below"
        exit 0
      } else if (load == threshold) {
        print "at"
        exit 1
      } else {
        print "above"
        exit 1
      }
    }
  '
}

# is_overloaded THRESHOLD [PATH]
#
# Convenience wrapper: exit 0 when the 1-minute load average is below
# THRESHOLD, exit 1 when it is at or above THRESHOLD, exit 2 on error.
# This is the function a monitoring system should call.
is_overloaded() {
  local threshold="${1:-}"
  local path="${2:-$LOADAVG_FILE}"
  local result

  result="$(compare_loadavg "$threshold" "$path")" || return $?

  case "$result" in
    below) return 0 ;;
    at|above) return 1 ;;
    *)
      printf 'load_average_monitor: unexpected comparison result %s\n' "$result" >&2
      return 2
      ;;
  esac
}

# When executed rather than sourced, act as a small CLI:
#   load_average_monitor.sh THRESHOLD [PATH]
# Exits 0 when under the threshold, 1 when at or above, 2 on error.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'usage: %s THRESHOLD [PATH]\n' "$0" >&2
    exit 2
  fi
  is_overloaded "$1" "${2:-$LOADAVG_FILE}"
  exit $?
fi
