#!/usr/bin/env python3
"""Ephemeral sessions and optional sanitized shared balance; never returns keys."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import secrets
import threading
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ORIGINS = {v.strip() for v in os.environ.get("VK1_ALLOWED_ORIGINS", "https://dash.example.test,https://localhost-dash.example.test").split(",") if v.strip()}
BALANCE_FILE = os.environ.get("VK1_BALANCE_FILE", "")
COOKIE = "vk1_session"
TTL = 12 * 3600
SESSIONS = {}
RATE = {}
LOCK = threading.RLock()
UPSTREAM = "https://api.deepseek.com/user/balance"

class Session:
    def __init__(self, key):
        self.key = key
        self.expires = time.monotonic() + TTL
        self.last = 0
        self.last_success = 0
        self.data = None
        self.lock = threading.Lock()

def fetch_balance(session):
    with session.lock:
        now = time.monotonic()
        if session.data and now - session.last < 8:
            return session.data
        request = urllib.request.Request(UPSTREAM, headers={"Authorization": "Bearer " + session.key, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=12) as response:
                raw = response.read(65537)
            if len(raw) > 65536:
                raise ValueError("size")
            body = json.loads(raw)
            rows = body.get("balance_infos", [])
            row = next((r for r in rows if r.get("currency") == "CNY"), None)
            if row is None:
                result = {"ok": False, "code": "CURRENCY", "error": "仅支持人民币余额，不将美元当作人民币"}
            else:
                value = float(row["total_balance"])
                if not math.isfinite(value) or value < 0:
                    raise ValueError("balance")
                result = {"ok": True, "totalBalance": value, "currency": "CNY", "updatedAt": datetime.now(timezone.utc).isoformat()}
        except urllib.error.HTTPError as exc:
            result = {"ok": False, "code": "AUTH" if exc.code in (401, 403) else "HTTP", "error": "密钥无效或无权限" if exc.code in (401, 403) else "余额服务暂时不可用"}
        except Exception:
            result = {"ok": False, "code": "NETWORK", "error": "余额服务连接失败，请稍后重试"}
        session.last = now
        if result.get("ok"):
            session.data = result
        elif session.data and now - session.last_success < 300:
            result = dict(session.data, stale=True)
        else:
            session.data = result
        session.data = result
        if result.get("ok") and not result.get("stale"):
            session.last_success = now
        return result

def prune():
    now = time.monotonic()
    for sid, session in list(SESSIONS.items()):
        if session.expires <= now:
            session.key = ""
            del SESSIONS[sid]
    for ip, times in list(RATE.items()):
        times[:] = [t for t in times if now - t < 60]
        if not times:
            del RATE[ip]

def shared_balance():
    """Only sanitized, short-lived balance data crosses the credential boundary."""
    missing = {"ok": False, "code": "NO_KEY", "error": "未连接余额；人物菜单中可连接 DeepSeek"}
    if not BALANCE_FILE:
        return missing
    try:
        with Path(BALANCE_FILE).open("rb") as handle:
            raw = handle.read(65537)
        if len(raw) > 65536:
            raise ValueError("size")
        data = json.loads(raw)
        if data.get("ok") is not True or data.get("currency") != "CNY":
            raise ValueError("shape")
        value = data["totalBalance"]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            raise ValueError("balance")
        updated = datetime.fromisoformat(data["updatedAt"])
        age = (datetime.now(timezone.utc) - updated).total_seconds()
        if not 0 <= age < 300:
            return {"ok": False, "code": "EXPIRED", "error": "余额同步已过期，请稍后刷新"}
        result = {"ok": True, "totalBalance": value, "currency": "CNY", "updatedAt": updated.isoformat()}
        if age > 60:
            result["stale"] = True
        return result
    except FileNotFoundError:
        return missing
    except Exception:
        return {"ok": False, "code": "SOURCE", "error": "余额同步暂时不可用"}

class Handler(BaseHTTPRequestHandler):
    server_version = "VK1"
    def log_message(self, *args):
        pass
    def output(self, data, status=200, cookie=None):
        raw = json.dumps(data, ensure_ascii=False, allow_nan=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store, private")
        self.send_header("X-Content-Type-Options", "nosniff")
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(raw)
    def sid(self):
        try:
            jar = SimpleCookie(self.headers.get("Cookie", ""))
            sid = jar[COOKIE].value if COOKIE in jar else ""
            return sid if re.fullmatch(r"[A-Za-z0-9_-]{43}", sid) else ""
        except Exception:
            return ""
    def session(self):
        with LOCK:
            prune()
            return SESSIONS.get(self.sid())
    def valid_origin(self):
        origin = self.headers.get("Origin", "")
        origin_host = self.headers.get("X-VK1-Host", self.headers.get("Host", "")).split(":")[0]
        return origin in ORIGINS and origin_host == origin.split("//")[1]
    def do_GET(self):
        if self.path == "/vk-1/api/health":
            self.output({"ok": True, "service": "vk1-balance"})
        elif self.path == "/vk-1/api/balance":
            session = self.session()
            self.output(fetch_balance(session) if session else shared_balance())
        else:
            self.output({"ok": False, "code": "NOT_FOUND"}, 404)
    def do_POST(self):
        if self.path != "/vk-1/api/session":
            self.output({"ok": False, "code": "NOT_FOUND"}, 404)
            return
        if not self.valid_origin() or self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            self.output({"ok": False, "code": "ORIGIN", "error": "仅允许同源请求"}, 403)
            return
        ip = self.headers.get("X-Real-IP", self.client_address[0])
        with LOCK:
            prune()
            attempts = RATE.setdefault(ip, [])
            if len(attempts) >= 6 or len(SESSIONS) >= 100:
                self.output({"ok": False, "code": "RATE", "error": "请求过多，请稍后重试"}, 429)
                return
            attempts.append(time.monotonic())
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 512:
                raise ValueError("length")
            body = json.loads(self.rfile.read(length))
            key = body.get("key", "")
            if not isinstance(key, str) or not re.fullmatch(r"sk-[A-Za-z0-9_-]{12,200}", key):
                raise ValueError("key")
        except Exception:
            self.output({"ok": False, "code": "KEY", "error": "请输入有效的 DeepSeek API Key"}, 400)
            return
        session = Session(key)
        result = fetch_balance(session)
        if not result.get("ok"):
            session.key = ""
            self.output(result, 400)
            return
        sid = secrets.token_urlsafe(32)
        with LOCK:
            old = SESSIONS.pop(self.sid(), None)
            if old:
                old.key = ""
            SESSIONS[sid] = session
        self.output({"ok": True}, cookie=COOKIE+"="+sid+"; Path=/vk-1/api; HttpOnly; Secure; SameSite=Strict; Max-Age="+str(TTL))
    def do_DELETE(self):
        if self.path != "/vk-1/api/session" or not self.valid_origin():
            self.output({"ok": False, "code": "ORIGIN"}, 403)
            return
        with LOCK:
            session = SESSIONS.pop(self.sid(), None)
            if session:
                session.key = ""
        self.output({"ok": True}, cookie=COOKIE+"=; Path=/vk-1/api; HttpOnly; Secure; SameSite=Strict; Max-Age=0")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18911)
    args = parser.parse_args()
    def cleanup():
        while True:
            threading.Event().wait(60)
            with LOCK:
                prune()
    threading.Thread(target=cleanup, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    server.serve_forever()

if __name__ == "__main__":
    main()
