"""Local debug-log receiver for Car TV debug builds.

Stores Diagnostics entries POSTed by the phone in a SQLite file next to this script. LAN only, no
cloud. Debug builds of Car TV send to http://<this Mac>.local:8787/log with the shared token.

Run:   python3 -I tools/debug-log-server/server.py
Read:  sqlite3 tools/debug-log-server/logs.sqlite "select received_at, logged_at, message from logs order by logged_at"
"""
import json
import sqlite3
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
DB = HERE / "logs.sqlite"
TOKEN = (HERE / ".token").read_text().strip()
PORT = 8787


def connect():
    db = sqlite3.connect(DB)
    db.execute("""create table if not exists logs (
        id text primary key,
        device text,
        logged_at text,
        received_at text,
        message text)""")
    return db


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/log" or self.headers.get("X-Debug-Token") != TOKEN:
            return self.reply(403)
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= 1_000_000:
            return self.reply(400)
        try:
            payload = json.loads(self.rfile.read(length))
            entries = payload["entries"]
            device = str(payload.get("device", ""))[:100]
        except (ValueError, KeyError, TypeError):
            return self.reply(400)
        now = datetime.now(timezone.utc).isoformat()
        with connect() as db:
            for e in entries:
                db.execute("insert or ignore into logs values (?, ?, ?, ?, ?)",
                           (str(e["id"]), device, str(e["date"]), now, str(e["message"])[:2000]))
        print(f"{now}  +{len(entries)} entries from {device}", flush=True)
        self.reply(200)

    def do_GET(self):
        self.reply(200 if self.path == "/health" else 404)

    def reply(self, code):
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    connect().close()
    print(f"Car TV debug log receiver on :{PORT}, db {DB}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
