#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cloudflare / fal 응답 모양을 그대로 흉내내는 시험용 서버.

우리 코드가 아니라 '진짜 응답 모양' 을 상대로 검증하기 위해 둔다.
"""
import base64, json, sys, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

PNG = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64
상태호출 = {"n": 0}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_POST(self):
        p = self.path
        n = int(self.headers.get("Content-Length") or 0)
        몸통 = json.loads(self.rfile.read(n) or b"{}")
        if "/ai/run/" in p:
            if self.headers.get("Authorization") != "Bearer testtoken":
                return self._json({"success": False, "errors": [{"message": "열쇠가 틀렸어요"}]}, 403)
            if not 몸통.get("prompt"):
                return self._json({"success": False, "errors": [{"message": "설명이 없어요"}]}, 400)
            return self._json({"success": True, "errors": [], "messages": [],
                               "result": {"image": base64.b64encode(PNG).decode()}})
        if p.startswith("/minimax/"):
            상태호출["n"] = 0
            base = "http://127.0.0.1:%d" % self.server.server_port
            return self._json({"request_id": "req1",
                               "status_url": base + "/status",
                               "response_url": base + "/result"})
        self._json({"error": "?"}, 404)

    def do_GET(self):
        if self.path == "/status":
            상태호출["n"] += 1
            # 처음엔 진행 중, 두 번째에 완료 — 기다리기가 되는지 본다
            return self._json({"status": "COMPLETED" if 상태호출["n"] >= 2 else "IN_PROGRESS"})
        if self.path == "/result":
            base = "http://127.0.0.1:%d" % self.server.server_port
            return self._json({"video": {"url": base + "/f.mp4"}})
        if self.path == "/f.mp4":
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(len(MP4)))
            self.end_headers()
            self.wfile.write(MP4)
            return
        self._json({"error": "?"}, 404)

if __name__ == "__main__":
    s = HTTPServer(("127.0.0.1", 0), H)
    sys.stdout.write("%d\n" % s.server_port)
    sys.stdout.flush()
    s.serve_forever()
