"""A tiny stand-in for the farm site's upload API, with faults, for Uploader tests.

    python3 mock_farm.py <folder to save into>

Prints "PORT <n>" once listening. Mirrors site/src/routes/api/upload and api/jobs/[id]/[action]:
POST /api/upload -> {id}; PUT /api/jobs/<id>/files with x-path / x-offset, 409 {size} when the offset
is not what the server has; POST /api/jobs/<id>/check. Needs the cookie "farm_session=test", which any other GET sets.
Faults: the first PUT of big.bin at a non-zero offset keeps half the body and drops the connection
(a Wi-Fi drop); the first PUT of any other file gets a 503.
"""
import json, os, sys, threading, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = sys.argv[1]
LOG = []
lock = threading.Lock()
faults = {"drop": False, "busy": False}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, status, body, cookie=False):
        data = json.dumps(body).encode()
        self.send_response(status)
        if cookie:  # the "login": the app's web view picks this up and Uploader borrows it
            self.send_header("set-cookie", "farm_session=test; Path=/")
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        return self.rfile.read(int(self.headers.get("content-length") or 0))

    def signed_in(self):
        if "farm_session=test" in (self.headers.get("cookie") or ""):
            return True
        self.body()
        self.reply(401, {"message": "Sign in again."})
        return False

    def do_POST(self):
        if not self.signed_in():
            return
        self.body()
        if self.path == "/api/upload":
            folder = urllib.parse.unquote(self.headers.get("x-folder") or "")
            LOG.append({"start": folder, "size": int(self.headers.get("x-size") or 0)})
            self.reply(200, {"id": "job1"})
        elif self.path == "/api/jobs/job1/check":
            LOG.append({"check": True})
            self.reply(200, {"ok": True})
        else:
            self.reply(404, {"message": "Not here."})

    def do_PUT(self):
        if not self.signed_in():
            return
        if self.path != "/api/jobs/job1/files":
            self.body()
            return self.reply(404, {"message": "Not here."})
        path = urllib.parse.unquote(self.headers.get("x-path") or "")
        offset = int(self.headers.get("x-offset") or 0)
        length = int(self.headers.get("content-length") or 0)
        target = os.path.join(ROOT, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with lock:
            have = os.path.getsize(target) if os.path.exists(target) else 0
            if os.path.basename(path) == "big.bin" and offset > 0 and not faults["drop"]:
                faults["drop"] = True
                half = self.rfile.read(length // 2)
                with open(target, "ab") as f:
                    f.write(half)
                LOG.append({"drop": path, "offset": offset, "kept": len(half)})
                self.close_connection = True
                self.connection.shutdown(2)
                return
            if os.path.basename(path) != "big.bin" and not faults["busy"]:
                faults["busy"] = True
                self.body()
                LOG.append({"busy": path})
                return self.reply(503, {"message": "That file is still being saved. Trying again…"})
            if offset != have:
                self.body()
                LOG.append({"conflict": path, "offset": offset, "have": have})
                return self.reply(409, {"message": "Part of that file is already on the farm.", "size": have})
            data = self.body()
            with open(target, "r+b" if offset else "wb") as f:
                f.seek(offset)
                f.write(data)
            LOG.append({"put": path, "offset": offset, "bytes": len(data)})
        self.reply(200, {"ok": True})

    def do_GET(self):
        if self.path == "/log":
            return self.reply(200, LOG)
        self.reply(200, {"ok": True, "page": self.path}, cookie=True)

    do_HEAD = do_GET


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print("PORT %d" % server.server_address[1], flush=True)
server.serve_forever()
