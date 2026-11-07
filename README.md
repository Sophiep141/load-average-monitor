# load-average-monitor

Reads `/proc/loadavg` and exits non-zero when the one-minute load average is at or above a configurable threshold.

## Usage

```bash
source load_average_monitor.sh

# Exit status: 0 below threshold, 1 at or above, 2 on error.
is_overloaded 4.0

# Or point it at a file (useful in tests and containers):
is_overloaded 4.0 /tmp/loadavg.copy
```

The script can also be run directly:

```bash
./load_average_monitor.sh 4.0
./load_average_monitor.sh 4.0 /tmp/loadavg.copy
```

## API

- `read_loadavg_1min [PATH]` — prints the first field of `PATH` (default `$LOADAVG_FILE` or `/proc/loadavg`) and returns 1 if the file is unreadable, empty, or the first field is not a non-negative decimal number.
- `compare_loadavg THRESHOLD [PATH]` — prints `below`, `at`, or `above` and returns 0 for below, 1 for at-or-above, 2 on a usage or parse error.
- `is_overloaded THRESHOLD [PATH]` — returns 0 when below the threshold, 1 when at or above, 2 on error.

The default path is taken from the `LOADAVG_FILE` environment variable, falling back to `/proc/loadavg`. This keeps the library portable to containers that mount a copy of the file.

## Why this exists

A monitoring check that shells out to `uptime` and parses its output is fragile: the format varies between coreutils versions, and `uptime` may not be installed in a minimal container. `/proc/loadavg` is a stable kernel interface with a documented format, and reading it needs nothing beyond bash builtins and one `awk` call for the float comparison. The trade-off is that this only works on Linux; on other systems the caller must supply a compatible file via `PATH` or `LOADAVG_FILE`.

## The awkward edge

The threshold comparison is `>=`, not `>`. If you set the threshold to `4.0`, a load of exactly `4.0` counts as overloaded. This matches the way operators usually phrase the check ("alert when load reaches 4") and is stated here because it is the one place where a reasonable person might expect `>` instead.

## Tests

```bash
bash test_load_average_monitor.sh
```

The tests use fixture files and never read the real `/proc/loadavg`, so they are deterministic and do not depend on the machine's load.
