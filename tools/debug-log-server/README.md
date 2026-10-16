# Debug log receiver

Local-only receiver for Car TV's Diagnostics log. Debug builds (installed from Xcode, not TestFlight)
upload entries to this Mac whenever the phone is on the same network; entries recorded elsewhere (in the
car) wait on the phone and upload later.

- Start: `python3 -I tools/debug-log-server/server.py` (port 8787, stores `logs.sqlite` here)
- Read: `sqlite3 tools/debug-log-server/logs.sqlite "select logged_at, message from logs order by logged_at"`
- `CarPlayTV/Debug/DebugLogConfig.swift` (host, port, token) and `.token` are generated locally and not
  committed. A fresh clone must recreate them before a Debug build compiles.
